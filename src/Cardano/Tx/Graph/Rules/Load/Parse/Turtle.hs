{- |
Module      : Cardano.Tx.Graph.Rules.Load.Parse.Turtle
Description : Structural Turtle parser for the operator-authored rules subset.
License     : Apache-2.0

Parses a canonical @rules.ttl@ byte blob into an in-memory
@['EntityDecl']@ list — the same shape the YAML compiler produces.
Downstream, the loader feeds the list to the existing serializer
('Cardano.Tx.Graph.Rules.Load.Emit.Overlay.emitOverlay'), which
re-emits the canonical Turtle byte stream. Authoring the same content
as YAML or as Turtle therefore produces byte-equal serializer output
— the co-equality requirement (spec SC-005).

== Subset supported (FR-003 + research R1)

In scope:

* @\@prefix \<pfx\>: \<iri\> .@ declarations.
* @\@base \<iri\> .@ (silently ignored — no current use).
* Prefixed names @pfx:localname@ and full IRI references @\<iri\>@.
* Blank-node references @_:name@.
* String literals @\"…\"@ with @\\\"@ escapes only.
* Integer literals @123@ (accepted by the lexer for forward-compat;
  the rules surface does not author them).
* Statement terminators @.@, @;@, @,@.
* Comments @#@ to end-of-line.
* @owl:imports@ triples are recognized; following the target is
  T007's surface.

Out of scope (rejected with 'ParserError'):

* Collections @( … )@.
* Blank-node property lists @[ … ]@.
* Language tags @\"…\"\@en@.
* Datatype suffixes @\"…\"^^xsd:integer@.
* Multiline strings @\"\"\"…\"\"\"@.
* Boolean literals @true@ / @false@.

== Pipeline

1. __Lex__ — produce a @[(Token, Int)]@ stream from the input text;
   each tuple carries the 1-based source line where the token began.
2. __Parse__ — walk tokens; recognize @\@prefix@ declarations into a
   prefix table; recognize statement runs; produce @[Triple]@.
3. __Group__ — group triples by subject.
4. __Reshape__ — find each subject typed @cardano:Entity@; follow its
   @cardano:hasIdentifier@ bnode references to the
   @cardano:Identifier@ subject; produce an 'EntityDecl'.

The operator-chosen blank-node names are discarded; the YAML
compiler's deterministic naming algorithm runs downstream when the
serializer emits the overlay, so any operator-authored Turtle is
normalized to the canonical form.

== Source-line provenance (T009)

The lexer tracks the current line as it advances through the input
and emits a 'TokLoc' wrapper carrying every 'Token' together with
its 1-based source line. Every structural error producer site uses
the offending token's line so the @tx-graph@ CLI and a future LSP
can render hyperlinked diagnostics. Errors that surface at end-of-
input (e.g. unterminated string, unterminated IRI) carry the line
where the offending token began.
-}
module Cardano.Tx.Graph.Rules.Load.Parse.Turtle (
    parseRulesTurtleText,
    parseRulesTurtleImports,
    parseRulesTurtleImportsWithFile,
) where

import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
 )

import Data.ByteString (ByteString)
import Data.Char (isAlphaNum, isDigit, isSpace)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Text.Encoding.Error (lenientDecode)

{- | The placeholder file path used when the caller drives the in-memory
@parseRulesTurtleText@ / @parseRulesTurtleImports@ entry points with
no file path. The 'Cardano.Tx.Graph.Rules.Load.loadRulesFile'
entrypoint threads the real path through
'parseRulesTurtleImportsWithFile'.
-}
inMemoryFile :: FilePath
inMemoryFile = "<in-memory>"

{- | The default line for tokens whose source position has been lost
(should not happen for normal authoring — every lexer site sets a
real line). The fallback is 1 (start of document).
-}
topLevelLine :: Int
topLevelLine = 1

----------------------------------------------------------------------
-- Public entry point
----------------------------------------------------------------------

{- | Parse a @rules.ttl@ byte blob into the in-memory entity list.

Returns @Right []@ for an empty document. Otherwise:

* tokenizes the input, tracking the 1-based source line of every
  token;
* gathers @\@prefix@ declarations into a prefix table;
* parses the remaining statements into a triple set;
* groups triples by subject;
* extracts every subject typed @cardano:Entity@ into an 'EntityDecl'
  (preserving source order), resolving its
  @cardano:hasIdentifier@ blank-node references to the
  matching @cardano:Identifier@ subject.

Out-of-scope Turtle constructs and any structural failure surface
as 'RulesLoadError' via 'Left'.

The in-memory entry point uses @\<in-memory\>@ as the source file in
every error. For real file-path provenance, drive
'Cardano.Tx.Graph.Rules.Load.loadRulesFile' (which threads the file
path through 'parseRulesTurtleImportsWithFile').
-}
parseRulesTurtleText :: ByteString -> Either RulesLoadError [EntityDecl]
parseRulesTurtleText = fmap snd . parseRulesTurtleImports

{- | Parse a @rules.ttl@ byte blob into both the @owl:imports@ targets
(in source order) and the in-memory entity list. Used by the imports
resolver (see "Cardano.Tx.Graph.Rules.Load.Resolve.Imports") so a
single parse pass produces both the dependency edges and the
entities the DFS resolver flattens. Uses the placeholder
@\<in-memory\>@ file path — see 'parseRulesTurtleImportsWithFile'
for the file-aware variant the resolver actually calls.

Returns @Right ([], [])@ for an empty document. Each element of the
returned import list is the raw operator-authored IRI body (without
the angle brackets) — the resolver applies its own absolute / HTTPS
/ missing-file checks.

@owl:imports@ triples whose object is a prefixed name rather than a
full IRI reference are rejected with a 'ParserError' (the canonical
authoring form uses @\<relative-path.ttl\>@).
-}
parseRulesTurtleImports ::
    ByteString -> Either RulesLoadError ([Text], [EntityDecl])
parseRulesTurtleImports = parseRulesTurtleImportsWithFile inMemoryFile

{- | Variant of 'parseRulesTurtleImports' that takes the source 'FilePath'
so every 'RulesLoadError' carries real (file, line) provenance. Used
by 'Cardano.Tx.Graph.Rules.Load.Resolve.Imports.resolveImports'.
-}
parseRulesTurtleImportsWithFile ::
    FilePath ->
    ByteString ->
    Either RulesLoadError ([Text], [EntityDecl])
parseRulesTurtleImportsWithFile file blob = do
    let txt = TextEncoding.decodeUtf8With lenientDecode blob
    tokens <- lexTurtle file txt
    parsed <- parseDocument file tokens
    imports <- extractOwlImports file (pdTriples parsed)
    entities <- reshapeEntities file parsed
    pure (imports, entities)

{- | Walk the parsed triple list and extract every @owl:imports@
object as an IRI body. The resolver applies its own absolute /
HTTPS / missing-file checks against the strings returned here.
-}
extractOwlImports ::
    FilePath -> [LocTriple] -> Either RulesLoadError [Text]
extractOwlImports file = traverse step . filter isOwlImports
  where
    isOwlImports (LocTriple _ _ p _) = case p of
        PredPrefixed "owl" "imports" -> True
        _ -> False
    step (LocTriple ln _ _ obj) = case obj of
        ObjIri iri -> Right iri
        other ->
            Left $
                ParserError
                    file
                    ln
                    ( "owl:imports target must be an IRI reference"
                        <> " <relative-path.ttl>; got: "
                        <> Text.pack (show other)
                    )

----------------------------------------------------------------------
-- Token stream
----------------------------------------------------------------------

{- | Lexical tokens the Turtle subset emits. Out-of-scope tokens
(@(@, @)@, @[@, @]@, @^^@, language tags, triple-quoted strings,
boolean literals) are emitted explicitly so the structural parser
can reject them with a precise error.
-}
data Token
    = -- | @\@prefix@ directive keyword.
      TokPrefixKw
    | -- | @\@base@ directive keyword.
      TokBaseKw
    | -- | Bare identifier (e.g. @PaymentKey@) — only appears in error
      -- contexts; the canonical Turtle subset does not use them.
      TokIdent !Text
    | -- | Full IRI reference, e.g. @\<https://…\>@. The carried text is
      -- the IRI body without the angle brackets.
      TokIri !Text
    | -- | Prefixed name @pfx:local@ (empty @pfx@ ↦ default @:@).
      TokPrefixed !Text !Text
    | -- | Blank-node reference @_:name@.
      TokBnode !Text
    | -- | String literal @\"…\"@ (with @\\\"@ escapes resolved).
      TokString !Text
    | -- | Integer literal @123@ (kept forward-compat; the rules
      -- surface does not author these).
      TokInteger !Integer
    | -- | The @a@ keyword (= @rdf:type@).
      TokA
    | -- | Statement terminator @.@.
      TokDot
    | -- | Predicate-list separator @;@.
      TokSemicolon
    | -- | Object-list separator @,@.
      TokComma
    | -- | Triple-quoted string opener (rejected).
      TokTripleQuote
    | -- | Datatype suffix @^^@ (rejected).
      TokCaretCaret
    | -- | Language tag @\@en@ (rejected).
      TokLangTag !Text
    | -- | Open paren @(@ — collection opener (rejected).
      TokLParen
    | -- | Close paren @)@ — collection closer (rejected).
      TokRParen
    | -- | Open bracket @[@ — blank-node prop-list opener (rejected).
      TokLBracket
    | -- | Close bracket @]@ — blank-node prop-list closer (rejected).
      TokRBracket
    deriving stock (Eq, Show)

{- | A token annotated with its 1-based source line. The lexer
maintains a current-line counter as it advances through the input
and stamps every emitted token; the structural parser then threads
the line through to every 'RulesLoadError' producer site.
-}
data TokLoc = TokLoc {tokLine :: !Int, tokValue :: !Token}
    deriving stock (Eq, Show)

{- | Tokenize a Turtle text blob into a 'TokLoc' stream. Returns
'Left' (a 'ParserError') on a malformed string literal or an
unterminated IRI; in those cases the error's line is the one
where the offending token began.
-}
lexTurtle :: FilePath -> Text -> Either RulesLoadError [TokLoc]
lexTurtle file = go 1
  where
    -- Walk @t@ keeping the current 1-based source line. Whitespace
    -- (including the line breaks comments produce) is consumed in
    -- step, and 'skipWhitespace' returns the updated line count.
    go :: Int -> Text -> Either RulesLoadError [TokLoc]
    go !ln t =
        let (ln', t') = skipWhitespace ln t
         in if Text.null t'
                then Right []
                else case Text.uncons t' of
                    Nothing -> Right []
                    Just (c, rest)
                        | c == '<' -> do
                            (iri, rest', ln'') <- takeIri file ln' rest
                            let (ln''', rest''') = skipWhitespace ln'' rest'
                            (TokLoc ln' (TokIri iri) :) <$> go ln''' rest'''
                        | c == '"' ->
                            if "\"\"" `Text.isPrefixOf` rest
                                then
                                    Left $
                                        ParserError
                                            file
                                            ln'
                                            "triple-quoted strings are not supported"
                                else do
                                    (lit, rest', ln'') <-
                                        takeString file ln' rest
                                    let (ln''', rest''') =
                                            skipWhitespace ln'' rest'
                                    (TokLoc ln' (TokString lit) :)
                                        <$> go ln''' rest'''
                        | c == '.' && not (startsDigit rest) -> do
                            let (ln'', rest'') = skipWhitespace ln' rest
                            (TokLoc ln' TokDot :) <$> go ln'' rest''
                        | c == ';' -> do
                            let (ln'', rest'') = skipWhitespace ln' rest
                            (TokLoc ln' TokSemicolon :) <$> go ln'' rest''
                        | c == ',' -> do
                            let (ln'', rest'') = skipWhitespace ln' rest
                            (TokLoc ln' TokComma :) <$> go ln'' rest''
                        | c == '(' -> do
                            let (ln'', rest'') = skipWhitespace ln' rest
                            (TokLoc ln' TokLParen :) <$> go ln'' rest''
                        | c == ')' -> do
                            let (ln'', rest'') = skipWhitespace ln' rest
                            (TokLoc ln' TokRParen :) <$> go ln'' rest''
                        | c == '[' -> do
                            let (ln'', rest'') = skipWhitespace ln' rest
                            (TokLoc ln' TokLBracket :) <$> go ln'' rest''
                        | c == ']' -> do
                            let (ln'', rest'') = skipWhitespace ln' rest
                            (TokLoc ln' TokRBracket :) <$> go ln'' rest''
                        | c == '^' && Text.isPrefixOf "^" rest -> do
                            let (ln'', rest'') =
                                    skipWhitespace ln' (Text.tail rest)
                            (TokLoc ln' TokCaretCaret :) <$> go ln'' rest''
                        | c == '@' -> do
                            let (kwTxt, rest') = Text.span isPnChar rest
                            case kwTxt of
                                "prefix" -> do
                                    let (ln'', rest'') =
                                            skipWhitespace ln' rest'
                                    (TokLoc ln' TokPrefixKw :)
                                        <$> go ln'' rest''
                                "base" -> do
                                    let (ln'', rest'') =
                                            skipWhitespace ln' rest'
                                    (TokLoc ln' TokBaseKw :)
                                        <$> go ln'' rest''
                                _ -> do
                                    let (ln'', rest'') =
                                            skipWhitespace ln' rest'
                                    (TokLoc ln' (TokLangTag kwTxt) :)
                                        <$> go ln'' rest''
                        | c == '_' && Text.isPrefixOf ":" rest -> do
                            let afterColon = Text.tail rest
                                (name, rest') =
                                    Text.span isPnChar afterColon
                            if Text.null name
                                then
                                    Left $
                                        ParserError
                                            file
                                            ln'
                                            "blank-node prefix '_:' must be followed by a label"
                                else do
                                    let (ln'', rest'') =
                                            skipWhitespace ln' rest'
                                    (TokLoc ln' (TokBnode name) :)
                                        <$> go ln'' rest''
                        | isDigit c || (c == '-' && startsDigit rest) -> do
                            let (numTxt, rest') = Text.span isNumChar t'
                            case readInteger numTxt of
                                Just n -> do
                                    let (ln'', rest'') =
                                            skipWhitespace ln' rest'
                                    (TokLoc ln' (TokInteger n) :)
                                        <$> go ln'' rest''
                                Nothing ->
                                    Left $
                                        ParserError
                                            file
                                            ln'
                                            ( "invalid numeric literal: "
                                                <> numTxt
                                            )
                        | isPnNameStart c -> do
                            let (word, rest') = Text.span isPnChar t'
                            case Text.uncons rest' of
                                Just (':', afterColon) -> do
                                    let (local, rest'') =
                                            Text.span isPnChar afterColon
                                        (ln'', rest''') =
                                            skipWhitespace ln' rest''
                                    (TokLoc ln' (TokPrefixed word local) :)
                                        <$> go ln'' rest'''
                                _ -> case word of
                                    "a" -> do
                                        let (ln'', rest'') =
                                                skipWhitespace ln' rest'
                                        (TokLoc ln' TokA :)
                                            <$> go ln'' rest''
                                    "true" ->
                                        Left $
                                            ParserError
                                                file
                                                ln'
                                                "boolean literals are not supported"
                                    "false" ->
                                        Left $
                                            ParserError
                                                file
                                                ln'
                                                "boolean literals are not supported"
                                    _ -> do
                                        let (ln'', rest'') =
                                                skipWhitespace ln' rest'
                                        (TokLoc ln' (TokIdent word) :)
                                            <$> go ln'' rest''
                        | c == ':' -> do
                            let (local, rest') = Text.span isPnChar rest
                                (ln'', rest'') = skipWhitespace ln' rest'
                            (TokLoc ln' (TokPrefixed "" local) :)
                                <$> go ln'' rest''
                        | otherwise ->
                            Left $
                                ParserError
                                    file
                                    ln'
                                    ( "unexpected character in Turtle input: "
                                        <> Text.pack [c]
                                    )

    startsDigit s = case Text.uncons s of
        Just (c, _) -> isDigit c
        Nothing -> False

{- | Skip whitespace and full-line comments at the start of @t@,
returning the updated line counter and the remaining input. Counts
@\\n@ characters (newlines) so callers see the correct source line
for the next token.
-}
skipWhitespace :: Int -> Text -> (Int, Text)
skipWhitespace !ln t =
    let (ws, rest) = Text.span isSpace t
        ln' = ln + Text.count "\n" ws
     in case Text.uncons rest of
            Just ('#', afterHash) ->
                -- Comment runs to end-of-line; the newline (if any)
                -- gets consumed by the next skipWhitespace pass.
                let (_, afterComment) = Text.break (== '\n') afterHash
                 in skipWhitespace ln' afterComment
            _ -> (ln', rest)

{- | True for characters that can appear inside a prefix or local name
in the supported subset. Permissive — the parser accepts more than
strict Turtle PN_CHARS but never less.
-}
isPnChar :: Char -> Bool
isPnChar c = isAlphaNum c || c == '_' || c == '-' || c == '.'

{- | True for characters that can _start_ a prefix or local name. The
canonical YAML-compiler output emits slugs whose first character is a
letter or underscore.
-}
isPnNameStart :: Char -> Bool
isPnNameStart c = isAlphaNum c || c == '_'

-- | True for digits and the '-' / '.' that can appear inside numerics.
isNumChar :: Char -> Bool
isNumChar c = isDigit c || c == '-' || c == '.'

readInteger :: Text -> Maybe Integer
readInteger t = case reads (Text.unpack t) of
    [(n, "")] -> Just n
    _ -> Nothing

{- | Take a @\<...\>@ IRI. Returns the body without the brackets, the
remaining input, and the updated line counter (the body may contain
newlines if the IRI spans multiple lines — uncommon but tolerated).
-}
takeIri :: FilePath -> Int -> Text -> Either RulesLoadError (Text, Text, Int)
takeIri file ln t =
    let (body, rest) = Text.break (== '>') t
     in case Text.uncons rest of
            Just ('>', rest') ->
                Right (body, rest', ln + Text.count "\n" body)
            _ ->
                Left $
                    ParserError
                        file
                        ln
                        "unterminated IRI reference"

{- | Take a @\"...\"@ string literal, honoring @\\\"@ as an escaped
double quote. Returns the unescaped body, the remaining input, and
the updated line counter (string literals may span lines under the
loose grammar; this is rejected upstream for the canonical surface
but tracked here for accurate diagnostics).
-}
takeString ::
    FilePath -> Int -> Text -> Either RulesLoadError (Text, Text, Int)
takeString file startLn = go Text.empty startLn
  where
    go acc !ln t = case Text.uncons t of
        Nothing ->
            Left $
                ParserError
                    file
                    startLn
                    "unterminated string literal"
        Just ('"', rest) -> Right (acc, rest, ln)
        Just ('\\', rest) -> case Text.uncons rest of
            Just ('"', rest') -> go (acc <> "\"") ln rest'
            Just ('\\', rest') -> go (acc <> "\\") ln rest'
            _ ->
                Left $
                    ParserError
                        file
                        ln
                        "unsupported escape in string literal"
        Just ('\n', rest) -> go (Text.snoc acc '\n') (ln + 1) rest
        Just (c, rest) -> go (Text.snoc acc c) ln rest

----------------------------------------------------------------------
-- Structural parse
----------------------------------------------------------------------

{- | A parsed subject — what appears on the left of a triple. Subjects
that the structural parser does not recognize (collections, blank-node
property lists) are rejected before they reach this type.
-}
data Subject
    = -- | @pfx:local@ or @:local@ (empty pfx ↦ default).
      SubjPrefixed !Text !Text
    | -- | @\<iri\>@.
      SubjIri !Text
    | -- | @_:name@.
      SubjBnode !Text
    deriving stock (Eq, Ord, Show)

{- | A parsed predicate. The canonical surface uses either a prefixed
name or the @a@ keyword (which we treat as the special-cased predicate
'a').
-}
data Predicate
    = -- | The @a@ keyword (= @rdf:type@).
      PredA
    | -- | @pfx:local@ predicate.
      PredPrefixed !Text !Text
    | -- | @\<iri\>@ predicate (rare).
      PredIri !Text
    deriving stock (Eq, Ord, Show)

{- | A parsed object — string literal, integer, prefixed name, IRI, or
bnode reference.
-}
data Object
    = ObjString !Text
    | ObjInteger !Integer
    | ObjPrefixed !Text !Text
    | ObjIri !Text
    | ObjBnode !Text
    deriving stock (Eq, Ord, Show)

{- | A flat triple, annotated with the 1-based source line of the
subject's first token. Lets the reshape phase surface entity-scoped
errors at the entity's declaration line.
-}
data LocTriple = LocTriple !Int !Subject !Predicate !Object
    deriving stock (Eq, Ord, Show)

{- | The parsed document: the prefix table and the located triple list
(in source order). The triple list is what the reshape phase
consumes; the prefix table is currently unused by the reshape but is
kept on hand for the imports resolver and validation.
-}
data ParsedDocument = ParsedDocument
    { _pdPrefixes :: !(Map Text Text)
    , pdTriples :: ![LocTriple]
    }
    deriving stock (Eq, Show)

{- | Walk the token stream. Recognizes @\@prefix@ and @\@base@
directives at the top level; everything else is a triple block.
-}
parseDocument ::
    FilePath -> [TokLoc] -> Either RulesLoadError ParsedDocument
parseDocument file = go (ParsedDocument Map.empty [])
  where
    go acc [] = Right acc{pdTriples = reverse (pdTriples acc)}
    go acc (TokLoc _ TokPrefixKw : rest) = do
        (pfx, iri, rest') <- parsePrefixDecl file rest
        let acc' = acc{_pdPrefixes = Map.insert pfx iri (_pdPrefixes acc)}
        go acc' rest'
    go acc (TokLoc _ TokBaseKw : rest) = do
        (_iri, rest') <- parseBaseDecl file rest
        -- @base is accepted but ignored (no current use).
        go acc rest'
    go acc toks = do
        (triples, rest) <- parseTripleBlock file toks
        go acc{pdTriples = reverse triples ++ pdTriples acc} rest

{- | Parse a @\@prefix \<pfx\>: \<iri\> .@ directive. Returns the prefix
text (without the trailing colon), the IRI body (without the angle
brackets), and the remaining token stream.
-}
parsePrefixDecl ::
    FilePath -> [TokLoc] -> Either RulesLoadError (Text, Text, [TokLoc])
parsePrefixDecl file = \case
    TokLoc ln (TokPrefixed pfx local)
        : TokLoc _ (TokIri iri)
        : TokLoc _ TokDot
        : rest
            | Text.null local -> Right (pfx, iri, rest)
            | otherwise ->
                Left $
                    ParserError
                        file
                        ln
                        ( "@prefix declaration has unexpected local part: "
                            <> pfx
                            <> ":"
                            <> local
                        )
    other ->
        Left $
            ParserError
                file
                (firstLine other)
                ( "malformed @prefix declaration; got: "
                    <> tokenSnippet other
                )

-- | Parse a @\@base \<iri\> .@ directive.
parseBaseDecl ::
    FilePath -> [TokLoc] -> Either RulesLoadError (Text, [TokLoc])
parseBaseDecl file = \case
    TokLoc _ (TokIri iri) : TokLoc _ TokDot : rest -> Right (iri, rest)
    other ->
        Left $
            ParserError
                file
                (firstLine other)
                ( "malformed @base declaration; got: "
                    <> tokenSnippet other
                )

{- | Parse a single triple block: @S P1 O1, O2 ; P2 O3 .@. Returns the
flat located-triple list (in source order) and the remaining token
stream after the closing @.@.
-}
parseTripleBlock ::
    FilePath -> [TokLoc] -> Either RulesLoadError ([LocTriple], [TokLoc])
parseTripleBlock file toks = do
    (subj, subjLn, rest1) <- parseSubject file toks
    parsePredicateObjectList file subj subjLn [] rest1

parseSubject ::
    FilePath -> [TokLoc] -> Either RulesLoadError (Subject, Int, [TokLoc])
parseSubject file = \case
    TokLoc ln (TokPrefixed pfx local) : rest ->
        Right (SubjPrefixed pfx local, ln, rest)
    TokLoc ln (TokIri iri) : rest -> Right (SubjIri iri, ln, rest)
    TokLoc ln (TokBnode name) : rest -> Right (SubjBnode name, ln, rest)
    TokLoc ln TokLBracket : _ ->
        Left $
            ParserError
                file
                ln
                "blank-node property lists '[ ... ]' are not supported"
    TokLoc ln TokLParen : _ ->
        Left $
            ParserError
                file
                ln
                "collection syntax '( ... )' is not supported"
    other ->
        Left $
            ParserError
                file
                (firstLine other)
                ( "expected subject (prefixed name, IRI, or blank node); got: "
                    <> tokenSnippet other
                )

{- | Walk the predicate-object list of a single subject. Re-enters
itself on @;@; the closing @.@ ends the block.
-}
parsePredicateObjectList ::
    FilePath ->
    Subject ->
    Int ->
    [LocTriple] ->
    [TokLoc] ->
    Either RulesLoadError ([LocTriple], [TokLoc])
parsePredicateObjectList file subj subjLn acc toks = do
    (pred_, rest1) <- parsePredicate file toks
    (objs, rest2) <- parseObjectList file [] rest1
    let triples = [LocTriple subjLn subj pred_ o | o <- objs]
        acc' = acc ++ triples
    case rest2 of
        TokLoc _ TokSemicolon : rest3 ->
            parsePredicateObjectList file subj subjLn acc' rest3
        TokLoc _ TokDot : rest3 -> Right (acc', rest3)
        other ->
            Left $
                ParserError
                    file
                    (firstLine other)
                    ( "expected ';' or '.' after object list; got: "
                        <> tokenSnippet other
                    )

parsePredicate ::
    FilePath -> [TokLoc] -> Either RulesLoadError (Predicate, [TokLoc])
parsePredicate file = \case
    TokLoc _ TokA : rest -> Right (PredA, rest)
    TokLoc _ (TokPrefixed pfx local) : rest ->
        Right (PredPrefixed pfx local, rest)
    TokLoc _ (TokIri iri) : rest -> Right (PredIri iri, rest)
    other ->
        Left $
            ParserError
                file
                (firstLine other)
                ( "expected predicate; got: "
                    <> tokenSnippet other
                )

{- | Parse a comma-separated object list. Returns the objects in source
order plus the remaining tokens (starting at the @;@ or @.@ that
terminates the list).
-}
parseObjectList ::
    FilePath ->
    [Object] ->
    [TokLoc] ->
    Either RulesLoadError ([Object], [TokLoc])
parseObjectList file acc toks = do
    (obj, rest) <- parseObject file toks
    let acc' = acc ++ [obj]
    case rest of
        TokLoc _ TokComma : rest' -> parseObjectList file acc' rest'
        _ -> Right (acc', rest)

parseObject ::
    FilePath -> [TokLoc] -> Either RulesLoadError (Object, [TokLoc])
parseObject file = \case
    TokLoc ln (TokString lit) : TokLoc _ (TokLangTag _tag) : _ ->
        Left $
            ParserError
                file
                ln
                ( "language tags on string literals are not supported "
                    <> "(literal "
                    <> renderShortLiteral lit
                    <> ")"
                )
    TokLoc ln (TokString lit) : TokLoc _ TokCaretCaret : _ ->
        Left $
            ParserError
                file
                ln
                ( "datatype suffixes on string literals are not supported "
                    <> "(literal "
                    <> renderShortLiteral lit
                    <> ")"
                )
    TokLoc _ (TokString lit) : rest -> Right (ObjString lit, rest)
    TokLoc _ (TokInteger n) : rest -> Right (ObjInteger n, rest)
    TokLoc _ (TokPrefixed pfx local) : rest ->
        Right (ObjPrefixed pfx local, rest)
    TokLoc _ (TokIri iri) : rest -> Right (ObjIri iri, rest)
    TokLoc _ (TokBnode name) : rest -> Right (ObjBnode name, rest)
    TokLoc ln TokLParen : _ ->
        Left $
            ParserError
                file
                ln
                "collection syntax '( ... )' is not supported"
    TokLoc ln TokLBracket : _ ->
        Left $
            ParserError
                file
                ln
                "blank-node property lists '[ ... ]' are not supported"
    other ->
        Left $
            ParserError
                file
                (firstLine other)
                ( "expected object; got: "
                    <> tokenSnippet other
                )

----------------------------------------------------------------------
-- Reshape: triples to EntityDecl
----------------------------------------------------------------------

{- | Group the parsed located triples by subject and reshape every
@cardano:Entity@-typed subject into an 'EntityDecl'.

The transform proceeds in three phases:

1. Build a per-subject map @{Subject -> [(Predicate, Object)]}@,
   preserving source order both across subjects and within a
   subject's predicate-object list. A second map records the
   first-seen line of every subject so error messages can point
   at the subject's declaration.
2. Walk the subject map; for every subject that has an
   @a cardano:Entity@ triple, extract its @rdfs:label@ and
   @cardano:hasIdentifier _:bnode@ references.
3. For every bnode reference, look up the @cardano:Identifier@
   subject in the same map, extract its @cardano:leafType@ and
   @cardano:bytesHex@ literals, and emit one 'EntityIdentifier'.
-}
reshapeEntities ::
    FilePath -> ParsedDocument -> Either RulesLoadError [EntityDecl]
reshapeEntities file doc =
    let subjectOrder = subjectsInOrder (pdTriples doc)
        groups = groupBySubject (pdTriples doc)
        subjectLines = subjectFirstLines (pdTriples doc)
        entitySubjects =
            filter (isEntitySubject groups) subjectOrder
     in traverse (buildEntity file subjectLines groups) entitySubjects

{- | List subjects in first-occurrence source order. The Turtle
canonical form authors each subject's full statement contiguously, so
the first-occurrence index doubles as the document order.
-}
subjectsInOrder :: [LocTriple] -> [Subject]
subjectsInOrder = go []
  where
    go acc [] = reverse acc
    go acc (LocTriple _ s _ _ : rest)
        | s `elem` acc = go acc rest
        | otherwise = go (s : acc) rest

groupBySubject ::
    [LocTriple] -> Map Subject [(Predicate, Object)]
groupBySubject = foldl' step Map.empty
  where
    step acc (LocTriple _ s p o) =
        Map.insertWith (flip (<>)) s [(p, o)] acc

{- | Record the 1-based source line of every subject's first
appearance. Used by 'buildEntity' so entity-scoped errors point at
the entity's own line, not at the document.
-}
subjectFirstLines :: [LocTriple] -> Map Subject Int
subjectFirstLines = foldl' step Map.empty
  where
    step acc (LocTriple ln s _ _) =
        Map.insertWith (\_new old -> old) s ln acc

isEntitySubject :: Map Subject [(Predicate, Object)] -> Subject -> Bool
isEntitySubject m s = case Map.lookup s m of
    Nothing -> False
    Just pairs ->
        any
            (\(p, o) -> p == PredA && objIsPrefixed "cardano" "Entity" o)
            pairs

objIsPrefixed :: Text -> Text -> Object -> Bool
objIsPrefixed pfx local (ObjPrefixed p l) = p == pfx && l == local
objIsPrefixed _ _ _ = False

{- | Build an 'EntityDecl' from a known @cardano:Entity@ subject by
locating its @rdfs:label@ and walking its @cardano:hasIdentifier@
references. The entity slug is the IRI local part for prefixed
subjects (no slugify pass — the operator authored a valid Turtle
local name). Entity-scoped errors point at the entity's first source
line, looked up via @subjectLines@.
-}
buildEntity ::
    FilePath ->
    Map Subject Int ->
    Map Subject [(Predicate, Object)] ->
    Subject ->
    Either RulesLoadError EntityDecl
buildEntity file subjectLines groups subj = do
    let ln = Map.findWithDefault topLevelLine subj subjectLines
    slug <- subjectSlug file ln subj
    let pairs = Map.findWithDefault [] subj groups
    name <- requireLabel file ln slug pairs
    bnodes <- collectHasIdentifierBnodes file ln slug pairs
    idents <- traverse (resolveIdentifier file subjectLines groups slug) bnodes
    pure
        EntityDecl
            { entityName = name
            , entitySlug = slug
            , entityIdentifiers = idents
            }

-- | The slug for a subject. Only prefixed-name subjects are supported.
subjectSlug ::
    FilePath -> Int -> Subject -> Either RulesLoadError Text
subjectSlug file ln = \case
    SubjPrefixed _ local
        | Text.null local ->
            Left $
                ParserError
                    file
                    ln
                    "entity subject has empty local part"
        | otherwise -> Right local
    SubjIri iri ->
        Left $
            ParserError
                file
                ln
                ( "entity subjects must use a prefixed name; got IRI: <"
                    <> iri
                    <> ">"
                )
    SubjBnode name ->
        Left $
            ParserError
                file
                ln
                ( "entity subjects must use a prefixed name; got blank node: _:"
                    <> name
                )

-- | Extract the single @rdfs:label \"…\"@ predicate from a subject's pairs.
requireLabel ::
    FilePath ->
    Int ->
    Text ->
    [(Predicate, Object)] ->
    Either RulesLoadError Text
requireLabel file ln slug pairs = case mapMaybe isLabel pairs of
    [lbl] -> Right lbl
    [] ->
        Left $
            ParserError
                file
                ln
                ( "entity :"
                    <> slug
                    <> " is missing the required 'rdfs:label' triple"
                )
    _ ->
        Left $
            ParserError
                file
                ln
                ( "entity :"
                    <> slug
                    <> " has multiple 'rdfs:label' triples"
                )
  where
    isLabel (PredPrefixed "rdfs" "label", ObjString s) = Just s
    isLabel _ = Nothing

{- | Collect every @cardano:hasIdentifier _:bnode@ object in the entity's
predicate-object list (in source order).
-}
collectHasIdentifierBnodes ::
    FilePath ->
    Int ->
    Text ->
    [(Predicate, Object)] ->
    Either RulesLoadError [Text]
collectHasIdentifierBnodes file ln slug pairs =
    case extractHasIdentifiers pairs of
        [] ->
            Left $
                ParserError
                    file
                    ln
                    ( "entity :"
                        <> slug
                        <> " has no 'cardano:hasIdentifier' triples"
                    )
        xs -> Right xs

extractHasIdentifiers :: [(Predicate, Object)] -> [Text]
extractHasIdentifiers = mapMaybe step
  where
    step (PredPrefixed "cardano" "hasIdentifier", ObjBnode name) = Just name
    step _ = Nothing

{- | Resolve a @_:bnode@ identifier reference into an 'EntityIdentifier'
by looking up the bnode's own predicate-object list. Requires the
bnode subject to be typed @cardano:Identifier@ and to carry exactly
one @cardano:leafType \"…\"@ and one @cardano:bytesHex \"…\"@ pair.
-}
resolveIdentifier ::
    FilePath ->
    Map Subject Int ->
    Map Subject [(Predicate, Object)] ->
    Text ->
    Text ->
    Either RulesLoadError EntityIdentifier
resolveIdentifier file subjectLines groups owningSlug bnodeName =
    let bnodeSubj = SubjBnode bnodeName
        bnodeLine =
            Map.findWithDefault topLevelLine bnodeSubj subjectLines
     in case Map.lookup bnodeSubj groups of
            Nothing ->
                Left $
                    ParserError
                        file
                        topLevelLine
                        ( "entity :"
                            <> owningSlug
                            <> " references unknown blank node _:"
                            <> bnodeName
                        )
            Just pairs -> do
                requireIdentifierType file bnodeLine owningSlug bnodeName pairs
                leafTypeText <-
                    requireSingleLiteral
                        file
                        bnodeLine
                        "cardano:leafType"
                        pairs
                        bnodeName
                        "leafType"
                leafType <- parseLeafType file bnodeLine bnodeName leafTypeText
                bytesHex <-
                    requireSingleLiteral
                        file
                        bnodeLine
                        "cardano:bytesHex"
                        pairs
                        bnodeName
                        "bytesHex"
                pure (EntityIdentifier leafType bytesHex)

requireIdentifierType ::
    FilePath ->
    Int ->
    Text ->
    Text ->
    [(Predicate, Object)] ->
    Either RulesLoadError ()
requireIdentifierType file ln owningSlug bnodeName pairs =
    if any isIdentifierType pairs
        then Right ()
        else
            Left $
                ParserError
                    file
                    ln
                    ( "blank node _:"
                        <> bnodeName
                        <> " (referenced by :"
                        <> owningSlug
                        <> ") is not typed 'cardano:Identifier'"
                    )
  where
    isIdentifierType (PredA, ObjPrefixed "cardano" "Identifier") = True
    isIdentifierType _ = False

{- | Extract exactly one @cardano:\<localPart\>@ string literal from a
subject's predicate-object list. The @humanField@ name is used in
diagnostics.
-}
requireSingleLiteral ::
    FilePath ->
    Int ->
    Text ->
    [(Predicate, Object)] ->
    Text ->
    Text ->
    Either RulesLoadError Text
requireSingleLiteral file ln _predLabel pairs bnodeName localPart =
    case mapMaybe pick pairs of
        [lit] -> Right lit
        [] ->
            Left $
                ParserError
                    file
                    ln
                    ( "blank node _:"
                        <> bnodeName
                        <> " is missing required 'cardano:"
                        <> localPart
                        <> "' triple"
                    )
        _ ->
            Left $
                ParserError
                    file
                    ln
                    ( "blank node _:"
                        <> bnodeName
                        <> " has multiple 'cardano:"
                        <> localPart
                        <> "' triples"
                    )
  where
    pick (PredPrefixed "cardano" l, ObjString s)
        | l == localPart = Just s
    pick _ = Nothing

-- | Map a leafType literal to a 'LeafType' enum. Pinned by FR-013.
parseLeafType ::
    FilePath -> Int -> Text -> Text -> Either RulesLoadError LeafType
parseLeafType file ln bnodeName = \case
    "PaymentKey" -> Right PaymentKey
    "PaymentScript" -> Right PaymentScript
    "StakeKey" -> Right StakeKey
    "StakeScript" -> Right StakeScript
    "AssetClass" -> Right AssetClass
    "Policy" -> Right Policy
    "PoolId" -> Right PoolId
    "DRepKey" -> Right DRepKey
    "DRepScript" -> Right DRepScript
    other ->
        Left $
            ParserError
                file
                ln
                ( "blank node _:"
                    <> bnodeName
                    <> " has unknown cardano:leafType literal: "
                    <> renderShortLiteral other
                )

----------------------------------------------------------------------
-- Diagnostics
----------------------------------------------------------------------

{- | Render a short, human-readable diagnostic snippet for a token list.
Used in the @got: …@ tail of structural errors.
-}
tokenSnippet :: [TokLoc] -> Text
tokenSnippet [] = "<end of input>"
tokenSnippet (t : _) = Text.pack (show (tokValue t))

-- | The 1-based source line of the first token in @toks@, or 1 if empty.
firstLine :: [TokLoc] -> Int
firstLine [] = topLevelLine
firstLine (t : _) = tokLine t

{- | Render a string literal back into its source-like @\"…\"@ form,
truncating to 32 characters for diagnostics.
-}
renderShortLiteral :: Text -> Text
renderShortLiteral t =
    let trimmed
            | Text.length t > 32 = Text.take 32 t <> "..."
            | otherwise = t
     in "\"" <> trimmed <> "\""

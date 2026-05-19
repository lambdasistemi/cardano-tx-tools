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

1. __Lex__ — produce a token stream from the input text.
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
-}
module Cardano.Tx.Graph.Rules.Load.Parse.Turtle (
    parseRulesTurtleText,
    parseRulesTurtleImports,
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

{- | The placeholder file path attached to T006 error variants. T009
threads the real file path through when @loadRulesFile@ runs.
-}
inMemoryFile :: FilePath
inMemoryFile = "<in-memory>"

{- | The placeholder line number for T006 error variants. T009
tightens the surface to real source-line numbers from the lexer.
-}
inMemoryLine :: Int
inMemoryLine = 0

----------------------------------------------------------------------
-- Public entry point
----------------------------------------------------------------------

{- | Parse a @rules.ttl@ byte blob into the in-memory entity list.

Returns @Right []@ for an empty document. Otherwise:

* tokenizes the input;
* gathers @\@prefix@ declarations into a prefix table;
* parses the remaining statements into a triple set;
* groups triples by subject;
* extracts every subject typed @cardano:Entity@ into an 'EntityDecl'
  (preserving source order), resolving its
  @cardano:hasIdentifier@ blank-node references to the
  matching @cardano:Identifier@ subject.

Out-of-scope Turtle constructs and any structural failure surface
as 'RulesLoadError' via 'Left'.
-}
parseRulesTurtleText :: ByteString -> Either RulesLoadError [EntityDecl]
parseRulesTurtleText = fmap snd . parseRulesTurtleImports

{- | Parse a @rules.ttl@ byte blob into both the @owl:imports@ targets
(in source order) and the in-memory entity list. Used by the imports
resolver in T007 (see
"Cardano.Tx.Graph.Rules.Load.Resolve.Imports") so a single parse
pass produces both the dependency edges and the entities the DFS
resolver flattens.

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
parseRulesTurtleImports blob = do
    let txt = TextEncoding.decodeUtf8With lenientDecode blob
    tokens <- lexTurtle txt
    parsed <- parseDocument tokens
    imports <- extractOwlImports (pdTriples parsed)
    entities <- reshapeEntities parsed
    pure (imports, entities)

{- | Walk the parsed triple list and extract every @owl:imports@
object as an IRI body. The resolver applies its own absolute /
HTTPS / missing-file checks against the strings returned here.
-}
extractOwlImports :: [Triple] -> Either RulesLoadError [Text]
extractOwlImports = traverse step . filter isOwlImports
  where
    isOwlImports (Triple _ p _) = case p of
        PredPrefixed "owl" "imports" -> True
        _ -> False
    step (Triple _ _ obj) = case obj of
        ObjIri iri -> Right iri
        other ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
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

{- | Tokenize a Turtle text blob into a 'Token' stream. Returns
'Left' (a 'ParserError') on a malformed string literal or an
unterminated IRI.
-}
lexTurtle :: Text -> Either RulesLoadError [Token]
lexTurtle = go . skipWhitespace
  where
    go t
        | Text.null t = Right []
        | otherwise = case Text.uncons t of
            Nothing -> Right []
            Just (c, rest)
                | c == '#' -> go (skipWhitespace (Text.dropWhile (/= '\n') rest))
                | c == '<' -> do
                    (iri, rest') <- takeIri rest
                    (TokIri iri :) <$> go (skipWhitespace rest')
                | c == '"' -> do
                    -- Reject triple-quoted strings before we try to
                    -- read a single-quoted literal.
                    if "\"\"" `Text.isPrefixOf` rest
                        then
                            Left $
                                ParserError
                                    inMemoryFile
                                    inMemoryLine
                                    "triple-quoted strings are not supported"
                        else do
                            (lit, rest') <- takeString rest
                            (TokString lit :) <$> go (skipWhitespace rest')
                | c == '.' && not (startsDigit rest) ->
                    (TokDot :) <$> go (skipWhitespace rest)
                | c == ';' -> (TokSemicolon :) <$> go (skipWhitespace rest)
                | c == ',' -> (TokComma :) <$> go (skipWhitespace rest)
                | c == '(' -> (TokLParen :) <$> go (skipWhitespace rest)
                | c == ')' -> (TokRParen :) <$> go (skipWhitespace rest)
                | c == '[' -> (TokLBracket :) <$> go (skipWhitespace rest)
                | c == ']' -> (TokRBracket :) <$> go (skipWhitespace rest)
                | c == '^' && Text.isPrefixOf "^" rest ->
                    (TokCaretCaret :) <$> go (skipWhitespace (Text.tail rest))
                | c == '@' -> do
                    let (kwTxt, rest') = Text.span isPnChar rest
                    case kwTxt of
                        "prefix" ->
                            (TokPrefixKw :) <$> go (skipWhitespace rest')
                        "base" ->
                            (TokBaseKw :) <$> go (skipWhitespace rest')
                        _ ->
                            (TokLangTag kwTxt :) <$> go (skipWhitespace rest')
                | c == '_' && Text.isPrefixOf ":" rest -> do
                    let afterColon = Text.tail rest
                        (name, rest') = Text.span isPnChar afterColon
                    if Text.null name
                        then
                            Left $
                                ParserError
                                    inMemoryFile
                                    inMemoryLine
                                    "blank-node prefix '_:' must be followed by a label"
                        else (TokBnode name :) <$> go (skipWhitespace rest')
                | isDigit c || (c == '-' && startsDigit rest) -> do
                    let (numTxt, rest') = Text.span isNumChar t
                    case readInteger numTxt of
                        Just n ->
                            (TokInteger n :) <$> go (skipWhitespace rest')
                        Nothing ->
                            Left $
                                ParserError
                                    inMemoryFile
                                    inMemoryLine
                                    ( "invalid numeric literal: "
                                        <> numTxt
                                    )
                | isPnNameStart c -> do
                    -- A bare word: either the keyword "a", a boolean
                    -- literal (rejected), an identifier, or the start
                    -- of a prefixed name "pfx:local".
                    let (word, rest') = Text.span isPnChar t
                    case Text.uncons rest' of
                        Just (':', afterColon) -> do
                            let (local, rest'') = Text.span isPnChar afterColon
                            (TokPrefixed word local :) <$> go (skipWhitespace rest'')
                        _ -> case word of
                            "a" -> (TokA :) <$> go (skipWhitespace rest')
                            "true" ->
                                Left $
                                    ParserError
                                        inMemoryFile
                                        inMemoryLine
                                        "boolean literals are not supported"
                            "false" ->
                                Left $
                                    ParserError
                                        inMemoryFile
                                        inMemoryLine
                                        "boolean literals are not supported"
                            _ ->
                                (TokIdent word :) <$> go (skipWhitespace rest')
                | c == ':' -> do
                    -- Default prefix usage: @:local@ or bare @:@ (the
                    -- subject form used by @owl:imports@ when the
                    -- subject is the default base).
                    let (local, rest') = Text.span isPnChar rest
                    (TokPrefixed "" local :) <$> go (skipWhitespace rest')
                | otherwise ->
                    Left $
                        ParserError
                            inMemoryFile
                            inMemoryLine
                            ( "unexpected character in Turtle input: "
                                <> Text.pack [c]
                            )

    startsDigit s = case Text.uncons s of
        Just (c, _) -> isDigit c
        Nothing -> False

-- | Skip whitespace and full-line comments at the start of @t@.
skipWhitespace :: Text -> Text
skipWhitespace t = case Text.uncons (Text.dropWhile isSpace t) of
    Just ('#', rest) ->
        skipWhitespace (Text.dropWhile (/= '\n') rest)
    _ -> Text.dropWhile isSpace t

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

-- | Take a @\<...\>@ IRI. Returns the body without the brackets.
takeIri :: Text -> Either RulesLoadError (Text, Text)
takeIri t =
    let (body, rest) = Text.break (== '>') t
     in case Text.uncons rest of
            Just ('>', rest') -> Right (body, rest')
            _ ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
                        "unterminated IRI reference"

{- | Take a @\"...\"@ string literal, honoring @\\\"@ as an escaped
double quote. Returns the unescaped body and the remaining input.
-}
takeString :: Text -> Either RulesLoadError (Text, Text)
takeString = go Text.empty
  where
    go acc t = case Text.uncons t of
        Nothing ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    "unterminated string literal"
        Just ('"', rest) -> Right (acc, rest)
        Just ('\\', rest) -> case Text.uncons rest of
            Just ('"', rest') -> go (acc <> "\"") rest'
            Just ('\\', rest') -> go (acc <> "\\") rest'
            _ ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
                        "unsupported escape in string literal"
        Just (c, rest) -> go (Text.snoc acc c) rest

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

-- | A flat triple — the structural parser's intermediate IR.
data Triple = Triple !Subject !Predicate !Object
    deriving stock (Eq, Ord, Show)

{- | The parsed document: the prefix table and the triple list (in
source order). The triple list is what the reshape phase consumes;
the prefix table is currently unused by the reshape but is kept on
hand for T007 (imports resolver) and T009 (validation).
-}
data ParsedDocument = ParsedDocument
    { _pdPrefixes :: !(Map Text Text)
    , pdTriples :: ![Triple]
    }
    deriving stock (Eq, Show)

{- | Walk the token stream. Recognizes @\@prefix@ and @\@base@
directives at the top level; everything else is a triple block.
-}
parseDocument :: [Token] -> Either RulesLoadError ParsedDocument
parseDocument = go (ParsedDocument Map.empty [])
  where
    go acc [] = Right acc{pdTriples = reverse (pdTriples acc)}
    go acc (TokPrefixKw : rest) = do
        (pfx, iri, rest') <- parsePrefixDecl rest
        let acc' = acc{_pdPrefixes = Map.insert pfx iri (_pdPrefixes acc)}
        go acc' rest'
    go acc (TokBaseKw : rest) = do
        (_iri, rest') <- parseBaseDecl rest
        -- @base is accepted but ignored (no current use).
        go acc rest'
    go acc toks = do
        (triples, rest) <- parseTripleBlock toks
        go acc{pdTriples = reverse triples ++ pdTriples acc} rest

{- | Parse a @\@prefix \<pfx\>: \<iri\> .@ directive. Returns the prefix
text (without the trailing colon), the IRI body (without the angle
brackets), and the remaining token stream.
-}
parsePrefixDecl :: [Token] -> Either RulesLoadError (Text, Text, [Token])
parsePrefixDecl = \case
    TokPrefixed pfx local : TokIri iri : TokDot : rest
        | Text.null local -> Right (pfx, iri, rest)
        | otherwise ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    ( "@prefix declaration has unexpected local part: "
                        <> pfx
                        <> ":"
                        <> local
                    )
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "malformed @prefix declaration; got: "
                    <> tokenSnippet other
                )

-- | Parse a @\@base \<iri\> .@ directive.
parseBaseDecl :: [Token] -> Either RulesLoadError (Text, [Token])
parseBaseDecl = \case
    TokIri iri : TokDot : rest -> Right (iri, rest)
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "malformed @base declaration; got: "
                    <> tokenSnippet other
                )

{- | Parse a single triple block: @S P1 O1, O2 ; P2 O3 .@. Returns the
flat triple list (in source order) and the remaining token stream
after the closing @.@.
-}
parseTripleBlock ::
    [Token] -> Either RulesLoadError ([Triple], [Token])
parseTripleBlock toks = do
    (subj, rest1) <- parseSubject toks
    parsePredicateObjectList subj [] rest1

parseSubject :: [Token] -> Either RulesLoadError (Subject, [Token])
parseSubject = \case
    TokPrefixed pfx local : rest -> Right (SubjPrefixed pfx local, rest)
    TokIri iri : rest -> Right (SubjIri iri, rest)
    TokBnode name : rest -> Right (SubjBnode name, rest)
    TokLBracket : _ ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                "blank-node property lists '[ ... ]' are not supported"
    TokLParen : _ ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                "collection syntax '( ... )' is not supported"
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "expected subject (prefixed name, IRI, or blank node); got: "
                    <> tokenSnippet other
                )

{- | Walk the predicate-object list of a single subject. Re-enters
itself on @;@; the closing @.@ ends the block.
-}
parsePredicateObjectList ::
    Subject ->
    [Triple] ->
    [Token] ->
    Either RulesLoadError ([Triple], [Token])
parsePredicateObjectList subj acc toks = do
    (pred_, rest1) <- parsePredicate toks
    (objs, rest2) <- parseObjectList [] rest1
    let triples = [Triple subj pred_ o | o <- objs]
        acc' = acc ++ triples
    case rest2 of
        TokSemicolon : rest3 ->
            parsePredicateObjectList subj acc' rest3
        TokDot : rest3 -> Right (acc', rest3)
        other ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    ( "expected ';' or '.' after object list; got: "
                        <> tokenSnippet other
                    )

parsePredicate :: [Token] -> Either RulesLoadError (Predicate, [Token])
parsePredicate = \case
    TokA : rest -> Right (PredA, rest)
    TokPrefixed pfx local : rest -> Right (PredPrefixed pfx local, rest)
    TokIri iri : rest -> Right (PredIri iri, rest)
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "expected predicate; got: "
                    <> tokenSnippet other
                )

{- | Parse a comma-separated object list. Returns the objects in source
order plus the remaining tokens (starting at the @;@ or @.@ that
terminates the list).
-}
parseObjectList ::
    [Object] -> [Token] -> Either RulesLoadError ([Object], [Token])
parseObjectList acc toks = do
    (obj, rest) <- parseObject toks
    let acc' = acc ++ [obj]
    case rest of
        TokComma : rest' -> parseObjectList acc' rest'
        _ -> Right (acc', rest)

parseObject :: [Token] -> Either RulesLoadError (Object, [Token])
parseObject = \case
    -- Reject decorated string objects up front: lang tag and datatype
    -- suffix follow the string literal in source.
    TokString lit : TokLangTag _tag : _ ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "language tags on string literals are not supported "
                    <> "(literal "
                    <> renderShortLiteral lit
                    <> ")"
                )
    TokString lit : TokCaretCaret : _ ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "datatype suffixes on string literals are not supported "
                    <> "(literal "
                    <> renderShortLiteral lit
                    <> ")"
                )
    TokString lit : rest -> Right (ObjString lit, rest)
    TokInteger n : rest -> Right (ObjInteger n, rest)
    TokPrefixed pfx local : rest -> Right (ObjPrefixed pfx local, rest)
    TokIri iri : rest -> Right (ObjIri iri, rest)
    TokBnode name : rest -> Right (ObjBnode name, rest)
    TokLParen : _ ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                "collection syntax '( ... )' is not supported"
    TokLBracket : _ ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                "blank-node property lists '[ ... ]' are not supported"
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "expected object; got: "
                    <> tokenSnippet other
                )

----------------------------------------------------------------------
-- Reshape: triples to EntityDecl
----------------------------------------------------------------------

{- | Group the parsed triples by subject and reshape every
@cardano:Entity@-typed subject into an 'EntityDecl'.

The transform proceeds in three phases:

1. Build a per-subject map @{Subject -> [(Predicate, Object)]}@,
   preserving source order both across subjects and within a
   subject's predicate-object list.
2. Walk the subject map; for every subject that has an
   @a cardano:Entity@ triple, extract its @rdfs:label@ and
   @cardano:hasIdentifier _:bnode@ references.
3. For every bnode reference, look up the @cardano:Identifier@
   subject in the same map, extract its @cardano:leafType@ and
   @cardano:bytesHex@ literals, and emit one 'EntityIdentifier'.
-}
reshapeEntities :: ParsedDocument -> Either RulesLoadError [EntityDecl]
reshapeEntities doc =
    let subjectOrder = subjectsInOrder (pdTriples doc)
        groups = groupBySubject (pdTriples doc)
        entitySubjects =
            filter (isEntitySubject groups) subjectOrder
     in traverse (buildEntity groups) entitySubjects

{- | List subjects in first-occurrence source order. The Turtle
canonical form authors each subject's full statement contiguously, so
the first-occurrence index doubles as the document order.
-}
subjectsInOrder :: [Triple] -> [Subject]
subjectsInOrder = go []
  where
    go acc [] = reverse acc
    go acc (Triple s _ _ : rest)
        | s `elem` acc = go acc rest
        | otherwise = go (s : acc) rest

groupBySubject :: [Triple] -> Map Subject [(Predicate, Object)]
groupBySubject = foldl' step Map.empty
  where
    step acc (Triple s p o) =
        Map.insertWith (flip (<>)) s [(p, o)] acc

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

{- | Build an 'EntityDecl' from a known 'cardano:Entity' subject by
locating its @rdfs:label@ and walking its @cardano:hasIdentifier@
references. The entity slug is the IRI local part for prefixed
subjects (no slugify pass — the operator authored a valid Turtle local
name).
-}
buildEntity ::
    Map Subject [(Predicate, Object)] ->
    Subject ->
    Either RulesLoadError EntityDecl
buildEntity groups subj = do
    slug <- subjectSlug subj
    let pairs = Map.findWithDefault [] subj groups
    name <- requireLabel slug pairs
    bnodes <- collectHasIdentifierBnodes slug pairs
    idents <- traverse (resolveIdentifier groups slug) bnodes
    pure
        EntityDecl
            { entityName = name
            , entitySlug = slug
            , entityIdentifiers = idents
            }

-- | The slug for a subject. Only prefixed-name subjects are supported.
subjectSlug :: Subject -> Either RulesLoadError Text
subjectSlug = \case
    SubjPrefixed _ local
        | Text.null local ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    "entity subject has empty local part"
        | otherwise -> Right local
    SubjIri iri ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "entity subjects must use a prefixed name; got IRI: <"
                    <> iri
                    <> ">"
                )
    SubjBnode name ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "entity subjects must use a prefixed name; got blank node: _:"
                    <> name
                )

-- | Extract the single @rdfs:label \"…\"@ predicate from a subject's pairs.
requireLabel ::
    Text -> [(Predicate, Object)] -> Either RulesLoadError Text
requireLabel slug pairs = case mapMaybe isLabel pairs of
    [lbl] -> Right lbl
    [] ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ( "entity :"
                    <> slug
                    <> " is missing the required 'rdfs:label' triple"
                )
    _ ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
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
    Text -> [(Predicate, Object)] -> Either RulesLoadError [Text]
collectHasIdentifierBnodes slug pairs = case extractHasIdentifiers pairs of
    [] ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
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
    Map Subject [(Predicate, Object)] ->
    Text ->
    Text ->
    Either RulesLoadError EntityIdentifier
resolveIdentifier groups owningSlug bnodeName =
    case Map.lookup (SubjBnode bnodeName) groups of
        Nothing ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    ( "entity :"
                        <> owningSlug
                        <> " references unknown blank node _:"
                        <> bnodeName
                    )
        Just pairs -> do
            requireIdentifierType owningSlug bnodeName pairs
            leafTypeText <- requireSingleLiteral "cardano:leafType" pairs bnodeName "leafType"
            leafType <- parseLeafType bnodeName leafTypeText
            bytesHex <- requireSingleLiteral "cardano:bytesHex" pairs bnodeName "bytesHex"
            pure (EntityIdentifier leafType bytesHex)

requireIdentifierType ::
    Text -> Text -> [(Predicate, Object)] -> Either RulesLoadError ()
requireIdentifierType owningSlug bnodeName pairs =
    if any isIdentifierType pairs
        then Right ()
        else
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
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
    Text -> [(Predicate, Object)] -> Text -> Text -> Either RulesLoadError Text
requireSingleLiteral _predLabel pairs bnodeName localPart =
    case mapMaybe pick pairs of
        [lit] -> Right lit
        [] ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    ( "blank node _:"
                        <> bnodeName
                        <> " is missing required 'cardano:"
                        <> localPart
                        <> "' triple"
                    )
        _ ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
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
parseLeafType :: Text -> Text -> Either RulesLoadError LeafType
parseLeafType bnodeName = \case
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
                inMemoryFile
                inMemoryLine
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
tokenSnippet :: [Token] -> Text
tokenSnippet [] = "<end of input>"
tokenSnippet (t : _) = Text.pack (show t)

{- | Render a string literal back into its source-like @\"…\"@ form,
truncating to 32 characters for diagnostics.
-}
renderShortLiteral :: Text -> Text
renderShortLiteral t =
    let trimmed
            | Text.length t > 32 = Text.take 32 t <> "..."
            | otherwise = t
     in "\"" <> trimmed <> "\""

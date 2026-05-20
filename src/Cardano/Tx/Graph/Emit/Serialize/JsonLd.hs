{- |
Module      : Cardano.Tx.Graph.Emit.Serialize.JsonLd
Description : Canonical JSON-LD serializer for the joint emit (private).
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. Renders an
'EmittedGraph' value to a JSON-LD byte stream that uses the
bounded subset spec plan D6 / research R1 pins:

* a single @\@context@ object declaring the three known prefixes
  (@cardano:@, @rdfs:@, fixture-local default @:@);
* a flat @\@graph@ array of subject-grouped objects, one per RDF
  subject, with predicates as CURIE-form JSON keys and objects as
  either bare values (literals), @\@id@-wrapped node references
  (IRIs / blank nodes), or arrays thereof when a predicate is
  many-valued.

No JSON-LD framing, no RDF Dataset Normalization (c14n), no
@\@vocab@ / @\@base@ / @\@language@ / typed-literal handling —
all out of scope for spec FR-007 + SC-003 (set-equality on the
parsed triple set is the acceptance contract, not byte-equality
on the JSON-LD output).

The serializer recovers the overlay's subject structure by
parsing the rules loader's @rulesOverlayTurtle@ byte stream
in-house (small Turtle subset matching exactly what the loader
emits). Body subject blocks come straight from the projection
walker's @[BodySection]@.
-}
module Cardano.Tx.Graph.Emit.Serialize.JsonLd (
    renderJsonLd,
) where

import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Char (isAlpha, isAlphaNum, isDigit, isSpace)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

import Cardano.Tx.Graph.Emit.Lookup (BnodeName (..))
import Cardano.Tx.Graph.Emit.Triple (
    BodySection (..),
    Object (..),
    Predicate (..),
    Subject (..),
    SubjectBlock (..),
 )
import Cardano.Tx.Graph.Emit.Vocab (
    cardanoPrefix,
    fixturePrefixBase,
    rdfsPrefix,
 )

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

{- | Render the joint JSON-LD output for a fixture slug, the
operator-entity overlay bytes (verbatim from the rules loader),
and the projection walker's body sections.

Shape (research R1):

@
{
  "\@context": {
    "cardano": "\<cardanoPrefix\>",
    "rdfs":    "\<rdfsPrefix\>",
    "":        "\<fixturePrefixBase + slug + #\>"
  },
  "\@graph": [
    { "\@id": ":alice",
      "\@type": "cardano:Entity",
      "rdfs:label": "alice",
      "cardano:hasIdentifier": [
        { "\@id": "_:alice_paymentKey" },
        { "\@id": "_:alice_stakeKey" }
      ]
    },
    …
  ]
}
@

A trailing newline is appended after @Aeson.encode@ for unix-tool
friendliness; the byte sequence is otherwise the @Aeson.encode@
output for the constructed 'Value'.
-}
renderJsonLd ::
    Text ->
    [(Text, Text)] ->
    ByteString ->
    [BodySection] ->
    ByteString
renderJsonLd slug _explicitPrefixes overlayBytes body =
    let overlayBlocks = parseOverlaySubjectBlocks overlayBytes
        bodyBlocks = concatMap sectionBlocks body
        allBlocks = overlayBlocks <> bodyBlocks
        ctx = buildContext slug
        graph = Aeson.toJSON (map subjectBlockToValue allBlocks)
        doc =
            Object $
                KeyMap.fromList
                    [ (Key.fromText "@context", ctx)
                    , (Key.fromText "@graph", graph)
                    ]
     in BSL.toStrict (Aeson.encode doc) <> "\n"

----------------------------------------------------------------------
-- @context construction
----------------------------------------------------------------------

buildContext :: Text -> Value
buildContext slug =
    Object $
        KeyMap.fromList
            [ (Key.fromText "cardano", String cardanoPrefix)
            , (Key.fromText "rdfs", String rdfsPrefix)
            , (Key.fromText "", String (fixturePrefixBase <> slug <> "#"))
            ]

----------------------------------------------------------------------
-- Per-subject JSON object
----------------------------------------------------------------------

{- | Build the JSON-LD object for one subject block. Predicates
appearing multiple times under the same subject collapse to a
JSON array under one key; @rdf:type@ ('PRdfType') maps to the
JSON-LD @\@type@ key with a bare CURIE-string value (not an
@\@id@-wrapped object).
-}
subjectBlockToValue :: SubjectBlock -> Value
subjectBlockToValue SubjectBlock{subjectBlockSubject, subjectBlockPredicates} =
    let (typeObjs, otherPairs) = partitionTypePairs subjectBlockPredicates
        grouped = groupPredicatesInOrder otherPairs
        idEntry = (Key.fromText "@id", String (renderSubjectText subjectBlockSubject))
        typeEntry = case typeObjs of
            [] -> []
            os -> [(Key.fromText "@type", typeValuesToJson os)]
        predEntries =
            [ (Key.fromText p, objectsToJson os)
            | (p, os) <- grouped
            ]
     in Object (KeyMap.fromList (idEntry : typeEntry <> predEntries))

{- | Split the @(Predicate, Object)@ list into the @rdf:type@
objects (in source order) and the rest (also in source order).
-}
partitionTypePairs ::
    [(Predicate, Object)] ->
    ([Object], [(Text, Object)])
partitionTypePairs = foldr step ([], [])
  where
    step (PRdfType, o) (ts, ps) = (o : ts, ps)
    step (PIri p, o) (ts, ps) = (ts, (p, o) : ps)

{- | Group consecutive equal predicates into @(predicateText,
[objects])@ tuples, preserving the input order of distinct
predicates and within-group order of objects. The emitter writes
same-predicate runs adjacent (see
'Cardano.Tx.Graph.Emit.Project'), so a fold suffices.
-}
groupPredicatesInOrder ::
    [(Text, Object)] ->
    [(Text, [Object])]
groupPredicatesInOrder = foldr step []
  where
    step (p, o) acc = case acc of
        ((p', os) : rest)
            | p == p' -> (p', o : os) : rest
        _ -> (p, [o]) : acc

{- | Render the @\@type@ value: a bare CURIE string when there is
exactly one, an array of CURIE strings otherwise. The serializer
only ever sees 'OIri' objects under @rdf:type@; non-IRI types
would be ill-formed RDF and are passed through as JSON strings of
their text rendering (defensive — the projection walker never
emits a literal under @rdf:type@).
-}
typeValuesToJson :: [Object] -> Value
typeValuesToJson = \case
    [o] -> String (renderTypeText o)
    os -> Aeson.toJSON (map (String . renderTypeText) os)

renderTypeText :: Object -> Text
renderTypeText = \case
    OIri t -> t
    OBnode (BnodeName n) -> "_:" <> n
    OStringLit s -> s
    OIntLit i -> Text.pack (show i)

{- | Render the predicate-value(s) for a non-type predicate. A
single object emits as a bare value; a many-valued predicate
emits as a JSON array.
-}
objectsToJson :: [Object] -> Value
objectsToJson = \case
    [o] -> objectToJson o
    os -> Aeson.toJSON (map objectToJson os)

{- | Render one object value to JSON. Blank-node and IRI objects
become @{ "\@id": "<curie-or-bnode>" }@; string literals stay
JSON strings; integer literals stay JSON numbers.
-}
objectToJson :: Object -> Value
objectToJson = \case
    OBnode (BnodeName n) ->
        Object $
            KeyMap.fromList
                [(Key.fromText "@id", String ("_:" <> n))]
    OIri t ->
        Object $
            KeyMap.fromList
                [(Key.fromText "@id", String t)]
    OStringLit s -> String s
    OIntLit i -> Number (fromInteger i)

----------------------------------------------------------------------
-- Subject text rendering
----------------------------------------------------------------------

renderSubjectText :: Subject -> Text
renderSubjectText = \case
    SBnode (BnodeName n) -> "_:" <> n
    SIri t -> t

----------------------------------------------------------------------
-- Overlay parsing (small Turtle subset)
----------------------------------------------------------------------

{- | Parse the rules-loader overlay byte stream into a list of
@SubjectBlock@ values in source order. The byte stream's shape
is fixed by 'Cardano.Tx.Graph.Rules.Load.Emit.Overlay': three
@\@prefix@ lines, a comment, then one or more subject blocks
separated by blank lines. We skip prefix declarations and
comments and parse the rest as canonical-form Turtle.

An empty input yields an empty list. A parse failure (malformed
overlay bytes) is a loader invariant violation, surfaced as an
error so the regression is loud rather than silent.
-}
parseOverlaySubjectBlocks :: ByteString -> [SubjectBlock]
parseOverlaySubjectBlocks bs
    | BS.null bs = []
    | otherwise =
        case lexTokens (TextEncoding.decodeUtf8 bs) of
            Left err ->
                error $
                    "Cardano.Tx.Graph.Emit.Serialize.JsonLd: "
                        <> "overlay lex failure: "
                        <> Text.unpack err
            Right toks ->
                case parseSubjectBlocks toks of
                    Left err ->
                        error $
                            "Cardano.Tx.Graph.Emit.Serialize.JsonLd: "
                                <> "overlay parse failure: "
                                <> Text.unpack err
                    Right blocks -> blocks

----------------------------------------------------------------------
-- Mini Turtle lexer
----------------------------------------------------------------------

data Tok
    = -- | @_:NAME@ — the wrapped 'Text' is the bare local part.
      TBnode !Text
    | -- | A prefixed CURIE — full @prefix:local@ form (e.g.
      -- @":alice"@, @"cardano:Entity"@).
      TCurie !Text
    | -- | The Turtle @a@ keyword (rdf:type).
      TKwA
    | -- | A double-quoted string literal (content only, no
      -- quotes); only @\\\"@ escapes are supported.
      TString !Text
    | -- | A non-negative integer literal.
      TInt !Integer
    | -- | The @;@ predicate continuation.
      TSemi
    | -- | The @.@ statement terminator.
      TDot
    deriving stock (Eq, Show)

{- | Lex the canonical-overlay byte stream (decoded as UTF-8) to
a list of tokens, skipping whitespace, comments (@\#@ to end of
line), and @\@prefix@ / @\@base@ declarations (a directive runs
to the next @.@).
-}
lexTokens :: Text -> Either Text [Tok]
lexTokens = go
  where
    go t = case Text.uncons t of
        Nothing -> Right []
        Just (c, rest)
            | isSpace c -> go rest
            | c == '#' -> go (Text.dropWhile (/= '\n') rest)
            | c == '@' -> go (skipDirective rest)
            | c == '_' && Text.take 1 rest == ":" ->
                let after0 = Text.drop 1 rest
                    (name, after) = Text.span isLocalChar after0
                 in if Text.null name
                        then Left "lexer: empty blank-node name after '_:'"
                        else (TBnode name :) <$> go after
            | c == ':' ->
                let (local, after) = Text.span isLocalChar rest
                 in (TCurie (":" <> local) :) <$> go after
            | c == '"' -> case lexString rest of
                Left err -> Left err
                Right (str, after) -> (TString str :) <$> go after
            | c == ';' -> (TSemi :) <$> go rest
            | c == '.' -> (TDot :) <$> go rest
            | isDigit c ->
                let (numTxt, after) = Text.span isDigit t
                 in case reads (Text.unpack numTxt) of
                        [(n, "")] -> (TInt n :) <$> go after
                        _ ->
                            Left $
                                "lexer: malformed integer at " <> numTxt
            | isAlpha c || c == '_' ->
                let (name, after1) = Text.span isLocalChar t
                 in case Text.uncons after1 of
                        Just (':', after2) ->
                            let (local, after3) = Text.span isLocalChar after2
                             in (TCurie (name <> ":" <> local) :) <$> go after3
                        _ ->
                            if name == "a"
                                then (TKwA :) <$> go after1
                                else
                                    Left $
                                        "lexer: bare identifier without "
                                            <> "':local': "
                                            <> name
            | otherwise ->
                Left $
                    "lexer: unexpected char "
                        <> Text.singleton c

-- | Locals: letters, digits, underscore, hyphen.
isLocalChar :: Char -> Bool
isLocalChar c = isAlphaNum c || c == '_' || c == '-'

{- | Skip a @\@prefix@ / @\@base@ directive — runs to the
statement-terminating @.@ that sits /outside/ any @\<…\>@ IRI
brackets. IRIs in prefix declarations routinely contain @.@
characters (e.g. @\<https://lambdasistemi.github.io/…\>@), so a
naive break-on-@.@ would terminate mid-IRI.
-}
skipDirective :: Text -> Text
skipDirective = outsideBracket
  where
    outsideBracket t = case Text.uncons t of
        Nothing -> t
        Just (c, rest)
            | c == '<' -> insideBracket rest
            | c == '.' -> rest
            | otherwise -> outsideBracket rest
    insideBracket t = case Text.uncons t of
        Nothing -> t
        Just (c, rest)
            | c == '>' -> outsideBracket rest
            | otherwise -> insideBracket rest

{- | Lex a double-quoted string. Supports only @\\\"@ as an
escape (the canonical-form serializers do not emit other
escapes). Returns @(content, remaining)@ — remaining starts
after the closing quote.
-}
lexString :: Text -> Either Text (Text, Text)
lexString = goS Text.empty
  where
    goS acc t = case Text.uncons t of
        Nothing -> Left "lexer: unterminated string literal"
        Just (c, rest)
            | c == '"' -> Right (acc, rest)
            | c == '\\' -> case Text.uncons rest of
                Just (e, rest') -> goS (Text.snoc acc e) rest'
                Nothing -> Left "lexer: dangling backslash in string"
            | otherwise -> goS (Text.snoc acc c) rest

----------------------------------------------------------------------
-- Mini Turtle parser
----------------------------------------------------------------------

{- | Parse a token list into a list of @SubjectBlock@s. Each
block starts with a subject token, follows with one or more
@predicate object@ pairs separated by @;@, and ends with @.@.
-}
parseSubjectBlocks :: [Tok] -> Either Text [SubjectBlock]
parseSubjectBlocks [] = Right []
parseSubjectBlocks toks = do
    (block, rest) <- parseSubjectBlock toks
    (block :) <$> parseSubjectBlocks rest

parseSubjectBlock :: [Tok] -> Either Text (SubjectBlock, [Tok])
parseSubjectBlock toks = do
    (subj, toks1) <- parseSubject toks
    (predObjs, toks2) <- parsePredicateObjects toks1
    pure
        ( SubjectBlock
            { subjectBlockSubject = subj
            , subjectBlockPredicates = predObjs
            }
        , toks2
        )

parseSubject :: [Tok] -> Either Text (Subject, [Tok])
parseSubject = \case
    (TBnode n : rest) -> Right (SBnode (BnodeName n), rest)
    (TCurie c : rest) -> Right (SIri c, rest)
    other ->
        Left $
            "parser: expected subject; saw "
                <> tokHead other

{- | Parse a (possibly empty) @predicate object ;...@ run
followed by a terminating @.@. Returns the (predicate, object)
pairs and the remaining tokens.
-}
parsePredicateObjects :: [Tok] -> Either Text ([(Predicate, Object)], [Tok])
parsePredicateObjects = \case
    (TDot : rest) -> Right ([], rest)
    toks -> do
        (p, toks1) <- parsePredicate toks
        (o, toks2) <- parseObject toks1
        case toks2 of
            (TSemi : rest) -> do
                (more, rest') <- parsePredicateObjects rest
                pure ((p, o) : more, rest')
            (TDot : rest) -> pure ([(p, o)], rest)
            other ->
                Left $
                    "parser: expected ';' or '.' after object; saw "
                        <> tokHead other

parsePredicate :: [Tok] -> Either Text (Predicate, [Tok])
parsePredicate = \case
    (TKwA : rest) -> Right (PRdfType, rest)
    (TCurie c : rest) -> Right (PIri c, rest)
    other ->
        Left $
            "parser: expected predicate ('a' or CURIE); saw "
                <> tokHead other

parseObject :: [Tok] -> Either Text (Object, [Tok])
parseObject = \case
    (TBnode n : rest) -> Right (OBnode (BnodeName n), rest)
    (TCurie c : rest) -> Right (OIri c, rest)
    (TString s : rest) -> Right (OStringLit s, rest)
    (TInt i : rest) -> Right (OIntLit i, rest)
    other ->
        Left $
            "parser: expected object; saw "
                <> tokHead other

-- | Render the head token (or @<eof>@) for error messages.
tokHead :: [Tok] -> Text
tokHead = \case
    [] -> "<eof>"
    (t : _) -> Text.pack (show t)

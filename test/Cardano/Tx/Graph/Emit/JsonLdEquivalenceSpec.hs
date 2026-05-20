{- |
Module      : Cardano.Tx.Graph.Emit.JsonLdEquivalenceSpec
Description : JSON-LD ≡ Turtle on parsed triple set (T011 / FR-007 / SC-003).
License     : Apache-2.0

Per-fixture set-equality check: the triple set parsed out of the
emitter's Turtle output must equal the triple set parsed out of
the emitter's JSON-LD output for the same fixture.

Acceptance contract (spec FR-007 + SC-003 + plan D6 + research
R1): JSON-LD output is acceptance-tested on the parsed triple
set, not on byte-equality. The serializer renders an in-house
bounded JSON-LD subset (@\@context@ + @\@graph@ + subject-grouped
objects); this spec parses that subset back to triples and
compares against the canonical Turtle output parsed by a small
in-house Turtle parser.

The spec exercises all 11 fixtures currently GREEN in
'Cardano.Tx.Graph.EmitGoldenSpec' (post-T010 — SC-001 closed).
Set-equality is asserted via @Set ParsedTriple@; a divergence
surfaces as a missing-or-extra triple diff in the failure
output.
-}
module Cardano.Tx.Graph.Emit.JsonLdEquivalenceSpec (spec) where

import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.Char (isAlpha, isAlphaNum, isDigit, isSpace)
import Data.Foldable qualified as Foldable
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.FilePath ((</>))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    EmittedGraph (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl,
    RulesLoadResult (..),
    loadRulesFile,
    rulesEntities,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.S01_AmaruTreasurySwap qualified as S01
import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02
import Fixtures.RewriteRedesign.S03_MultiAssetTransfer qualified as S03
import Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap qualified as S04
import Fixtures.RewriteRedesign.S05_WithdrawalScriptStake qualified as S05
import Fixtures.RewriteRedesign.S06_StakePoolDelegation qualified as S06
import Fixtures.RewriteRedesign.S07_VoteDelegation qualified as S07
import Fixtures.RewriteRedesign.S08_ContingencyDisburse qualified as S08
import Fixtures.RewriteRedesign.S09_MpfsFactsRequest qualified as S09
import Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal qualified as S10
import Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal qualified as S11

import Data.ByteString qualified as BS
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
 )

----------------------------------------------------------------------
-- Fixture roster (mirrors EmitGoldenSpec / VocabTraceabilitySpec)
----------------------------------------------------------------------

-- | Fixtures GREEN in 'EmitGoldenSpec' at end of T010 (all 11).
enabledFixtures :: [(String, ConwayTx)]
enabledFixtures =
    [ ("01-amaru-treasury-swap", S01.tx)
    , ("02-alice-bob-ada", S02.tx)
    , ("03-multi-asset-transfer", S03.tx)
    , ("04-mint-spend-script-overlap", S04.tx)
    , ("05-withdrawal-script-stake", S05.tx)
    , ("06-stake-pool-delegation", S06.tx)
    , ("07-vote-delegation", S07.tx)
    , ("08-contingency-disburse", S08.tx)
    , ("09-mpfs-facts-request", S09.tx)
    , ("10-governance-treasury-withdrawal", S10.tx)
    , ("11-amaru-treasury-swap-real", S11.tx)
    ]

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit JSON-LD ≡ Turtle (T011)" $
        mapM_ fixtureSpec enabledFixtures

fixtureSpec :: (String, ConwayTx) -> Spec
fixtureSpec (slug, tx) = describe slug $ do
    let dir = "test/fixtures/rewrite-redesign" </> slug
        rulesPath = dir </> "rules.yaml"
    (entities, overlay) <- runIO (loadEntitiesAndOverlay rulesPath)
    case emit tx emptyUtxo entities of
        Left err ->
            it "emit produced Right" $
                expectationFailure $
                    "JsonLdEquivalenceSpec setup: "
                        <> slug
                        <> ": emit returned Left "
                        <> show err
        Right g -> do
            let joint = g{graphOverlayTurtle = overlay}
                turtleBytes = serialize Turtle slug joint
                jsonLdBytes = serialize JsonLd slug joint
            it "Turtle ≡ JSON-LD on the parsed triple set" $ do
                let turtleTriples =
                        case parseCanonicalTurtle turtleBytes of
                            Right ts -> ts
                            Left err ->
                                error $
                                    "JsonLdEquivalenceSpec: Turtle "
                                        <> "parse failed for "
                                        <> slug
                                        <> ": "
                                        <> Text.unpack err
                    jsonLdTriples =
                        case parseSubsetJsonLd jsonLdBytes of
                            Right ts -> ts
                            Left err ->
                                error $
                                    "JsonLdEquivalenceSpec: JSON-LD "
                                        <> "parse failed for "
                                        <> slug
                                        <> ": "
                                        <> Text.unpack err
                jsonLdTriples `shouldBe` turtleTriples

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

loadEntitiesAndOverlay ::
    FilePath -> IO ([EntityDecl], ByteString)
loadEntitiesAndOverlay path = do
    result <- loadRulesFile path
    case result of
        Right res@RulesLoadResult{rulesOverlayTurtle} ->
            pure (rulesEntities res, rulesOverlayTurtle)
        Left err ->
            fail $
                "JsonLdEquivalenceSpec.loadEntitiesAndOverlay: "
                    <> path
                    <> ": "
                    <> show err

----------------------------------------------------------------------
-- Parsed-triple representation (shared between both parsers)
----------------------------------------------------------------------

{- | The normalized object value used by both parsers. @PObjRef@
covers both IRI CURIEs (e.g. @":alice"@, @"cardano:Entity"@) and
blank-node references (@"_:alice_paymentKey"@) — both serializers
emit these as text-identical tokens, so set comparison works
without further normalization.
-}
data ParsedObject
    = PObjRef !Text
    | PObjString !Text
    | PObjInt !Integer
    deriving stock (Eq, Ord, Show)

-- | A parsed triple: subject token, predicate token, object value.
type ParsedTriple = (Text, Text, ParsedObject)

{- | The canonical text used for the @rdf:type@ predicate
regardless of which output it was parsed from — Turtle's @a@
keyword and JSON-LD's @\@type@ both normalize here.
-}
rdfTypePredicate :: Text
rdfTypePredicate = "a"

----------------------------------------------------------------------
-- Canonical-Turtle parser (in-house, bounded subset)
----------------------------------------------------------------------

parseCanonicalTurtle :: ByteString -> Either Text (Set ParsedTriple)
parseCanonicalTurtle bs
    | BS.null bs = Right Set.empty
    | otherwise = do
        toks <- lexTurtleTokens (TextEncoding.decodeUtf8 bs)
        blocks <- parseTurtleSubjectBlocks toks
        pure (Set.fromList (concatMap blockToTriples blocks))

{- | One subject block — used as the intermediate result of the
Turtle parser before flattening to triples.
-}
data TurtleBlock = TurtleBlock
    { tbSubject :: !Text
    , tbPairs :: ![(Text, ParsedObject)]
    }

blockToTriples :: TurtleBlock -> [ParsedTriple]
blockToTriples TurtleBlock{tbSubject, tbPairs} =
    [(tbSubject, p, o) | (p, o) <- tbPairs]

----------------------------------------------------------------------
-- Mini Turtle lexer (mirrors the JsonLd module's private lexer;
-- duplicated intentionally — the test module cannot import the
-- private serializer submodule, and the parser is small.)
----------------------------------------------------------------------

data TTok
    = TtBnode !Text
    | TtCurie !Text
    | TtKwA
    | TtString !Text
    | TtInt !Integer
    | TtSemi
    | TtDot
    deriving stock (Eq, Show)

lexTurtleTokens :: Text -> Either Text [TTok]
lexTurtleTokens = goT
  where
    goT t = case Text.uncons t of
        Nothing -> Right []
        Just (c, rest)
            | isSpace c -> goT rest
            | c == '#' -> goT (Text.dropWhile (/= '\n') rest)
            | c == '@' -> goT (skipDirective rest)
            | c == '_' && Text.take 1 rest == ":" ->
                let after0 = Text.drop 1 rest
                    (name, after) = Text.span isLocalChar after0
                 in if Text.null name
                        then Left "turtle-lex: empty blank-node name after '_:'"
                        else (TtBnode name :) <$> goT after
            | c == ':' ->
                let (local, after) = Text.span isLocalChar rest
                 in (TtCurie (":" <> local) :) <$> goT after
            | c == '"' -> case lexTurtleString rest of
                Left err -> Left err
                Right (str, after) -> (TtString str :) <$> goT after
            | c == ';' -> (TtSemi :) <$> goT rest
            | c == '.' -> (TtDot :) <$> goT rest
            | isDigit c ->
                let (numTxt, after) = Text.span isDigit t
                 in case reads (Text.unpack numTxt) of
                        [(n, "")] -> (TtInt n :) <$> goT after
                        _ ->
                            Left $
                                "turtle-lex: malformed integer: "
                                    <> numTxt
            | isAlpha c || c == '_' ->
                let (name, after1) = Text.span isLocalChar t
                 in case Text.uncons after1 of
                        Just (':', after2) ->
                            let (local, after3) =
                                    Text.span isLocalChar after2
                             in (TtCurie (name <> ":" <> local) :)
                                    <$> goT after3
                        _ ->
                            if name == "a"
                                then (TtKwA :) <$> goT after1
                                else
                                    Left $
                                        "turtle-lex: bare identifier "
                                            <> "without ':local': "
                                            <> name
            | otherwise ->
                Left $
                    "turtle-lex: unexpected char: "
                        <> Text.singleton c

isLocalChar :: Char -> Bool
isLocalChar c = isAlphaNum c || c == '_' || c == '-'

{- | Skip an @\@prefix@ / @\@base@ directive — runs to the first
@.@ outside any @\<…\>@ IRI bracket pair.
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

lexTurtleString :: Text -> Either Text (Text, Text)
lexTurtleString = goS Text.empty
  where
    goS acc t = case Text.uncons t of
        Nothing -> Left "turtle-lex: unterminated string literal"
        Just (c, rest)
            | c == '"' -> Right (acc, rest)
            | c == '\\' -> case Text.uncons rest of
                Just (e, rest') -> goS (Text.snoc acc e) rest'
                Nothing -> Left "turtle-lex: dangling backslash"
            | otherwise -> goS (Text.snoc acc c) rest

----------------------------------------------------------------------
-- Turtle parser → [TurtleBlock]
----------------------------------------------------------------------

parseTurtleSubjectBlocks :: [TTok] -> Either Text [TurtleBlock]
parseTurtleSubjectBlocks [] = Right []
parseTurtleSubjectBlocks toks = do
    (b, rest) <- parseOneBlock toks
    (b :) <$> parseTurtleSubjectBlocks rest

parseOneBlock :: [TTok] -> Either Text (TurtleBlock, [TTok])
parseOneBlock toks = do
    (subj, toks1) <- parseTurtleSubject toks
    (pairs, toks2) <- parseTurtlePredObjs toks1
    pure
        ( TurtleBlock{tbSubject = subj, tbPairs = pairs}
        , toks2
        )

parseTurtleSubject :: [TTok] -> Either Text (Text, [TTok])
parseTurtleSubject = \case
    (TtBnode n : rest) -> Right ("_:" <> n, rest)
    (TtCurie c : rest) -> Right (c, rest)
    other ->
        Left $
            "turtle-parse: expected subject; saw "
                <> turtleTokHead other

parseTurtlePredObjs ::
    [TTok] -> Either Text ([(Text, ParsedObject)], [TTok])
parseTurtlePredObjs = \case
    (TtDot : rest) -> Right ([], rest)
    toks -> do
        (p, toks1) <- parseTurtlePredicate toks
        (o, toks2) <- parseTurtleObject toks1
        case toks2 of
            (TtSemi : rest) -> do
                (more, rest') <- parseTurtlePredObjs rest
                pure ((p, o) : more, rest')
            (TtDot : rest) -> pure ([(p, o)], rest)
            other ->
                Left $
                    "turtle-parse: expected ';' or '.' after object; saw "
                        <> turtleTokHead other

parseTurtlePredicate :: [TTok] -> Either Text (Text, [TTok])
parseTurtlePredicate = \case
    (TtKwA : rest) -> Right (rdfTypePredicate, rest)
    (TtCurie c : rest) -> Right (c, rest)
    other ->
        Left $
            "turtle-parse: expected predicate; saw "
                <> turtleTokHead other

parseTurtleObject :: [TTok] -> Either Text (ParsedObject, [TTok])
parseTurtleObject = \case
    (TtBnode n : rest) -> Right (PObjRef ("_:" <> n), rest)
    (TtCurie c : rest) -> Right (PObjRef c, rest)
    (TtString s : rest) -> Right (PObjString s, rest)
    (TtInt i : rest) -> Right (PObjInt i, rest)
    other ->
        Left $
            "turtle-parse: expected object; saw "
                <> turtleTokHead other

turtleTokHead :: [TTok] -> Text
turtleTokHead = \case
    [] -> "<eof>"
    (t : _) -> Text.pack (show t)

----------------------------------------------------------------------
-- JSON-LD parser (bounded subset matching the in-house serializer)
----------------------------------------------------------------------

{- | Parse the JSON-LD byte stream the serializer produces back
to a set of triples. The expected shape (research R1):

@
{ "\@context": {...},
  "\@graph": [
    { "\@id": <subject>,
      "\@type": <curie> | [<curie>, ...],   -- optional
      "<curie>": <object-or-array>,
      ...
    },
    ...
  ]
}
@

@\@context@ is ignored (the prefixes match by construction with
the Turtle output; both use the same CURIE forms).
-}
parseSubsetJsonLd :: ByteString -> Either Text (Set ParsedTriple)
parseSubsetJsonLd bs = do
    val <- case Aeson.eitherDecodeStrict bs of
        Right v -> Right (v :: Value)
        Left e ->
            Left $
                "json-ld-parse: aeson decode failed: " <> Text.pack e
    graph <- extractGraph val
    triples <- traverse subjectToTriples graph
    pure (Set.fromList (concat triples))

extractGraph :: Value -> Either Text [KeyMap.KeyMap Value]
extractGraph = \case
    Object km -> case KeyMap.lookup (Key.fromText "@graph") km of
        Just (Array xs) ->
            traverse expectObject (Foldable.toList xs)
        Just _ -> Left "json-ld-parse: '@graph' is not an array"
        Nothing -> Left "json-ld-parse: missing '@graph' key"
    _ -> Left "json-ld-parse: top-level value is not an object"
  where
    expectObject = \case
        Object km -> Right km
        _ -> Left "json-ld-parse: '@graph' element is not an object"

subjectToTriples :: KeyMap.KeyMap Value -> Either Text [ParsedTriple]
subjectToTriples km = do
    subjText <- case KeyMap.lookup (Key.fromText "@id") km of
        Just (String s) -> Right s
        Just _ -> Left "json-ld-parse: '@id' is not a string"
        Nothing -> Left "json-ld-parse: subject missing '@id'"
    let pairs = [(Key.toText k, v) | (k, v) <- KeyMap.toList km]
        otherPairs =
            [(k, v) | (k, v) <- pairs, k /= "@id"]
    concat
        <$> traverse (pairToTriples subjText) otherPairs

pairToTriples ::
    Text -> (Text, Value) -> Either Text [ParsedTriple]
pairToTriples subj (key, value)
    | key == "@type" = do
        types <- parseTypeValue value
        pure [(subj, rdfTypePredicate, PObjRef t) | t <- types]
    | otherwise = do
        objs <- parseObjectValue value
        pure [(subj, key, o) | o <- objs]

{- | Parse the value of a @\@type@ key — either a bare string or
an array of strings.
-}
parseTypeValue :: Value -> Either Text [Text]
parseTypeValue = \case
    String s -> Right [s]
    Array xs ->
        traverse
            ( \case
                String s -> Right s
                _ -> Left "json-ld-parse: '@type' element is not a string"
            )
            (Foldable.toList xs)
    _ -> Left "json-ld-parse: '@type' is not a string or array"

{- | Parse the value of a non-type predicate key — a single
object (literal or node reference) or an array thereof.
-}
parseObjectValue :: Value -> Either Text [ParsedObject]
parseObjectValue = \case
    Array xs -> traverse parseSingleObject (Foldable.toList xs)
    other -> fmap pure (parseSingleObject other)

parseSingleObject :: Value -> Either Text ParsedObject
parseSingleObject v = case v of
    String s -> Right (PObjString s)
    Number _ -> case Aeson.fromJSON v :: Aeson.Result Integer of
        Aeson.Success i -> Right (PObjInt i)
        Aeson.Error e ->
            Left $
                "json-ld-parse: non-integer number literal: "
                    <> Text.pack e
    Object km -> case KeyMap.lookup (Key.fromText "@id") km of
        Just (String s) -> Right (PObjRef s)
        Just _ -> Left "json-ld-parse: '@id' is not a string"
        Nothing ->
            Left $
                "json-ld-parse: object lacks '@id': "
                    <> Text.pack (show km)
    other ->
        Left $
            "json-ld-parse: unexpected object value: "
                <> Text.pack (show other)

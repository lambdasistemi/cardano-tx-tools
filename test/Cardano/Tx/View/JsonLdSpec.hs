{- |
Module      : Cardano.Tx.View.JsonLdSpec
Description : tx-view --view json-ld projection spec (slice S4 of #51).
License     : Apache-2.0

S4 slice of #51 (T400-T407 in @specs\/051-sparql-views\/tasks.md@).

Asserts the @json-ld@ packaged view over an existing canonical Turtle
graph file:

* exits 0 with empty stderr;
* emits stdout that parses as JSON-LD;
* preserves a bounded supported triple subset between the Turtle input
  and JSON-LD output;
* exits 0 with parseable empty JSON-LD for an empty-match graph.

The bounded subset intentionally covers the graph wiring needed by
browser consumers without importing a full RDF runtime: @rdf:type@ via
Turtle @a@ / JSON-LD @\@type@, labels, transaction outputs, output
addresses, and address bech32 literals.
-}
module Cardano.Tx.View.JsonLdSpec (spec) where

import Control.Monad (unless)
import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Char (isSpace)
import Data.Foldable qualified as Foldable
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (
    CreateProcess (..),
    StdStream (..),
    proc,
    waitForProcess,
    withCreateProcess,
 )
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
 )

----------------------------------------------------------------------
-- Spec entry point
----------------------------------------------------------------------

spec :: Spec
spec =
    describe "Cardano.Tx.View - json-ld projection (slice S4 of #51)" $ do
        mExe <- runIO locateTxView
        case mExe of
            Nothing ->
                it "tx-view executable is on PATH or pointed at by TX_VIEW_EXE" $
                    expectationFailure $
                        "tx-view is neither on PATH (via cabal's "
                            <> "build-tool-depends) nor pointed at by "
                            <> "TX_VIEW_EXE. The json-ld slice cannot "
                            <> "run without the executable in the sandbox."
            Just exe -> do
                amaruSwapCase exe
                emptyGraphCase exe

----------------------------------------------------------------------
-- Amaru swap fixture - parseability and bounded triple preservation
----------------------------------------------------------------------

amaruSwapCase :: FilePath -> Spec
amaruSwapCase exe =
    describe "01-amaru-treasury-swap" $
        it "emits parseable JSON-LD preserving the supported triple subset" $ do
            let graphPath =
                    "test/fixtures/rewrite-redesign"
                        </> "01-amaru-treasury-swap"
                        </> "expected.ttl"
            turtleBytes <- BS.readFile graphPath
            (code, out, err) <-
                runExe
                    exe
                    [ "--graph"
                    , graphPath
                    , "--view"
                    , "json-ld"
                    ]
            assertJsonLdCommandSucceeded code err
            value <- decodeJsonLd out
            jsonTriples <- expectRight "JSON-LD supported triples" (parseSupportedJsonLd value)
            turtleTriples <-
                expectRight
                    "Turtle supported triples"
                    (parseSupportedTurtle turtleBytes)
            jsonTriples `shouldBe` turtleTriples

----------------------------------------------------------------------
-- Empty-result invariant - FR-008 / T405
----------------------------------------------------------------------

emptyGraphCase :: FilePath -> Spec
emptyGraphCase exe =
    it "empty graph - exit 0 with parseable empty JSON-LD" $
        withSystemTempDirectory "tx-view-json-ld-empty" $ \dir -> do
            let graphPath = dir </> "empty.ttl"
            BS.writeFile
                graphPath
                ( BS8.pack
                    ( "@prefix cardano: "
                        <> "<https://lambdasistemi.github.io/"
                        <> "cardano-knowledge-maps/vocab/cardano#> .\n"
                    )
                )
            (code, out, err) <-
                runExe
                    exe
                    [ "--graph"
                    , graphPath
                    , "--view"
                    , "json-ld"
                    ]
            assertJsonLdCommandSucceeded code err
            value <- decodeJsonLd out
            triples <- expectRight "JSON-LD supported triples" (parseSupportedJsonLd value)
            triples `shouldBe` Set.empty

----------------------------------------------------------------------
-- Subprocess helpers
----------------------------------------------------------------------

{- | Locate the tx-view binary. Prefers @TX_VIEW_EXE@ when set (the
nix flake check sandbox path); falls back to @findExecutable@ on
@PATH@ (the @cabal test@ path, where cabal places the binary on
@PATH@ via @build-tool-depends@).
-}
locateTxView :: IO (Maybe FilePath)
locateTxView = do
    mEnv <- lookupEnv "TX_VIEW_EXE"
    case mEnv of
        Just p | not (null p) -> pure (Just p)
        _ -> findExecutable "tx-view"

-- | Spawn an external program, capture stdout + stderr, return exit code.
runExe :: FilePath -> [String] -> IO (ExitCode, ByteString, ByteString)
runExe prog args = do
    let cp =
            (proc prog args)
                { std_in = NoStream
                , std_out = CreatePipe
                , std_err = CreatePipe
                }
    withCreateProcess cp $ \_mIn mOut mErr ph ->
        case (mOut, mErr) of
            (Just hOut, Just hErr) -> do
                out <- BS.hGetContents hOut
                err <- BS.hGetContents hErr
                hClose hOut
                hClose hErr
                code <- waitForProcess ph
                pure (code, out, err)
            _ ->
                fail $
                    "runExe: stdout/stderr pipes not created for " <> prog

assertJsonLdCommandSucceeded :: ExitCode -> ByteString -> IO ()
assertJsonLdCommandSucceeded code err =
    unless (code == ExitSuccess && BS.null err) $
        expectationFailure $
            "tx-view --view json-ld failed: exit="
                <> show code
                <> " stderr="
                <> BS8.unpack err

decodeJsonLd :: ByteString -> IO Value
decodeJsonLd out =
    case Aeson.eitherDecodeStrict' out of
        Right value -> pure value
        Left err ->
            fail $
                "tx-view --view json-ld stdout is not parseable JSON: "
                    <> err

expectRight :: String -> Either Text a -> IO a
expectRight label =
    either
        (fail . ((label <> ": ") <>) . Text.unpack)
        pure

----------------------------------------------------------------------
-- Bounded supported triple representation
----------------------------------------------------------------------

data SupportedObject
    = ObjRef !Text
    | ObjString !Text
    deriving stock (Eq, Ord, Show)

type SupportedTriple = (Text, Text, SupportedObject)

rdfTypePredicate :: Text
rdfTypePredicate = "a"

supportedPredicates :: Set Text
supportedPredicates =
    Set.fromList
        [ rdfTypePredicate
        , "rdfs:label"
        , "cardano:hasOutput"
        , "cardano:atAddress"
        , "cardano:bech32"
        ]

----------------------------------------------------------------------
-- Canonical Turtle subset parser for supported triples
----------------------------------------------------------------------

parseSupportedTurtle :: ByteString -> Either Text (Set SupportedTriple)
parseSupportedTurtle =
    fmap Set.fromList
        . traverseStatementTriples
        . collectStatements
        . Text.lines
        . TextEncoding.decodeUtf8

traverseStatementTriples :: [Text] -> Either Text [SupportedTriple]
traverseStatementTriples stmts =
    fmap concat (traverse parseStatement stmts)

collectStatements :: [Text] -> [Text]
collectStatements = go [] []
  where
    go acc [] [] = reverse acc
    go acc buf [] = reverse (Text.unlines (reverse buf) : acc)
    go acc [] (line : rest)
        | isSkippable line = go acc [] rest
        | endsWithPeriod line = go (line : acc) [] rest
        | otherwise = go acc [line] rest
    go acc buf (line : rest)
        | endsWithPeriod line =
            go (Text.unlines (reverse (line : buf)) : acc) [] rest
        | otherwise = go acc (line : buf) rest

    isSkippable l =
        let stripped = Text.strip l
         in Text.null stripped
                || Text.isPrefixOf "#" stripped
                || Text.isPrefixOf "@" stripped

    endsWithPeriod t =
        case Text.unsnoc (Text.stripEnd t) of
            Just (_, '.') -> True
            _ -> False

parseStatement :: Text -> Either Text [SupportedTriple]
parseStatement stmt =
    case nonBlankLines stmt of
        [] -> Right []
        (firstLine : moreLines) -> do
            let strippedFirst = Text.strip firstLine
                (subject, rest) = Text.break isSpace strippedFirst
                pairLines =
                    Text.strip rest
                        : map Text.strip moreLines
            concat
                <$> traverse
                    (parseTurtlePair subject)
                    (filter (not . Text.null) pairLines)

nonBlankLines :: Text -> [Text]
nonBlankLines =
    filter (not . Text.null . Text.strip)
        . Text.lines

parseTurtlePair :: Text -> Text -> Either Text [SupportedTriple]
parseTurtlePair subject rawLine = do
    let line = dropTerminator rawLine
        (predicate, rest) = Text.break isSpace line
        objectText = Text.strip rest
    if predicate `Set.member` supportedPredicates
        then do
            objectValue <- parseTurtleObject objectText
            pure [(subject, predicate, objectValue)]
        else pure []

dropTerminator :: Text -> Text
dropTerminator =
    Text.dropWhileEnd (\c -> c == ';' || c == '.')
        . Text.strip

parseTurtleObject :: Text -> Either Text SupportedObject
parseTurtleObject t
    | Text.isPrefixOf "\"" t = ObjString <$> parseQuoted t
    | Text.isPrefixOf "_:" t = Right (ObjRef (firstToken t))
    | Text.isPrefixOf ":" t = Right (ObjRef (firstToken t))
    | Text.isPrefixOf "<" t = Right (ObjRef (takeIri t))
    | Text.any (== ':') (firstToken t) = Right (ObjRef (firstToken t))
    | otherwise = Left ("unsupported Turtle object: " <> t)

parseQuoted :: Text -> Either Text Text
parseQuoted t =
    let body = Text.drop 1 t
        (content, rest) = Text.breakOn "\"" body
     in if Text.null rest
            then Left ("unterminated string literal: " <> t)
            else Right content

takeIri :: Text -> Text
takeIri t =
    case Text.breakOn ">" t of
        (iri, rest)
            | Text.null rest -> firstToken t
            | otherwise -> iri <> ">"

firstToken :: Text -> Text
firstToken = Text.takeWhile (not . isSpace)

----------------------------------------------------------------------
-- JSON-LD subset parser for supported triples
----------------------------------------------------------------------

parseSupportedJsonLd :: Value -> Either Text (Set SupportedTriple)
parseSupportedJsonLd = \case
    Object doc -> do
        graphValue <-
            maybe
                (Left "JSON-LD document has no @graph array")
                Right
                (KeyMap.lookup (Key.fromText "@graph") doc)
        case graphValue of
            Array entries ->
                Set.fromList . concat
                    <$> traverse parseGraphEntry (Foldable.toList entries)
            _ -> Left "JSON-LD @graph is not an array"
    _ -> Left "JSON-LD document is not an object"

parseGraphEntry :: Value -> Either Text [SupportedTriple]
parseGraphEntry = \case
    Object entry -> do
        subject <- lookupString "@id" entry
        concat
            <$> traverse
                (parseJsonLdPair subject)
                (KeyMap.toList entry)
    _ -> Left "JSON-LD @graph entry is not an object"

parseJsonLdPair ::
    Text ->
    (Key.Key, Value) ->
    Either Text [SupportedTriple]
parseJsonLdPair subject (key, value)
    | name == "@id" = Right []
    | name == "@type" =
        parseJsonLdObjects rdfTypePredicate value <&> \objects ->
            [(subject, rdfTypePredicate, objectValue) | objectValue <- objects]
    | name `Set.member` supportedPredicates =
        parseJsonLdObjects name value <&> \objects ->
            [(subject, name, objectValue) | objectValue <- objects]
    | otherwise = Right []
  where
    name = Key.toText key

parseJsonLdObjects :: Text -> Value -> Either Text [SupportedObject]
parseJsonLdObjects predicate = \case
    Array values ->
        concat <$> traverse (parseJsonLdObjects predicate) (Foldable.toList values)
    Object object ->
        (: []) . ObjRef <$> lookupString "@id" object
    String t
        | predicate == rdfTypePredicate -> Right [ObjRef t]
        | otherwise -> Right [ObjString t]
    other ->
        Left $
            "unsupported JSON-LD object for "
                <> predicate
                <> ": "
                <> Text.pack (show other)

lookupString :: Text -> KeyMap.KeyMap Value -> Either Text Text
lookupString name object =
    case KeyMap.lookup (Key.fromText name) object of
        Just (String t) -> Right t
        Just other ->
            Left $
                "JSON-LD "
                    <> name
                    <> " is not a string: "
                    <> Text.pack (show other)
        Nothing -> Left ("JSON-LD object has no " <> name)

(<&>) :: (Functor f) => f a -> (a -> b) -> f b
(<&>) = flip fmap

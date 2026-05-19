{- |
Module      : Cardano.Tx.Graph.Rules.LoadImportsSpec
Description : Unit tests for the @owl:imports@ / @imports:@ DFS resolver.
License     : Apache-2.0

Covers the cross-file composition surface (spec FR-007, FR-017, US3):

* parent imports child (Turtle/Turtle, YAML/YAML);
* mixed-format imports (YAML imports Turtle, Turtle imports YAML);
* diamond imports — the shared leaf file is loaded once;
* transitive (chained) imports — entities flow from leaf to root;
* 'MissingImport' on a dangling relative reference;
* 'AbsoluteImport' on an absolute path (filesystem or @file://@ URI);
* 'HttpsImport' on an HTTPS @owl:imports@ target (default-offline,
  analyzer N4 + FR-017);
* 'RulesImportCycle' on a back-edge in the import graph (two-file
  cycle and self-import — T008).

Each test authors its file graph in a fresh temp directory using
'System.IO.Temp.withSystemTempDirectory' and exercises the public
'loadRulesFile' surface end-to-end. The DAG assertions are on the
serialized overlay byte stream (via 'BS.isInfixOf' substring checks)
rather than the @['EntityDecl']@ AST so the test catches both the
parser-level recognition of the imports surface and the resolver's
DFS flattening. The cycle assertions are on the structured 'Left'
'RulesImportCycle' payload; we wrap the loader call in a 5-second
'System.Timeout.timeout' so a regression that disables Grey-state
detection surfaces as a finite test failure (the symptom) rather
than hanging CI.
-}
module Cardano.Tx.Graph.Rules.LoadImportsSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    RulesLoadError (..),
    RulesLoadResult (..),
    RulesLoadWarning (..),
    loadRulesFile,
 )

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import System.Directory (canonicalizePath)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Rules.Load owl:imports composition (T007)" $ do
    describe "happy path" $ do
        it "Turtle imports Turtle — child entity reaches parent overlay" $ do
            withSystemTempDirectory "tx-48-imports-ttl-ttl" $ \dir -> do
                let parentPath = dir </> "parent.ttl"
                    childPath = dir </> "child.ttl"
                BS.writeFile childPath (ttlEntity "child_a" "PaymentScript" hexA)
                BS.writeFile parentPath $
                    ttlHeader
                        <> "<> owl:imports <child.ttl> .\n\n"
                        <> ttlEntityBody "parent_a" "PaymentScript" hexB
                overlay <- loadOverlay parentPath
                assertByteSubstring overlay ":child_a a cardano:Entity"
                assertByteSubstring overlay ":parent_a a cardano:Entity"

        it "YAML imports YAML — child entity reaches parent overlay" $ do
            withSystemTempDirectory "tx-48-imports-yaml-yaml" $ \dir -> do
                let parentPath = dir </> "parent.yaml"
                    childPath = dir </> "child.yaml"
                BS.writeFile childPath (yamlOne "child_a" hexA)
                BS.writeFile parentPath $
                    "imports:\n  - child.yaml\n"
                        <> yamlOne "parent_a" hexB
                overlay <- loadOverlay parentPath
                assertByteSubstring overlay ":child_a a cardano:Entity"
                assertByteSubstring overlay ":parent_a a cardano:Entity"

        it "YAML imports Turtle — mixed format" $ do
            withSystemTempDirectory "tx-48-imports-yaml-ttl" $ \dir -> do
                let parentPath = dir </> "parent.yaml"
                    childPath = dir </> "child.ttl"
                BS.writeFile childPath (ttlEntity "child_a" "PaymentScript" hexA)
                BS.writeFile parentPath $
                    "imports:\n  - child.ttl\n"
                        <> yamlOne "parent_a" hexB
                overlay <- loadOverlay parentPath
                assertByteSubstring overlay ":child_a a cardano:Entity"
                assertByteSubstring overlay ":parent_a a cardano:Entity"

        it "Turtle imports YAML — mixed format" $ do
            withSystemTempDirectory "tx-48-imports-ttl-yaml" $ \dir -> do
                let parentPath = dir </> "parent.ttl"
                    childPath = dir </> "child.yaml"
                BS.writeFile childPath (yamlOne "child_a" hexA)
                BS.writeFile parentPath $
                    ttlHeader
                        <> "<> owl:imports <child.yaml> .\n\n"
                        <> ttlEntityBody "parent_a" "PaymentScript" hexB
                overlay <- loadOverlay parentPath
                assertByteSubstring overlay ":child_a a cardano:Entity"
                assertByteSubstring overlay ":parent_a a cardano:Entity"

        it
            ( "diamond — parent imports A and B; A and B import C;"
                <> " C's entity appears in overlay exactly once"
            )
            $ do
                withSystemTempDirectory "tx-48-imports-diamond" $ \dir -> do
                    let parentPath = dir </> "parent.yaml"
                        aPath = dir </> "a.yaml"
                        bPath = dir </> "b.yaml"
                        cPath = dir </> "c.yaml"
                    BS.writeFile cPath (yamlOne "leaf_c" hexA)
                    BS.writeFile aPath $
                        "imports:\n  - c.yaml\n"
                            <> yamlOne "side_a" hexB
                    BS.writeFile bPath $
                        "imports:\n  - c.yaml\n"
                            <> yamlOne "side_b" hexC
                    BS.writeFile parentPath $
                        "imports:\n  - a.yaml\n  - b.yaml\n"
                            <> yamlOne "root_p" hexD
                    overlay <- loadOverlay parentPath
                    -- All four entities reach the overlay.
                    assertByteSubstring overlay ":leaf_c a cardano:Entity"
                    assertByteSubstring overlay ":side_a a cardano:Entity"
                    assertByteSubstring overlay ":side_b a cardano:Entity"
                    assertByteSubstring overlay ":root_p a cardano:Entity"
                    -- The shared leaf entity block appears exactly once.
                    byteOccurrences overlay ":leaf_c a cardano:Entity"
                        `shouldBe` 1

        it "transitive — parent → A → B → C; C's entity reaches parent" $ do
            withSystemTempDirectory "tx-48-imports-transitive" $ \dir -> do
                let parentPath = dir </> "parent.yaml"
                    aPath = dir </> "a.yaml"
                    bPath = dir </> "b.yaml"
                    cPath = dir </> "c.yaml"
                BS.writeFile cPath (yamlOne "deep_c" hexA)
                BS.writeFile bPath $
                    "imports:\n  - c.yaml\n"
                        <> yamlOne "mid_b" hexB
                BS.writeFile aPath $
                    "imports:\n  - b.yaml\n"
                        <> yamlOne "near_a" hexC
                BS.writeFile parentPath $
                    "imports:\n  - a.yaml\n"
                        <> yamlOne "root_p" hexD
                overlay <- loadOverlay parentPath
                assertByteSubstring overlay ":deep_c a cardano:Entity"
                assertByteSubstring overlay ":mid_b a cardano:Entity"
                assertByteSubstring overlay ":near_a a cardano:Entity"
                assertByteSubstring overlay ":root_p a cardano:Entity"

    describe "cross-file duplicate entities (T010, FR-011 / US6)" $ do
        it
            ( "DuplicateEntityAcrossFiles — two imports declare 'usdm'"
                <> " with conflicting asset policy hashes; first-wins,"
                <> " warning surfaces, second's payload is NOT merged"
            )
            $ do
                withSystemTempDirectory "tx-48-dup-cross-conflict" $ \dir -> do
                    let parentPath = dir </> "parent.yaml"
                        aPath = dir </> "a.yaml"
                        bPath = dir </> "b.yaml"
                    BS.writeFile aPath $
                        yamlAsset "usdm" policyAaa "USDM"
                    BS.writeFile bPath $
                        yamlAsset "usdm" policyBbb "USDM"
                    BS.writeFile
                        parentPath
                        "imports:\n  - a.yaml\n  - b.yaml\n"
                    aCanon <- canonicalizePath aPath
                    bCanon <- canonicalizePath bPath
                    result <- loadRulesFile parentPath
                    case result of
                        Right
                            RulesLoadResult
                                { rulesOverlayTurtle = bs
                                , rulesWarnings = ws
                                } -> do
                                ws
                                    `shouldBe` [ DuplicateEntityAcrossFiles
                                                    "usdm"
                                                    aCanon
                                                    bCanon
                                               ]
                                -- a.yaml's payload wins:
                                --   policy aaa…1a + "USDM" hex 5553444d
                                assertByteSubstring
                                    bs
                                    ":usdm a cardano:Entity"
                                assertByteSubstring
                                    bs
                                    "cardano:bytesHex \"aa11111111111111111111111111111111111111111111111111111a5553444d\""
                                -- b.yaml's payload is NOT in the overlay.
                                byteOccurrences
                                    bs
                                    "cardano:bytesHex \"bb22222222222222222222222222222222222222222222222222222b5553444d\""
                                    `shouldBe` 0
                                -- Exactly one :usdm block.
                                byteOccurrences
                                    bs
                                    ":usdm a cardano:Entity"
                                    `shouldBe` 1
                        other ->
                            expectationFailure $
                                "expected Right with one warning, got: "
                                    <> show other

        it
            ( "DuplicateEntityAcrossFiles — identical-payload dup still"
                <> " warns (per FR-011: loader names the duplication,"
                <> " does not infer additive intent)"
            )
            $ do
                withSystemTempDirectory "tx-48-dup-cross-identical" $ \dir -> do
                    let parentPath = dir </> "parent.yaml"
                        aPath = dir </> "a.yaml"
                        bPath = dir </> "b.yaml"
                    BS.writeFile aPath $
                        yamlAsset "usdm" policyAaa "USDM"
                    BS.writeFile bPath $
                        yamlAsset "usdm" policyAaa "USDM"
                    BS.writeFile
                        parentPath
                        "imports:\n  - a.yaml\n  - b.yaml\n"
                    aCanon <- canonicalizePath aPath
                    bCanon <- canonicalizePath bPath
                    result <- loadRulesFile parentPath
                    case result of
                        Right
                            RulesLoadResult
                                { rulesOverlayTurtle = bs
                                , rulesWarnings = ws
                                } -> do
                                ws
                                    `shouldBe` [ DuplicateEntityAcrossFiles
                                                    "usdm"
                                                    aCanon
                                                    bCanon
                                               ]
                                byteOccurrences
                                    bs
                                    ":usdm a cardano:Entity"
                                    `shouldBe` 1
                        other ->
                            expectationFailure $
                                "expected Right with one warning, got: "
                                    <> show other

    describe "structured errors" $ do
        it "MissingImport — parent imports a non-existent file" $ do
            withSystemTempDirectory "tx-48-imports-missing" $ \dir -> do
                let parentPath = dir </> "parent.yaml"
                    missingPath = dir </> "absent.yaml"
                BS.writeFile parentPath $
                    "imports:\n  - absent.yaml\n"
                        <> yamlOne "parent_a" hexA
                result <- loadRulesFile parentPath
                case result of
                    Left (MissingImport importer imported) -> do
                        importer `shouldBe` parentPath
                        imported `shouldBe` missingPath
                    other ->
                        expectationFailure $
                            "expected MissingImport, got: " <> show other

        it "AbsoluteImport — YAML imports an absolute filesystem path" $ do
            withSystemTempDirectory "tx-48-imports-abs-yaml" $ \dir -> do
                let parentPath = dir </> "parent.yaml"
                BS.writeFile parentPath $
                    "imports:\n  - /abs/foo.yaml\n"
                        <> yamlOne "parent_a" hexA
                result <- loadRulesFile parentPath
                case result of
                    Left (AbsoluteImport importer imported) -> do
                        importer `shouldBe` parentPath
                        imported `shouldBe` "/abs/foo.yaml"
                    other ->
                        expectationFailure $
                            "expected AbsoluteImport, got: " <> show other

        it "AbsoluteImport — Turtle imports a file:/// URI" $ do
            withSystemTempDirectory "tx-48-imports-abs-ttl" $ \dir -> do
                let parentPath = dir </> "parent.ttl"
                BS.writeFile parentPath $
                    ttlHeader
                        <> "<> owl:imports <file:///abs.ttl> .\n\n"
                        <> ttlEntityBody "parent_a" "PaymentScript" hexA
                result <- loadRulesFile parentPath
                case result of
                    Left (AbsoluteImport importer imported) -> do
                        importer `shouldBe` parentPath
                        imported `shouldBe` "file:///abs.ttl"
                    other ->
                        expectationFailure $
                            "expected AbsoluteImport, got: " <> show other

        it
            ( "HttpsImport — Turtle's owl:imports <https://...>"
                <> " is rejected (default-offline, FR-017)"
            )
            $ do
                withSystemTempDirectory "tx-48-imports-https" $ \dir -> do
                    let parentPath = dir </> "parent.ttl"
                    BS.writeFile parentPath $
                        ttlHeader
                            <> "<> owl:imports <https://example.org/x.ttl> .\n\n"
                            <> ttlEntityBody "parent_a" "PaymentScript" hexA
                    result <- loadRulesFile parentPath
                    case result of
                        Left (HttpsImport importer imported) -> do
                            importer `shouldBe` parentPath
                            imported `shouldBe` "https://example.org/x.ttl"
                        other ->
                            expectationFailure $
                                "expected HttpsImport, got: " <> show other

    describe "cycle detection (T008)" $ do
        it
            ( "RulesImportCycle — two-file cycle a.yaml ↔ b.yaml"
                <> " surfaces [a, b, a]"
            )
            $ do
                withSystemTempDirectory "tx-48-imports-cycle-pair" $ \dir -> do
                    let aPath = dir </> "a.yaml"
                        bPath = dir </> "b.yaml"
                    BS.writeFile aPath $
                        "imports:\n  - b.yaml\n" <> yamlOne "a_ent" hexA
                    BS.writeFile bPath $
                        "imports:\n  - a.yaml\n" <> yamlOne "b_ent" hexB
                    -- Cycle keys are canonical paths — resolve before
                    -- comparing so the assertion is robust against
                    -- /tmp ↔ /private/tmp on macOS or any future
                    -- canonicalization shift on Linux.
                    aCanon <- canonicalizePath aPath
                    bCanon <- canonicalizePath bPath
                    mResult <- timeout cycleTimeoutMicros $ loadRulesFile aPath
                    case mResult of
                        Nothing ->
                            expectationFailure $
                                "loader did not return within "
                                    <> show cycleTimeoutMicros
                                    <> "µs — Grey-state cycle detection"
                                    <> " regression: DFS hung through readFile"
                        Just (Left (RulesImportCycle cyc)) ->
                            cyc `shouldBe` [aCanon, bCanon, aCanon]
                        Just other ->
                            expectationFailure $
                                "expected RulesImportCycle, got: " <> show other

        it "RulesImportCycle — self-import a.yaml → a.yaml surfaces [a, a]" $ do
            withSystemTempDirectory "tx-48-imports-cycle-self" $ \dir -> do
                let aPath = dir </> "a.yaml"
                BS.writeFile aPath $
                    "imports:\n  - a.yaml\n" <> yamlOne "a_ent" hexA
                aCanon <- canonicalizePath aPath
                mResult <- timeout cycleTimeoutMicros $ loadRulesFile aPath
                case mResult of
                    Nothing ->
                        expectationFailure $
                            "loader did not return within "
                                <> show cycleTimeoutMicros
                                <> "µs — Grey-state cycle detection"
                                <> " regression: DFS hung through readFile"
                    Just (Left (RulesImportCycle cyc)) ->
                        cyc `shouldBe` [aCanon, aCanon]
                    Just other ->
                        expectationFailure $
                            "expected RulesImportCycle, got: " <> show other

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{- | The microsecond cap for the cycle-detection tests. Five seconds
is generous on any CI runner the project supports; it exists to
turn a regression that re-enables unbounded recursion into a finite
test failure rather than a CI hang.
-}
cycleTimeoutMicros :: Int
cycleTimeoutMicros = 5_000_000

{- | Drive 'loadRulesFile' over an absolute file path, returning the
emitted overlay bytes or failing the spec on Left.
-}
loadOverlay :: FilePath -> IO ByteString
loadOverlay path = do
    result <- loadRulesFile path
    case result of
        Right RulesLoadResult{rulesOverlayTurtle = bs} -> pure bs
        Left err ->
            fail $
                "loadOverlay: loadRulesFile " <> path <> " failed: " <> show err

{- | The canonical Turtle prefix preamble used by every Turtle fixture in
this spec. Matches the byte shape the YAML/Turtle parsers expect.
-}
ttlHeader :: ByteString
ttlHeader =
    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
    \@prefix owl:     <http://www.w3.org/2002/07/owl#> .\n\
    \@prefix :        <https://example.com/x#> .\n\
    \\n"

-- | A complete Turtle blob with header + one entity block.
ttlEntity :: ByteString -> ByteString -> ByteString -> ByteString
ttlEntity slug leafType hex = ttlHeader <> ttlEntityBody slug leafType hex

{- | Just the entity + identifier blocks for a single Turtle entity,
without the prefix header — composed onto an existing @ttlHeader@
when the parent file also carries an @owl:imports@ triple.
-}
ttlEntityBody :: ByteString -> ByteString -> ByteString -> ByteString
ttlEntityBody slug leafType hex =
    ":"
        <> slug
        <> " a cardano:Entity ;\n  rdfs:label \""
        <> slug
        <> "\" ;\n  cardano:hasIdentifier _:"
        <> slug
        <> "_id .\n\n_:"
        <> slug
        <> "_id a cardano:Identifier ;\n  cardano:leafType \""
        <> leafType
        <> "\" ;\n  cardano:bytesHex \""
        <> hex
        <> "\" .\n"

-- | A complete YAML blob declaring one PaymentScript entity.
yamlOne :: ByteString -> ByteString -> ByteString
yamlOne slug hex =
    "entities:\n  - name: "
        <> slug
        <> "\n    script: "
        <> hex
        <> "\n"

{- | Four distinct 28-byte hex blobs the tests author into entity files.
Each starts with an alphabetic nibble so YAML decodes the value as a
string, not as a number.
-}
hexA, hexB, hexC, hexD :: ByteString
hexA = "aa11111111111111111111111111111111111111111111111111111a"
hexB = "bb22222222222222222222222222222222222222222222222222222b"
hexC = "cc33333333333333333333333333333333333333333333333333333c"
hexD = "dd44444444444444444444444444444444444444444444444444444d"

{- | Two distinct 28-byte hex policy IDs used by the cross-file
duplicate-entity tests (T010). Their suffix differs so the bytesHex
substring assertions can distinguish a.yaml's payload from b.yaml's.
-}
policyAaa, policyBbb :: ByteString
policyAaa = "aa11111111111111111111111111111111111111111111111111111a"
policyBbb = "bb22222222222222222222222222222222222222222222222222222b"

{- | A complete YAML blob declaring one asset-shape entity with a given
slug, policy hex, and asset name. Used by the cross-file duplicate-
entity tests so the per-file payload differs by policy hash while
the entity slug collides.
-}
yamlAsset :: ByteString -> ByteString -> ByteString -> ByteString
yamlAsset slug policy assetName =
    "entities:\n  - name: "
        <> slug
        <> "\n    asset: { policy: "
        <> policy
        <> ", name: "
        <> assetName
        <> " }\n"

-- | Assert that @needle@ appears at least once inside @haystack@.
assertByteSubstring :: ByteString -> ByteString -> IO ()
assertByteSubstring haystack needle =
    if needle `BS.isInfixOf` haystack
        then pure ()
        else
            expectationFailure $
                "expected substring not found in overlay bytes: "
                    <> show needle

-- | Count occurrences of @needle@ inside @haystack@.
byteOccurrences :: ByteString -> ByteString -> Int
byteOccurrences haystack needle
    | BS.null needle = 0
    | otherwise = go 0 haystack
  where
    go n hs = case BS.breakSubstring needle hs of
        (_, rest)
            | BS.null rest -> n
            | otherwise -> go (n + 1) (BS.drop (BS.length needle) rest)

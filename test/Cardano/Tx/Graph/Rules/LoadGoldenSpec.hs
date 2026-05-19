{- |
Module      : Cardano.Tx.Graph.Rules.LoadGoldenSpec
Description : Byte-diff goldens for the entity overlay (T003 + T004 + T005).
License     : Apache-2.0

Drives the rules-loader against each of the 11 @rewrite-redesign@
fixtures' @rules.yaml@ files and byte-compares the produced overlay
bytes against the corresponding @expected.entities.ttl@ carve-out.

T003 activates the seven basic-shape fixtures (02, 03, 05, 06, 07,
08, 10) and leaves the four complex-shape fixtures (01, 04, 09, 11)
@pending@ — those land in T004 (keys+bytes compound) and T005
(shared identity / blueprints / collapse).

The carve-outs are authored by capturing the loader's stdout, not by
hand — see the T003 task description for the three-step ritual.
-}
module Cardano.Tx.Graph.Rules.LoadGoldenSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    RulesLoadResult (..),
    loadRulesFile,
 )

import Control.Exception (try)
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import System.FilePath ((</>))
import Test.Hspec (Spec, describe, expectationFailure, it, pending)

----------------------------------------------------------------------
-- Fixture registry
----------------------------------------------------------------------

{- | All 11 rewrite-redesign fixtures with the slice that activates
each fixture's byte-diff. T003 activates 02, 03, 05, 06, 07, 08, 10;
T004 activates 04; T005 activates 01, 09, 11.
-}
data FixtureStatus = Active | Pending !String
    deriving stock (Eq, Show)

fixtures :: [(String, FixtureStatus)]
fixtures =
    [ ("01-amaru-treasury-swap", Pending "T005 — shared identity + blueprints")
    , ("02-alice-bob-ada", Active)
    , ("03-multi-asset-transfer", Active)
    , ("04-mint-spend-script-overlap", Pending "T004 — keys+bytes compound entity")
    , ("05-withdrawal-script-stake", Active)
    , ("06-stake-pool-delegation", Active)
    , ("07-vote-delegation", Active)
    , ("08-contingency-disburse", Active)
    , ("09-mpfs-facts-request", Pending "T005 — shared identity + collapse")
    , ("10-governance-treasury-withdrawal", Active)
    , ("11-amaru-treasury-swap-real", Pending "T005 — shared identity (real)")
    ]

fixturesRoot :: FilePath
fixturesRoot = "test/fixtures/rewrite-redesign"

----------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Rules.Load entity-overlay goldens (T003)" $
        mapM_ describeFixture fixtures

describeFixture :: (String, FixtureStatus) -> Spec
describeFixture (slug, status) =
    it (slug <> " — entity overlay bytes match expected.entities.ttl") $
        case status of
            Pending _reason -> pending
            Active -> runActiveGolden slug

{- | Load the fixture's @rules.yaml@, compare the emitted overlay
bytes to the @expected.entities.ttl@ carve-out, and fail the test
verbosely on mismatch. A missing @expected.entities.ttl@ file
(common during the RED phase before the carve-outs land) is
distinguished from a byte mismatch.
-}
runActiveGolden :: String -> IO ()
runActiveGolden slug = do
    let rulesPath = fixturesRoot </> slug </> "rules.yaml"
        expectedPath = fixturesRoot </> slug </> "expected.entities.ttl"
    loadResult <- loadRulesFile rulesPath
    case loadResult of
        Left err ->
            expectationFailure $
                "loadRulesFile " <> rulesPath <> " failed: " <> show err
        Right RulesLoadResult{rulesOverlayTurtle = actual} -> do
            mExpected <- safeReadFile expectedPath
            case mExpected of
                Nothing ->
                    expectationFailure $
                        "carve-out missing: " <> expectedPath
                Just expected ->
                    unless (actual == expected) $
                        expectationFailure $
                            unlines
                                [ "overlay bytes do not match " <> expectedPath
                                , "--- expected (first 400 bytes):"
                                , take 400 (showBytes expected)
                                , "--- actual (first 400 bytes):"
                                , take 400 (showBytes actual)
                                ]

safeReadFile :: FilePath -> IO (Maybe ByteString)
safeReadFile p = do
    eContents <- try (BS.readFile p) :: IO (Either IOError ByteString)
    pure $ case eContents of
        Right bs -> Just bs
        Left _ -> Nothing

showBytes :: ByteString -> String
showBytes = map (toEnum . fromEnum) . BS.unpack

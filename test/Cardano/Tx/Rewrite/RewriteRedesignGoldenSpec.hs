{- |
Module      : Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec
Description : Goldens suite scaffolding for harness #45 / specs/033-rewrite-redesign-harness.
License     : Apache-2.0

Empty fixture registry in this slice. Subsequent slices (S5..S14
per-fixture) populate the suite. The B-side @expected.ttl@ files
(S15..S24) land post-kmaps#53 Phase A signal.

See @specs/033-rewrite-redesign-harness/contracts/goldens-suite.md@ for the
behavioural contract.

The foundational @blueprints@ block (this slice, S3) sits at the top of
'spec', outside the per-fixture iteration. It asserts that the two CIP-57
blueprint files under @test\/fixtures\/rewrite-redesign\/blueprints\/@
exist on disk and parse as JSON.

The inner @helpers@ block carries one structural Hspec item exercising
'mkTx', 'defTxBuilder', 'baseShape', and 'assertShape' end-to-end against
a synthetic 'StoryId' @"smoke"@ 'FixturePaths'. The per-fixture iteration
block lands later, populated from a @fixtureRegistry@ list that this slice
intentionally leaves empty.
-}
module Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec (spec) where

import Data.Aeson (Value, eitherDecodeFileStrict)
import Data.Either (isRight)
import Test.Hspec (Spec, describe, it, shouldSatisfy)

import Fixtures.RewriteRedesign.Helpers (
    StoryId (..),
    assertShape,
    baseShape,
    defTxBuilder,
    mkFixturePaths,
    mkTx,
 )

spec :: Spec
spec = do
    blueprintsDescribe
    describe "RewriteRedesignGoldens" $ do
        describe "helpers" $ do
            it "mkTx defTxBuilder satisfies baseShape" $
                assertShape
                    (mkTx defTxBuilder)
                    baseShape
                    (mkFixturePaths (StoryId "smoke"))

{- | Foundational on-disk presence + JSON-parse checks for the two CIP-57
blueprint files. Lives at the top of 'spec', outside the per-fixture
iteration. See
@specs\/033-rewrite-redesign-harness\/contracts\/goldens-suite.md@,
section /Foundational block — "blueprints"/.
-}
blueprintsDescribe :: Spec
blueprintsDescribe = describe "blueprints" $ do
    it "swap-v2-datum.cip57.json exists and parses as JSON" $
        loadAndParseJson
            "test/fixtures/rewrite-redesign/blueprints/swap-v2-datum.cip57.json"
    it "mpfs-fact.cip57.json exists and parses as JSON" $
        loadAndParseJson
            "test/fixtures/rewrite-redesign/blueprints/mpfs-fact.cip57.json"

{- | Read @path@ from disk and decode it as a generic Aeson 'Value', then
assert the decode succeeded. Surfaces both file-absence (an Aeson
'IOException') and malformed JSON ('Left' from 'eitherDecodeFileStrict')
as Hspec assertion failures.
-}
loadAndParseJson :: FilePath -> IO ()
loadAndParseJson path = do
    result <- eitherDecodeFileStrict path :: IO (Either String Value)
    result `shouldSatisfy` isRight

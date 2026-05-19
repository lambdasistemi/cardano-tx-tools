{- |
Module      : Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec
Description : Goldens suite for harness #45 / specs/033-rewrite-redesign-harness.
License     : Apache-2.0

The suite has three layers:

* A foundational @blueprints@ block at the top of 'spec' (outside the
  per-fixture iteration) that asserts the two CIP-57 blueprint files under
  @test\/fixtures\/rewrite-redesign\/blueprints\/@ exist and parse as JSON.
* An inner @helpers@ smoke block that exercises 'mkTx', 'defTxBuilder',
  'baseShape', and 'assertShape' against a synthetic 'StoryId' @"smoke"@
  'FixturePaths' (no on-disk data files).
* A per-fixture iteration that walks 'fixtureRegistry' and produces three
  Hspec items per entry: one active structural check ('assertShape') plus
  two 'pendingWith' placeholders for the future Turtle (#47) and SPARQL
  (#51) byte-equivalence checks.

See @specs/033-rewrite-redesign-harness/contracts/goldens-suite.md@ for
the behavioural contract; the registry layout (kebab data dirs + camel-case
module names linked by 'StoryId') is documented in
@specs/033-rewrite-redesign-harness/data-model.md@.
-}
module Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (Value, eitherDecodeFileStrict)
import Data.Either (isRight)
import Data.Text qualified as Text
import Test.Hspec (Spec, describe, it, pendingWith, shouldSatisfy)

import Fixtures.RewriteRedesign.Helpers (
    FixtureEntry (..),
    StoryId (..),
    assertShape,
    baseShape,
    defTxBuilder,
    mkFixturePaths,
    mkTx,
 )
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
        forM_ fixtureRegistry $ \fe ->
            describe (Text.unpack (unStoryId (feStoryId fe))) $ do
                it "produces a ConwayTx of expected shape" $
                    assertShape (feBuilder fe) (feShape fe) (fePaths fe)
                it "Turtle byte-equivalence with the future emitter (#47)" $
                    pendingWith "awaits #47 emitter MVP"
                it "Text byte-equivalence via cli-tree SPARQL view (#51)" $
                    pendingWith "awaits #51 cli-tree SPARQL view"

{- | The fixture registry — one entry per 044 user story whose A-side has
landed. Registry order mirrors the 044 story numbers so the Hspec output
is predictable (per @contracts/goldens-suite.md@, Invariants).
-}
fixtureRegistry :: [FixtureEntry]
fixtureRegistry =
    [ FixtureEntry
        { feStoryId = S01.storyId
        , feBuilder = S01.tx
        , fePaths = mkFixturePaths S01.storyId
        , feShape = S01.shape
        }
    , FixtureEntry
        { feStoryId = S02.storyId
        , feBuilder = S02.tx
        , fePaths = mkFixturePaths S02.storyId
        , feShape = S02.shape
        }
    , FixtureEntry
        { feStoryId = S03.storyId
        , feBuilder = S03.tx
        , fePaths = mkFixturePaths S03.storyId
        , feShape = S03.shape
        }
    , FixtureEntry
        { feStoryId = S04.storyId
        , feBuilder = S04.tx
        , fePaths = mkFixturePaths S04.storyId
        , feShape = S04.shape
        }
    , FixtureEntry
        { feStoryId = S05.storyId
        , feBuilder = S05.tx
        , fePaths = mkFixturePaths S05.storyId
        , feShape = S05.shape
        }
    , FixtureEntry
        { feStoryId = S06.storyId
        , feBuilder = S06.tx
        , fePaths = mkFixturePaths S06.storyId
        , feShape = S06.shape
        }
    , FixtureEntry
        { feStoryId = S07.storyId
        , feBuilder = S07.tx
        , fePaths = mkFixturePaths S07.storyId
        , feShape = S07.shape
        }
    , FixtureEntry
        { feStoryId = S08.storyId
        , feBuilder = S08.tx
        , fePaths = mkFixturePaths S08.storyId
        , feShape = S08.shape
        }
    , FixtureEntry
        { feStoryId = S09.storyId
        , feBuilder = S09.tx
        , fePaths = mkFixturePaths S09.storyId
        , feShape = S09.shape
        }
    , FixtureEntry
        { feStoryId = S10.storyId
        , feBuilder = S10.tx
        , fePaths = mkFixturePaths S10.storyId
        , feShape = S10.shape
        }
    , FixtureEntry
        { feStoryId = S11.storyId
        , feBuilder = S11.tx
        , fePaths = mkFixturePaths S11.storyId
        , feShape = S11.shape
        }
    ]

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

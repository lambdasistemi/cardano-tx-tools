{- |
Module      : Cardano.Tx.Graph.Emit.InputSemanticSpec
Description : Input semantic-content invariants for the body emitter (T103/S2).
License     : Apache-2.0

T103 / slice S2 introduces the per-input semantic content the
#58 stub-shape omitted: every @cardano:Input@ subject block
carries @cardano:fromTxOutRef "\<txid\>#\<ix\>"@ as its first
non-@rdf:type@ predicate, and the empty-leaf probe is relaxed
so reference inputs decode and bind to @_:tx@ via
@cardano:hasReferenceInput@.

This spec asserts two things directly on the emitter output —
no Turtle parsing, no byte-diff comparison:

1. For every fixture, every subject block whose bnode name
   starts with @input@ / @collateral@ / @refInput@ carries a
   @PIri "cardano:fromTxOutRef"@ predicate.
2. Fixture 11 ('S11.tx', the on-chain-shape mirror), which
   carries non-empty @referenceInputs@ post-T103, emits to
   @Right _@ — proving the @ConwayReferenceInputValue@
    unsupported-leaf failure is gone.

The byte-equality property is owned by
'Cardano.Tx.Graph.EmitGoldenSpec'; this spec guards the
semantic invariant locally so future refactors that
re-shape the byte layout still cannot drop the
@fromTxOutRef@ content or re-introduce the reference-input
fail-loudly arm.
-}
module Cardano.Tx.Graph.Emit.InputSemanticSpec (spec) where

import Data.Either (isRight)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text

import Cardano.Tx.Graph.Emit (
    BnodeName (..),
    BodySection (..),
    EmittedGraph (..),
    Predicate (..),
    Subject (..),
    SubjectBlock (..),
    emit,
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

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit input semantic content (T103/S2)" $ do
    describe "every input/collateral/refInput block carries cardano:fromTxOutRef" $
        mapM_ assertFromTxOutRef allFixtures
    describe "fixture 11 emits successfully (no PUnsupportedLeafType ConwayReferenceInputValue)" $ do
        it "11-amaru-treasury-swap-real emits to Right _" $
            isRight (emit S11.tx Map.empty []) `shouldBe` True

-- | All fixtures the body emitter currently covers.
allFixtures :: [(String, ConwayTx)]
allFixtures =
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

{- | Per-fixture assertion: every @cardano:Input@ subject block
(spending input @_:inputK@, collateral @_:collateralK@,
reference input @_:refInputK@) emitted for this fixture must
carry a @cardano:fromTxOutRef@ predicate.
-}
assertFromTxOutRef :: (String, ConwayTx) -> Spec
assertFromTxOutRef (slug, tx) =
    it (slug <> " — every input/collateral/refInput block has fromTxOutRef") $
        case emit tx Map.empty [] of
            Left err ->
                expectationFailure $
                    "emit returned Left " <> show err
            Right g ->
                let inputBlocks =
                        [ block
                        | section <- graphBody g
                        , block <- sectionBlocks section
                        , isInputSubject (subjectBlockSubject block)
                        ]
                    missing =
                        [ block
                        | block <- inputBlocks
                        , not (hasFromTxOutRef block)
                        ]
                 in case missing of
                        [] -> pure ()
                        _ ->
                            expectationFailure $
                                "input blocks missing cardano:fromTxOutRef: "
                                    <> show missing

{- | A subject is an "input" position in the
T103-defined sense when its bnode name starts with
@input@, @collateral@, or @refInput@. The numeric suffix
(@input1@, @collateral1@, @refInput1@, …) distinguishes
ordinal positions and is not part of the prefix match.
-}
isInputSubject :: Subject -> Bool
isInputSubject = \case
    SBnode (BnodeName name) ->
        any
            (`Text.isPrefixOf` name)
            ["input", "collateral", "refInput"]
            && not ("resolvedInput" `Text.isPrefixOf` name)
            && not ("resolvedCollateral" `Text.isPrefixOf` name)
    _ -> False

-- | Whether a subject block contains @cardano:fromTxOutRef@.
hasFromTxOutRef :: SubjectBlock -> Bool
hasFromTxOutRef SubjectBlock{subjectBlockPredicates} =
    any (\(p, _) -> p == fromTxOutRefPredicate) subjectBlockPredicates

-- | The @cardano:fromTxOutRef@ predicate, spelled as a CURIE.
fromTxOutRefPredicate :: Predicate
fromTxOutRefPredicate = PIri (Text.pack "cardano:fromTxOutRef")

{- |
Module      : Cardano.Tx.Graph.Emit.ReproducibilitySpec
Description : Per-fixture byte-determinism check on the emitter (T012).
License     : Apache-2.0

Per-fixture byte-equality check across two independent runs of
'Cardano.Tx.Graph.Emit.emit' + 'Cardano.Tx.Graph.Emit.serialize'
on the same @(ConwayTx, ResolvedUTxO, [EntityDecl])@ tuple. Both
runs must produce identical Turtle bytes.

Acceptance contract (spec FR-006 + SC-004): the emitter is a pure
function of its inputs, so two invocations with the same input
must yield the same output bytes. A divergence indicates a
non-determinism source has crept into the pipeline — common
suspects are 'Data.HashMap' / 'Data.HashSet' (randomized hash
seeds), accidental 'System.IO.Unsafe.unsafePerformIO', or
filesystem-ordered traversal leaking into a pure path.

The spec exercises all 11 fixtures GREEN in
'Cardano.Tx.Graph.EmitGoldenSpec' at the close of T010 — the same
roster used by 'Cardano.Tx.Graph.Emit.JsonLdEquivalenceSpec'. The
two evaluations of @emitOnce@ are written as independent let
bindings so that GHC (under @-O0@, per the project Haskell rule)
keeps them distinct rather than sharing via CSE.
-}
module Cardano.Tx.Graph.Emit.ReproducibilitySpec (spec) where

import Data.ByteString (ByteString)
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Cardano.Tx.Graph.Emit (
    EmitError,
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

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
 )

----------------------------------------------------------------------
-- Fixture roster (mirrors EmitGoldenSpec / JsonLdEquivalenceSpec)
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
    describe "Cardano.Tx.Graph.Emit reproducibility (T012)" $
        mapM_ fixtureSpec enabledFixtures

fixtureSpec :: (String, ConwayTx) -> Spec
fixtureSpec (slug, tx) = describe slug $ do
    let dir = "test/fixtures/rewrite-redesign" </> slug
        rulesPath = dir </> "rules.yaml"
    (entities, overlay) <- runIO (loadEntitiesAndOverlay rulesPath)
    it "emit + serialize Turtle is byte-deterministic across two runs" $ do
        let r1 = emitOnce slug tx emptyUtxo entities overlay
            r2 = emitOnce slug tx emptyUtxo entities overlay
        case (r1, r2) of
            (Right b1, Right b2) -> b1 `shouldBe` b2
            (Left err, _) ->
                expectationFailure $
                    "ReproducibilitySpec: "
                        <> slug
                        <> ": first emit returned Left "
                        <> show err
            (_, Left err) ->
                expectationFailure $
                    "ReproducibilitySpec: "
                        <> slug
                        <> ": second emit returned Left "
                        <> show err

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{- | One @emit@ + @serialize Turtle@ pass. Two call sites in
'fixtureSpec' invoke this independently so that the two byte
strings being compared come from two distinct evaluations.
-}
emitOnce ::
    FilePath ->
    ConwayTx ->
    ResolvedUTxO ->
    [EntityDecl] ->
    ByteString ->
    Either EmitError ByteString
emitOnce slug tx utxo entities overlay =
    case emit tx utxo entities of
        Left err -> Left err
        Right g ->
            Right
                ( serialize
                    Turtle
                    slug
                    g{graphOverlayTurtle = overlay}
                )

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
                "ReproducibilitySpec.loadEntitiesAndOverlay: "
                    <> path
                    <> ": "
                    <> show err

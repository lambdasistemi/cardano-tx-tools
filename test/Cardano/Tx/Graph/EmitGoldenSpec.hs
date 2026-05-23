{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.Tx.Graph.EmitGoldenSpec
Description : Byte-diff golden spec for the joint Turtle output (T005).
License     : Apache-2.0

Per-fixture byte-equality check: the Turtle bytes 'emit' produces
for a fixture's @(ConwayTx, ResolvedUTxO, [EntityDecl])@ tuple
must equal the committed @expected.ttl@.

T005 enabled fixture 02; T006-T010 grew coverage one slice at a
time; T010 closes the final three (01 collateral + multi-input,
10 TreasuryWithdrawal proposal, 11 collateral on the real-shape
mirror). All 11 fixtures are GREEN at end of T010 — SC-001 closed.

== Regen mode

When the environment variable @EMIT_GOLDEN_REGEN=1@ is set, each
@it@ overwrites the on-disk @expected.ttl@ with the freshly
emitted bytes (and reports success without a byte-diff). This is
the regen path the slice-by-slice walk uses to update the
fixtures when the emitter shape changes (T103 / S2 onwards). The
default (env var unset) is the byte-diff golden assertion.
-}
module Cardano.Tx.Graph.EmitGoldenSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import System.Environment (lookupEnv)
import System.FilePath ((</>))

import Cardano.Ledger.Hashes (ScriptHash)

import Cardano.Tx.Blueprint (Blueprint)
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
    rulesBlueprints,
    rulesEntities,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.Helpers (stubTxIn, stubTxOutMA)
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
import Fixtures.RewriteRedesign.S12BlueprintTyped qualified as S12
import Fixtures.RewriteRedesign.S13BlueprintPassthrough qualified as S13
import Fixtures.RewriteRedesign.S14BlueprintDecodeFail qualified as S14
import Fixtures.RewriteRedesign.S15_AmaruDisburseNetworkCompliance qualified as S15
import Fixtures.RewriteRedesign.S17_AmaruDisburseContingency qualified as S17

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit joint Turtle goldens (T005)" $ do
    regen <- runIO regenEnabled
    mapM_ (fixtureGoldenItem regen) allFixtures

{- | List of every fixture covered by the byte-diff golden suite.
The slug is the directory name under
@test/fixtures/rewrite-redesign/@; the @ConwayTx@ comes from the
per-fixture @Sxx@ module. Adding a fixture is a one-line append.
-}
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
    , ("12-blueprint-typed", S12.tx)
    , ("13-blueprint-passthrough", S13.tx)
    , ("14-blueprint-decode-fail", S14.tx)
    , ("15-amaru-disburse-network-compliance", S15.tx)
    , ("17-amaru-disburse-contingency", S17.tx)
    ]

{- | One Hspec @it@ per fixture: byte-diff the emitted Turtle
against the committed @expected.ttl@, or overwrite the on-disk
file when 'regen' is @True@. The rules YAML + overlay bytes
are loaded once at @runIO@ time so the loader cost is paid
before the test body runs.
-}
fixtureGoldenItem :: Bool -> (String, ConwayTx) -> Spec
fixtureGoldenItem regen (slug, tx) = do
    let dir = "test/fixtures/rewrite-redesign" </> slug
        rulesPath = dir </> "rules.yaml"
        expectedPath = dir </> "expected.ttl"
    (entities, overlay, blueprints) <-
        runIO (loadEntitiesAndOverlay rulesPath)
    expected <- runIO (BS.readFile expectedPath)
    it (slug <> " — emit + serialize matches expected.ttl") $ do
        case emit tx (fixtureUtxo slug) entities blueprints of
            Left err ->
                expectationFailure $
                    "emit returned Left " <> show err
            Right g ->
                let joint = g{graphOverlayTurtle = overlay}
                    actual = serialize Turtle slug joint
                 in if regen
                        then BS.writeFile expectedPath actual
                        else
                            if actual == expected
                                then pure ()
                                else
                                    expectationFailure $
                                        "byte-diff: emit("
                                            <> slug
                                            <> ") /= "
                                            <> expectedPath
                                            <> " (lengths "
                                            <> show (BS.length actual)
                                            <> " vs "
                                            <> show (BS.length expected)
                                            <> ")"

-- | @True@ when @EMIT_GOLDEN_REGEN=1@ is in the environment.
regenEnabled :: IO Bool
regenEnabled = do
    mv <- lookupEnv "EMIT_GOLDEN_REGEN"
    pure (mv == Just "1")

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

{- | Per-fixture resolved-UTxO. Almost every fixture passes an empty
map (its inputs are not resolved against any operator-supplied
UTxO context). Fixture @11-amaru-treasury-swap-real@ ships a
single resolved entry so the T103 + T104 resolved-input value
emission path (the @_:resolvedInputK@ block carrying
@cardano:lovelace@ + the multi-asset RDF list) is exercised in
the golden bytes — keeps the slice's live-boundary diagnostic
honest per A-002-fixture-multi-asset-coverage.

The resolved entry maps @stubTxIn 2@ (the treasury input) onto
a multi-asset 'TxOut' carrying ADA + USDM under the same
@usdm-control@ policy fixtures 03 + 04 use. The USDM identifier
appears as a raw-bytes bnode here (fixture 11's @rules.yaml@
does not declare a USDM entity).
-}
fixtureUtxo :: String -> ResolvedUTxO
fixtureUtxo = \case
    "11-amaru-treasury-swap-real" ->
        Map.singleton
            (stubTxIn 2)
            ( stubTxOutMA
                1_137_000_000_000
                [(S11.swapUsdmPolicy, S11.swapUsdmName, 2_500_000_000)]
            )
    "15-amaru-disburse-network-compliance" ->
        Map.fromList
            [(txIn, S15.treasuryUtxoEntry) | txIn <- S15.treasuryInputs]
    "17-amaru-disburse-contingency" ->
        Map.singleton S17.treasuryInput S17.treasuryUtxoEntry
    _ -> emptyUtxo

loadEntitiesAndOverlay ::
    FilePath -> IO ([EntityDecl], ByteString, [(ScriptHash, Blueprint, Text)])
loadEntitiesAndOverlay path = do
    result <- loadRulesFile path
    case result of
        Right res@RulesLoadResult{rulesOverlayTurtle} ->
            pure
                ( rulesEntities res
                , rulesOverlayTurtle
                , rulesBlueprints res
                )
        Left err ->
            fail $
                "EmitGoldenSpec.loadEntitiesAndOverlay: "
                    <> path
                    <> ": "
                    <> show err

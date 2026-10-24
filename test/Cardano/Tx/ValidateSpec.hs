{- |
Module      : Cardano.Tx.ValidateSpec
Description : Acceptance coverage for the Phase-1 pre-flight validator.
License     : Apache-2.0

Exercises 'validatePhase1' against the committed @swap-cancel@
issue-#8 fixture. The on-disk @body.cbor.hex@ is the **pre-fix**
body — its @script_integrity_hash@ carries the buggy value
mainnet rejected. The first slice derives the **post-fix** body
at test time by overwriting that field with the value PR #9's
fix now emits, runs the validator, and asserts the carried
@ConwayLedgerPredFailure@ list contains only
witness-completeness noise — no structural failures (spec
acceptance scenarios 1 and 3, success criterion SC-001).

Subsequent slices add the pre-fix integrity-hash assertion
(SC-002), zero-fee mutation (FR-007), the two-failure
accumulating case (SC-003), and the empty-UTxO short-circuit
edge case.
-}
module Cardano.Tx.ValidateSpec (
    spec,
) where

import Data.Aeson qualified as Aeson
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, fromMaybe)
import Data.Ratio ((%))
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

import Cardano.Slotting.EpochInfo qualified as EpochInfo
import Cardano.Slotting.Time (SystemStart (..))
import Cardano.Slotting.Time qualified as SlottingTime

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (AccountAddress, Withdrawals (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.TxBody (
    ScriptIntegrityHash,
    scriptIntegrityHashTxBodyL,
 )
import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Api.Tx.Body (
    feeTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (
    ActiveSlotCoeff,
    EpochSize (..),
    Globals (..),
    Network (Mainnet, Testnet),
    SlotNo (..),
    StrictMaybe (..),
    TxIx (..),
    boundRational,
    knownNonZeroBounded,
    mkActiveSlotCoeff,
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ApplyTxError (..), ConwayEra)
import Cardano.Ledger.Conway.Rules (
    ConwayLedgerPredFailure (..),
    ConwayUtxowPredFailure (..),
 )
import Cardano.Ledger.Core (bodyTxL)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.Build (mkPParamsBound)
import Cardano.Tx.BuildSpec (loadBody, loadPParams)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Validate (
    isWitnessCompletenessFailure,
    validatePhase1,
    validatePhase1WithGlobals,
    validatePhase1WithGlobalsAndRewardAccounts,
    validatePhase1WithRewardAccounts,
 )
import Cardano.Tx.Validate.LoadUtxo (loadUtxo)
import Fixtures.RewriteRedesign.Helpers (
    stubRewardAccount,
    stubTxIn,
    stubTxOut,
 )
import Fixtures.RewriteRedesign.S05_WithdrawalScriptStake qualified as WithdrawalScriptStake

spec :: Spec
spec = do
    callerGlobalsSpec
    synthesisedNetworkSpec

{- | Caller-supplied 'Globals' entry points.

These pin what this pure Phase-1 boundary can actually observe:

* the caller's 'networkId' governs the verdict for the exact
  candidate, through both entry points;
* the complete 'ApplyTxError' the legacy wrapper returns is
  returned unchanged, with no filtering or reclassification;
* reward-account seeding is unchanged; and
* the no-reward entry point is the empty-reward specialisation.

Deliberately NOT asserted here: that the caller's 'epochInfo' and
'systemStart' reach the ledger. No rule reachable from
@applyTx@ with the committed fixtures observes them — deadline
translation happens at the script-context boundary, which this
suite does not reach — so an assertion of that here would claim
more than it executes. Per A-068 the delegation of the exact
'Globals' object is proven by GREEN source review, and the full
coordinate binding is proven downstream at the applied-validator
boundary where synthetic and real intervals already differ.
-}
callerGlobalsSpec :: Spec
callerGlobalsSpec =
    describe "Cardano.Tx.Validate.validatePhase1WithGlobals" $ do
        -- The candidate withdraws from a Testnet reward account. Under a
        -- caller coordinate whose networkId is Testnet the ledger accepts
        -- the account's network; under an otherwise identical coordinate
        -- whose networkId is Mainnet it reports a network mismatch for the
        -- same candidate, same UTxO and same slot. Only the caller's
        -- 'Globals' differs, so the verdict is governed by the supplied
        -- value and not by a synthesised network coordinate.
        it
            ( "caller Globals networkId governs the exact candidate, "
                <> "not a synthesised coordinate"
            )
            $ do
                pp <- loadPParams ppPath
                let seeded =
                        Map.singleton withdrawalRewardAccount (Coin 0)
                    matching =
                        validateWithdrawalWithGlobals
                            (devnetShapedGlobals Testnet)
                            seeded
                            pp
                    mismatched =
                        validateWithdrawalWithGlobals
                            (devnetShapedGlobals Mainnet)
                            seeded
                            pp
                resultFailures matching
                    `shouldSatisfy` not . any isWrongNetworkFailure
                resultFailures mismatched
                    `shouldSatisfy` any isWrongNetworkFailure

        -- The same differential holds through the no-reward entry point,
        -- so neither convenience wrapper reintroduces a synthesised
        -- coordinate of its own.
        it
            ( "caller Globals networkId governs the no-reward entry "
                <> "point too"
            )
            $ do
                pp <- loadPParams ppPath
                let matching =
                        validatePhase1WithGlobals
                            (devnetShapedGlobals Testnet)
                            (mkPParamsBound pp)
                            withdrawalUtxo
                            (SlotNo 0)
                            withdrawZeroTx
                    mismatched =
                        validatePhase1WithGlobals
                            (devnetShapedGlobals Mainnet)
                            (mkPParamsBound pp)
                            withdrawalUtxo
                            (SlotNo 0)
                            withdrawZeroTx
                resultFailures matching
                    `shouldSatisfy` not . any isWrongNetworkFailure
                resultFailures mismatched
                    `shouldSatisfy` any isWrongNetworkFailure

        -- The no-reward entry point is exactly the empty-reward
        -- specialisation of the reward-aware one: same caller Globals,
        -- same candidate, same result.
        it
            ( "the no-reward entry point is the empty-reward "
                <> "specialisation of the reward-aware one"
            )
            $ do
                pp <- loadPParams ppPath
                buggy <- loadBody bodyPath
                utxo <- loadUtxo producerTxDir issue8TxIns
                let tx = postFix buggy
                    slot = inRangeSlot tx
                    globals = devnetShapedGlobals Mainnet
                    plain =
                        validatePhase1WithGlobals
                            globals
                            (mkPParamsBound pp)
                            utxo
                            slot
                            tx
                    withEmptyRewards =
                        validatePhase1WithGlobalsAndRewardAccounts
                            globals
                            (mkPParamsBound pp)
                            utxo
                            Map.empty
                            slot
                            tx
                renderResult plain
                    `shouldBe` renderResult withEmptyRewards

        -- Reward seeding is unchanged by the caller-Globals entry point:
        -- an absent account still surfaces the ledger's own
        -- WithdrawalsNotInRewardsCERTS, and a seeded zero-balance account
        -- still suppresses it, under the caller's coordinate.
        it
            ( "caller-supplied registered reward accounts remain seeded "
                <> "under the caller Globals"
            )
            $ do
                pp <- loadPParams ppPath
                let globals = devnetShapedGlobals Testnet
                    unregistered =
                        validateWithdrawalWithGlobals globals Map.empty pp
                    registered =
                        validateWithdrawalWithGlobals
                            globals
                            (Map.singleton withdrawalRewardAccount (Coin 0))
                            pp
                resultFailures unregistered
                    `shouldSatisfy` any isWithdrawalsNotInRewardsFailure
                resultFailures registered
                    `shouldSatisfy` not . any isWithdrawalsNotInRewardsFailure

        -- Complete error parity with the legacy wrapper. The same doubly
        -- mutated candidate, UTxO and slot are validated through
        -- 'validatePhase1 Mainnet' and through the caller entry point
        -- given a coordinate matching that wrapper's synthesised one.
        -- The COMPLETE rendered outcomes must be equal, so no failure can
        -- be filtered, dropped, reordered or reclassified by the new API:
        -- an implementation that preserved only the fee and
        -- integrity-hash failures would fail this assertion.
        it
            ( "returns the complete ApplyTxError the legacy wrapper "
                <> "returns, unfiltered and unreclassified"
            )
            $ do
                pp <- loadPParams ppPath
                buggy <- loadBody bodyPath
                utxo <- loadUtxo producerTxDir issue8TxIns
                let tx = zeroFee buggy
                    slot = inRangeSlot tx
                    legacy =
                        validatePhase1
                            Mainnet
                            (mkPParamsBound pp)
                            utxo
                            slot
                            tx
                    caller =
                        validatePhase1WithGlobals
                            (mainnetShapedGlobals Mainnet)
                            (mkPParamsBound pp)
                            utxo
                            slot
                            tx
                renderResult caller `shouldBe` renderResult legacy
                -- Guard the assertion above against being vacuously
                -- satisfied by two empty failure lists.
                resultFailures legacy `shouldSatisfy` (not . null)

{- | A deliberately devnet-shaped caller coordinate: 100 ms slots,
100-slot epochs, and a non-POSIX-zero system start. This is the
shape the node/devnet builder actually uses, and the shape the
previously synthesised mainnet coordinate could not express.
-}
devnetShapedGlobals :: Network -> Globals
devnetShapedGlobals network =
    (mainnetShapedGlobals network)
        { epochInfo =
            EpochInfo.fixedEpochInfo
                (EpochSize 100)
                (SlottingTime.mkSlotLength 0.1)
        , systemStart = systemStartFromText "2030-01-01T00:00:00Z"
        }

{- | A mainnet-shaped caller coordinate, used as the contrast case
and as the base record the devnet coordinate overrides.
-}
mainnetShapedGlobals :: Network -> Globals
mainnetShapedGlobals network =
    Globals
        { epochInfo =
            EpochInfo.fixedEpochInfo
                (EpochSize 432000)
                (SlottingTime.mkSlotLength 1)
        , slotsPerKESPeriod = 129600
        , stabilityWindow = 129600
        , randomnessStabilisationWindow = 172800
        , securityParameter = knownNonZeroBounded @2160
        , maxKESEvo = 62
        , quorum = 5
        , maxLovelaceSupply = 45 * 1000 * 1000 * 1000 * 1000 * 1000
        , activeSlotCoeff = testActiveSlotCoeff
        , networkId = network
        , systemStart = systemStartFromText "1970-01-01T00:00:00Z"
        }

testActiveSlotCoeff :: ActiveSlotCoeff
testActiveSlotCoeff =
    mkActiveSlotCoeff
        (fromMaybe maxBound (boundRational (1 % 20)))

{- | Decode an ISO-8601 instant with Aeson, so the fixture obtains a
typed 'SystemStart' without this test component taking a direct
@time@ dependency (the fence adds no Cabal change).
-}
systemStartFromText :: Text.Text -> SystemStart
systemStartFromText text =
    case Aeson.eitherDecodeStrict encoded of
        Right value -> SystemStart value
        Left err ->
            error ("systemStartFromText: " <> err)
  where
    encoded =
        TextEncoding.encodeUtf8 ("\"" <> text <> "\"")

{- | Run the withdrawal fixture through the caller-Globals
reward-aware entry point.
-}
validateWithdrawalWithGlobals ::
    Globals ->
    Map.Map AccountAddress Coin ->
    PParams ConwayEra ->
    Either (ApplyTxError ConwayEra) ()
validateWithdrawalWithGlobals globals rewardAccounts pp =
    validatePhase1WithGlobalsAndRewardAccounts
        globals
        (mkPParamsBound pp)
        withdrawalUtxo
        rewardAccounts
        (SlotNo 0)
        withdrawZeroTx

-- | The carried failure list, or none when the ledger accepted.
resultFailures ::
    Either (ApplyTxError ConwayEra) () ->
    [ConwayLedgerPredFailure ConwayEra]
resultFailures (Left err) = failures err
resultFailures (Right ()) = []

{- | Compare two results by their rendered outcome, so the
equality assertion does not depend on an 'Eq' instance for
'ApplyTxError'.
-}
renderResult ::
    Either (ApplyTxError ConwayEra) () ->
    String
renderResult (Right ()) = "Right ()"
renderResult (Left err) = show (failures err)

{- | Recognise the network-mismatch failures the Conway UTXO rule
surfaces when an address or withdrawal account belongs to a
different network than the one the run's 'Globals' names.
-}
isWrongNetworkFailure ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isWrongNetworkFailure failure =
    "WrongNetwork" `Text.isInfixOf` Text.pack (show failure)

{- | The pre-existing wrappers, unchanged. They keep synthesising a
coordinate from a 'Network' and must stay source- and
behaviour-compatible.
-}
synthesisedNetworkSpec :: Spec
synthesisedNetworkSpec = describe "Cardano.Tx.Validate.validatePhase1" $ do
    it
        ( "post-fix issue-#8 swap-cancel body returns only "
            <> "witness-completeness noise"
        )
        $ do
            pp <- loadPParams ppPath
            buggy <- loadBody bodyPath
            utxo <- loadUtxo producerTxDir issue8TxIns
            let tx = postFix buggy
                slot = inRangeSlot tx
                result =
                    validatePhase1
                        Mainnet
                        (mkPParamsBound pp)
                        utxo
                        slot
                        tx
            result `shouldSatisfy` isLeft
            case result of
                Right () -> error "expected Left on unsigned tx"
                Left err ->
                    failures err
                        `shouldSatisfy` all isWitnessCompletenessFailure

    it
        ( "pre-fix issue-#8 swap-cancel body surfaces the "
            <> "integrity-hash mismatch (SC-002)"
        )
        $ do
            pp <- loadPParams ppPath
            tx <- loadBody bodyPath
            utxo <- loadUtxo producerTxDir issue8TxIns
            let result =
                    validatePhase1
                        Mainnet
                        (mkPParamsBound pp)
                        utxo
                        (inRangeSlot tx)
                        tx
            case result of
                Right () -> error "expected Left on pre-fix body"
                Left err ->
                    failures err
                        `shouldSatisfy` any isIntegrityHashMismatch

    it
        ( "zero-fee mutation surfaces a fee-related failure "
            <> "(FR-007 negative test)"
        )
        $ do
            pp <- loadPParams ppPath
            buggy <- loadBody bodyPath
            utxo <- loadUtxo producerTxDir issue8TxIns
            let tx = zeroFee (postFix buggy)
                result =
                    validatePhase1
                        Mainnet
                        (mkPParamsBound pp)
                        utxo
                        (inRangeSlot tx)
                        tx
            case result of
                Right () -> error "expected Left on zero-fee tx"
                Left err ->
                    failures err `shouldSatisfy` any isFeeFailure

    it
        ( "fee + integrity-hash mutation surfaces both failures "
            <> "in one call (SC-003 accumulating)"
        )
        $ do
            pp <- loadPParams ppPath
            buggy <- loadBody bodyPath
            utxo <- loadUtxo producerTxDir issue8TxIns
            -- pre-fix body already has the bad integrity hash;
            -- zero the fee on top so both mutations are present.
            let tx = zeroFee buggy
                result =
                    validatePhase1
                        Mainnet
                        (mkPParamsBound pp)
                        utxo
                        (inRangeSlot tx)
                        tx
            case result of
                Right () -> error "expected Left on doubly-mutated tx"
                Left err -> do
                    let errs = failures err
                    errs `shouldSatisfy` any isFeeFailure
                    errs `shouldSatisfy` any isIntegrityHashMismatch

    -- Edge case from spec.md: 'If the supplied UTxO contains zero
    -- entries for any of the tx's inputs, the mempool
    -- short-circuits via the whenFailureFreeDefault duplicate-
    -- detection gate and the only failure reported is that one.'
    -- The defensive negative test locks the documented behaviour
    -- so a caller who passes an empty UTxO gets a recognisable
    -- mempool failure rather than silent confusion.
    it
        ( "empty UTxO short-circuits via the mempool "
            <> "duplicate-detection gate"
        )
        $ do
            pp <- loadPParams ppPath
            tx <- loadBody bodyPath
            let result =
                    validatePhase1
                        Mainnet
                        (mkPParamsBound pp)
                        []
                        (inRangeSlot tx)
                        tx
            case result of
                Right () -> error "expected Left on empty UTxO"
                Left err ->
                    failures err
                        `shouldSatisfy` any isMempoolFailure

    it
        ( "withdrawal tx with no seeded reward accounts surfaces "
            <> "WithdrawalsNotInRewardsCERTS"
        )
        $ do
            pp <- loadPParams ppPath
            let result =
                    validateWithdrawalFixture Map.empty pp
            case result of
                Right () -> error "expected Left on unregistered withdrawal"
                Left err ->
                    failures err
                        `shouldSatisfy` any isWithdrawalsNotInRewardsFailure

    it
        ( "withdrawal tx with zero-balance registered reward account "
            <> "does not surface WithdrawalsNotInRewardsCERTS"
        )
        $ do
            pp <- loadPParams ppPath
            let result =
                    validateWithdrawalFixture
                        (Map.singleton withdrawalRewardAccount (Coin 0))
                        pp
            case result of
                Right () -> pure ()
                Left err ->
                    failures err
                        `shouldSatisfy` (not . any isWithdrawalsNotInRewardsFailure)

ppPath :: FilePath
ppPath = "test/fixtures/pparams.json"

bodyPath :: FilePath
bodyPath =
    "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex"

producerTxDir :: FilePath
producerTxDir =
    "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs"

issue8TxIns :: [TxIn]
issue8TxIns =
    [ TxIn (txIdFromHex txId59e10) (TxIx 0)
    , TxIn (txIdFromHex txId59e10) (TxIx 2)
    , TxIn (txIdFromHex txIdF5f1b) (TxIx 0)
    ]

txId59e10 :: String
txId59e10 =
    "59e10ca5e03b8d243c699fc45e1e18a2a825e2a09c5efa6954aec820a4d64dfe"

txIdF5f1b :: String
txIdF5f1b =
    "f5f1bdfad3eb4d67d2fc36f36f47fc2938cf6f001689184ab320735a28642cf2"

{- | Pick a slot that satisfies the body's validity interval so
the validity-interval rule doesn't reject the tx for an
unrelated reason. Uses the lower bound if present, else slot
zero (no lower bound means any slot is acceptable).
-}
inRangeSlot :: ConwayTx -> SlotNo
inRangeSlot tx =
    let ValidityInterval lo _ = tx ^. bodyTxL . vldtTxBodyL
     in case lo of
            SJust s -> s
            SNothing -> SlotNo 0

txIdFromHex :: String -> TxId
txIdFromHex hex =
    TxId
        (unsafeMakeSafeHash (fromJust (hashFromStringAsHex hex)))

{- | The committed @body.cbor.hex@ fixture is the **pre-fix** body —
its @script_integrity_hash@ field carries the buggy value
@03e9d7ed…1941@ that mainnet rejected. @postFix@ derives the
post-fix body by overwriting that field with the value the ledger
computes (and that PR #9's fix now emits): @41a7cd57…dcf9@.

This is intentionally test-time mutation, not a separate fixture
file: re-using the one committed body keeps the fixture surface
small and locks the relationship in code.
-}
postFix :: ConwayTx -> ConwayTx
postFix tx =
    tx
        & bodyTxL
            . scriptIntegrityHashTxBodyL
            .~ SJust expectedIntegrityHash

{- | The integrity hash the ledger expects for the
@swap-cancel-issue-8@ fixture body — same constant
@Cardano.Tx.BuildSpec@'s golden hash test asserts.
-}
expectedIntegrityHash :: ScriptIntegrityHash
expectedIntegrityHash =
    unsafeMakeSafeHash
        ( fromJust
            ( hashFromStringAsHex
                "41a7cd5798b8b6f081bfaee0f5f88dc02eea894b7ed888b2a8658b3784dcdcf9"
            )
        )

failures ::
    ApplyTxError ConwayEra ->
    [ConwayLedgerPredFailure ConwayEra]
failures (ConwayApplyTxError errs) = toList errs

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

{- | Recognise the script-integrity-hash-mismatch constructors
the Conway UTXOW rule surfaces when the body's
@script_integrity_hash@ field does not match what the ledger
recomputes from witness-set redeemers, datums, and cost-model
language views.

The pinned ledger version uses 'PPViewHashesDontMatch' for this
case (older variant); 'ScriptIntegrityHashMismatch' is the newer
explicit constructor. Recognising both keeps the assertion
robust across CHaP bumps.
-}
isIntegrityHashMismatch ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isIntegrityHashMismatch (ConwayUtxowFailure failure) = case failure of
    PPViewHashesDontMatch _ -> True
    ScriptIntegrityHashMismatch _ _ -> True
    _ -> False
isIntegrityHashMismatch _ = False

{- | Overwrite the body's fee to zero. The minimum-fee check
fires through @UtxoFailure@ — a fee-related failure means
@ConwayUtxowFailure (UtxoFailure ...)@ carrying a
@FeeTooSmallUTxO@-shaped sub-failure in the pinned ledger
version.
-}
zeroFee :: ConwayTx -> ConwayTx
zeroFee tx =
    tx & bodyTxL . feeTxBodyL .~ Coin 0

{- | Recognise any failure that carries a fee-related sub-failure.
We check the rendered @show@ output rather than pattern-matching
on the @UtxoFailure@ sub-constructor name, because the
@AlonzoUtxoPredFailure@ shape has reshuffled across ledger
releases (some versions split fee-too-small from
fee-not-balanced). Pattern matching on the rendered shape keeps
the assertion resilient.
-}
isFeeFailure ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isFeeFailure failure =
    "Fee" `Text.isInfixOf` Text.pack (show failure)

{- | Recognise the @ConwayMempoolFailure@ that surfaces when
the LEDGER subrule short-circuits via
@whenFailureFreeDefault@'s duplicate-detection gate (i.e., none
of the tx's inputs were in the supplied UTxO).
-}
isMempoolFailure ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isMempoolFailure (ConwayMempoolFailure _) = True
isMempoolFailure _ = False

withdrawalRewardAccount :: AccountAddress
withdrawalRewardAccount = stubRewardAccount 1

withdrawalUtxo :: [(TxIn, TxOut ConwayEra)]
withdrawalUtxo = [(stubTxIn 1, stubTxOut 2_000_000)]

validateWithdrawalFixture ::
    Map.Map AccountAddress Coin ->
    PParams ConwayEra ->
    Either (ApplyTxError ConwayEra) ()
validateWithdrawalFixture rewardAccounts pp =
    validatePhase1WithRewardAccounts
        Testnet
        (mkPParamsBound pp)
        withdrawalUtxo
        rewardAccounts
        (SlotNo 0)
        withdrawZeroTx

withdrawZeroTx :: ConwayTx
withdrawZeroTx =
    WithdrawalScriptStake.tx
        & bodyTxL
            . withdrawalsTxBodyL
            .~ Withdrawals
                (Map.singleton withdrawalRewardAccount (Coin 0))

isWithdrawalsNotInRewardsFailure ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isWithdrawalsNotInRewardsFailure failure =
    "WithdrawalsNotInRewardsCERTS"
        `Text.isInfixOf` Text.pack (show failure)

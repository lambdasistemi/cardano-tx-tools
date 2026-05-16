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

import Data.Foldable (toList)
import Data.Maybe (fromJust)
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Spec, describe, it, shouldSatisfy)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.TxBody (
    ScriptIntegrityHash,
    scriptIntegrityHashTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Body (vldtTxBodyL)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet),
    SlotNo (..),
    StrictMaybe (..),
    TxIx (..),
 )
import Cardano.Ledger.Conway (ApplyTxError (..), ConwayEra)
import Cardano.Ledger.Conway.Rules (ConwayLedgerPredFailure)
import Cardano.Ledger.Core (bodyTxL)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.Build (mkPParamsBound)
import Cardano.Tx.BuildSpec (loadBody, loadPParams)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Validate (isWitnessCompletenessFailure, validatePhase1)
import Cardano.Tx.Validate.LoadUtxo (loadUtxo)

spec :: Spec
spec = describe "Cardano.Tx.Validate.validatePhase1" $ do
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

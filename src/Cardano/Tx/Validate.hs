{-# LANGUAGE DataKinds #-}

{- |
Module      : Cardano.Tx.Validate
Description : Conway Phase-1 pre-flight against ledger applyTx.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Run the Conway ledger's Phase-1 rule (UTXOW + LEDGER) against a
candidate transaction without submitting it. The transaction is
typically the unsigned 'ConwayTx' that
"Cardano.Tx.Build" returns; callers invoke 'validatePhase1'
between build and sign to catch structural bugs (script integrity
hash mismatch, fee bounds, min-utxo, collateral, validity
interval, ref-script bytes, language-view consistency) before
paying the signing or submission cost.

On unsigned input, the ledger's @applyTx@ always raises
'MissingVKeyWitnessesUTXOW' (and similar native-script-signature
failures) alongside any genuine structural problems. These are
expected noise that callers strip via a downstream
@isWitnessCompletenessFailure@ helper (added in a follow-up
slice); a @Right ()@ result is therefore essentially impossible
on unsigned input. The contract is "no structural failure
remained after filtering."

The recipe (synthesise 'Globals', seed 'NewEpochState' via
'def', call 'Mempool.applyTx') is duplicated verbatim from
[@cardano-ledger-inspector@'s @Conway.Inspector.Validation@](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs).
See @specs/014-validate-phase1/spec.md@ "Implementation strategy"
and upstream consolidation ticket
<https://github.com/lambdasistemi/cardano-ledger-inspector/issues/73>
for the rationale and the swap-to-dependency path if the typed
kernel ships upstream.
-}
module Cardano.Tx.Validate (
    validatePhase1,
    isWitnessCompletenessFailure,
) where

import Data.Default (def)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Ratio ((%))
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Lens.Micro ((&), (.~))

import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (
    ActiveSlotCoeff,
    EpochSize (..),
    Globals (..),
    Network,
    SlotNo,
    boundRational,
    knownNonZeroBounded,
    mkActiveSlotCoeff,
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Rules (
    ConwayLedgerPredFailure (..),
    ConwayUtxowPredFailure (..),
 )
import Cardano.Ledger.Shelley.API.Mempool (
    ApplyTxError,
    applyTx,
    mkMempoolEnv,
    mkMempoolState,
 )
import Cardano.Ledger.Shelley.LedgerState (
    NewEpochState,
    curPParamsEpochStateL,
    esLStateL,
    lsUTxOStateL,
    nesEsL,
    utxoL,
 )
import Cardano.Ledger.State qualified as LedgerState
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Slotting.EpochInfo qualified as EpochInfo
import Cardano.Slotting.Time (SystemStart (..))
import Cardano.Slotting.Time qualified as SlottingTime

import Cardano.Tx.Build (PParamsBound, unPParamsBound)
import Cardano.Tx.Ledger (ConwayTx)

{- | Run Conway Phase-1 validation against a candidate transaction.

Pure: no @IO@. Synthesises a ledger 'Globals' from the supplied
'Network', seeds a fresh 'NewEpochState' with the unwrapped
'PParams' and the supplied UTxO at the given 'SlotNo', wraps that
in a 'MempoolEnv' + 'MempoolState', and calls
@Cardano.Ledger.Shelley.API.Mempool.applyTx@. The returned
'ApplyTxError' is exposed verbatim — no re-classification, no
filtering. Callers needing to drop witness-completeness noise
filter the carried @NonEmpty ConwayLedgerPredFailure@ at their
end.

== Mempool seeding caveat

If the supplied UTxO does not contain at least one entry for any
of the transaction's inputs, the mempool short-circuits via
the @whenFailureFreeDefault@ duplicate-detection gate and the
only failure reported is that one. The test suite covers this
defensive negative case.
-}
validatePhase1 ::
    Network ->
    PParamsBound ->
    [(TxIn, TxOut ConwayEra)] ->
    SlotNo ->
    ConwayTx ->
    Either (ApplyTxError ConwayEra) ()
validatePhase1 network ppBound utxo slot tx =
    let pp = unPParamsBound ppBound
        nes = seedNewEpochState pp utxo
        env = mkMempoolEnv nes slot
        state = mkMempoolState nes
     in case applyTx (synthesiseGlobals network) env state tx of
            Right _ -> Right ()
            Left err -> Left err

{- | Seed a fresh 'NewEpochState' for the supplied era with the
caller-supplied protocol parameters and UTxO. Everything else
comes from @def@'s defaults (empty account state, no stake/cert
state, etc.).

This is the typed mirror of
[inspector's @validationNewEpochState@](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L400-L413).
-}
seedNewEpochState ::
    PParams ConwayEra ->
    [(TxIn, TxOut ConwayEra)] ->
    NewEpochState ConwayEra
seedNewEpochState pp utxo =
    def
        & nesEsL . curPParamsEpochStateL .~ pp
        & nesEsL
            . esLStateL
            . lsUTxOStateL
            . utxoL
            .~ LedgerState.UTxO (Map.fromList utxo)

{- | Synthesise a 'Globals' for the supplied 'Network'. All
non-@networkId@ fields are hardcoded to mainnet-shaped Shelley
genesis constants (k=2160, slot length 1s, epoch size 432000,
active-slots-coeff 1/20, etc.). Phase-1 (UTXOW + LEDGER) reads
@networkId@ and uses @epochInfo@ for slot-to-epoch resolution;
the other fields are stake-pool / KES bookkeeping the mempool
rule does not touch.

A future caller that needs per-magic distinction (preview vs
preprod) or non-mainnet @k@/@f@ would need this lifted into a
'Globals' parameter; out of scope here, tracked by upstream
consolidation ticket
<https://github.com/lambdasistemi/cardano-ledger-inspector/issues/73>.
-}
synthesiseGlobals :: Network -> Globals
synthesiseGlobals network =
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
        , activeSlotCoeff = defaultActiveSlotCoeff
        , networkId = network
        , systemStart =
            SystemStart (posixSecondsToUTCTime 0)
        }

defaultActiveSlotCoeff :: ActiveSlotCoeff
defaultActiveSlotCoeff =
    mkActiveSlotCoeff
        (fromMaybe maxBound (boundRational (1 % 20)))

{- | Recognise the failure constructor that any unsigned candidate
transaction trips via @applyTx@'s UTXOW rule. This is not a
structural bug; it reflects the fact that 'validatePhase1' is a
pre-flight run BEFORE signing.

Typical caller workflow — drop these from the carried
@NonEmpty ConwayLedgerPredFailure@ and inspect what remains:

@
case 'validatePhase1' net pp utxo slot tx of
    Right () -> ...
    Left ('Cardano.Ledger.Conway.ConwayApplyTxError' errs) ->
        let structural =
                filter (not . 'isWitnessCompletenessFailure')
                    (Data.Foldable.toList errs)
        in if null structural
            then -- only noise; safe to sign
            else -- real Phase-1 bug; halt the pipeline
@

Constructor recognised as noise (locked by spec SC-004):

* @'ConwayUtxowFailure' ('MissingVKeyWitnessesUTXOW' _)@ —
  required vkey signers without witnesses.

Constructors deliberately NOT recognised as noise — they fire on
both signed and unsigned input, so they're genuine structural
issues either way:

* @'MissingScriptWitnessesUTXOW'@ — native or Plutus scripts that
  the body references but the build did NOT attach to the witness
  set (or expose via reference inputs). That is a build-time
  oversight, not a signing-step concern.
* metadata-hash mismatches (@MissingTxBodyMetadataHash@,
  @ConflictingMetadataHash@)
* script-integrity-hash mismatches
  (@ScriptIntegrityHashMismatch@, @PPViewHashesDontMatch@)
* fee, min-utxo, collateral, validity-interval failures
* @ScriptWitnessNotValidatingUTXOW@ (Plutus-eval failure is
  Phase-2 but exposed through the same rule)
* ref-script bytes / language-view consistency

If a future pinned ledger version adds a new
witness-completeness constructor — i.e., a failure that fires
specifically because vkey signatures are absent — bump
cardano-haskell-packages, extend this function, and update the
locked-list test in @Cardano.Tx.ValidateSpec@ in the same
commit. The compiler enforces exhaustiveness at the pattern
match level; reviewer checks the new constructor doc.
-}
isWitnessCompletenessFailure ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isWitnessCompletenessFailure (ConwayUtxowFailure failure) = case failure of
    MissingVKeyWitnessesUTXOW _ -> True
    _ -> False
isWitnessCompletenessFailure _ = False

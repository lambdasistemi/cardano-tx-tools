{- |
Module      : Cardano.Tx.Scripts
Description : Script fee and integrity helpers
License     : Apache-2.0

Helpers for script-related transaction body concepts
used by builders and balancers.
-}
module Cardano.Tx.Scripts (
    computeScriptIntegrity,
    languagesUsedInTx,
    languagesUsedIn,
    evalBudgetExUnits,
    placeholderExUnits,
    refScriptsSize,
) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Lens.Micro ((^.))

import Cardano.Ledger.Alonzo.PParams (
    LangDepView,
    getLanguageView,
 )
import Cardano.Ledger.Alonzo.Scripts (
    plutusScriptLanguage,
    toPlutusScript,
 )
import Cardano.Ledger.Alonzo.Tx (
    ScriptIntegrity (..),
    ScriptIntegrityHash,
    hashScriptIntegrity,
 )
import Cardano.Ledger.Alonzo.TxWits (
    Redeemers (..),
    TxDats (..),
 )
import Cardano.Ledger.Api.Tx.Body (
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    referenceScriptTxOutL,
 )
import Cardano.Ledger.BaseTypes (
    StrictMaybe (SJust, SNothing),
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (
    PParams,
    Script,
    bodyTxL,
    scriptTxWitsL,
    witsTxL,
 )
import Cardano.Ledger.Hashes (
    ScriptHash,
    originalBytes,
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (Language)
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Tx.Ledger (ConwayTx)

{- | Sum the byte lengths of any reference scripts
attached to UTxOs whose 'TxIn' is in the body's
@referenceInputsTxBodyL@ set. Used to feed
@estimateMinFeeTx@ so the Conway
@minFeeRefScriptCostPerByte@ tier is correctly
charged.

Native (timelock) scripts are included in the sum;
the Conway ledger only charges Plutus scripts, so
including timelock bytes can over-estimate slightly,
which is safe: over-paying fee is accepted by the
ledger; under-paying is rejected with
@FeeTooSmallUTxO@.
-}
refScriptsSize ::
    Set TxIn ->
    [(TxIn, TxOut ConwayEra)] ->
    Int
refScriptsSize bodyRefIns =
    foldr
        ( \(i, o) acc ->
            if Set.member i bodyRefIns
                then case o ^. referenceScriptTxOutL of
                    SJust s -> acc + BS.length (originalBytes s)
                    SNothing -> acc
                else acc
        )
        0

{- | Derive the set of Plutus languages referenced by
the given witness-set scripts and reference inputs.

Walks two sources, both required because either is
sufficient on its own to introduce a language:

* Witness-set scripts — any Plutus script the tx
  carries directly.
* Reference inputs that resolve to UTxOs carrying a
  Plutus reference script.

Native (timelock) scripts are filtered out — they do
not contribute to the integrity hash.

The supplied @refUtxos@ list must contain the
resolved UTxOs for any reference input the tx
references; entries for other TxIns are ignored
(this matches the existing @refScriptsSize@ pattern).
-}
languagesUsedIn ::
    Map.Map ScriptHash (Script ConwayEra) ->
    Set TxIn ->
    [(TxIn, TxOut ConwayEra)] ->
    Set Language
languagesUsedIn witScripts refIns refUtxos =
    Set.union witLangs refLangs
  where
    witLangs =
        Set.fromList
            [ plutusScriptLanguage ps
            | s <- Map.elems witScripts
            , Just ps <- [toPlutusScript s]
            ]

    refLangs =
        Set.fromList
            [ plutusScriptLanguage ps
            | (txin, txout) <- refUtxos
            , Set.member txin refIns
            , SJust s <- [txout ^. referenceScriptTxOutL]
            , Just ps <- [toPlutusScript s]
            ]

{- | Convenience wrapper over 'languagesUsedIn' that
sources both the witness-set scripts and the
reference-input set from a fully-assembled tx.
-}
languagesUsedInTx ::
    ConwayTx ->
    [(TxIn, TxOut ConwayEra)] ->
    Set Language
languagesUsedInTx tx =
    languagesUsedIn
        (tx ^. witsTxL . scriptTxWitsL)
        (tx ^. bodyTxL . referenceInputsTxBodyL)

{- | Compute the 'ScriptIntegrityHash' from protocol
parameters, a body-derived set of Plutus languages,
the redeemers, and the witness-set datums.

The hash covers the cost-model language views for
exactly the languages referenced by the body, the
redeemers in their witness-set form (Conway map form
for Conway), and the witness-set datums map (which
may be empty for inline-only datum txs).

The language set is intentionally an input rather
than derived inside this function: callers know the
tx and the resolved reference-input UTxOs and can
compute it via 'languagesUsedInTx'. Pulling that
derivation up keeps this helper independent of
@TxOut@ resolution.

Returns 'SNothing' when there are no redeemers, no
datums, and no language views — i.e. the tx carries
nothing the hash would commit to.
-}
computeScriptIntegrity ::
    Set Language ->
    PParams ConwayEra ->
    Redeemers ConwayEra ->
    TxDats ConwayEra ->
    StrictMaybe ScriptIntegrityHash
computeScriptIntegrity langs pp rdmrs dats =
    let langViews :: Set LangDepView
        langViews = Set.map (getLanguageView pp) langs
        Redeemers redeemerMap = rdmrs
        TxDats datMap = dats
     in if Map.null redeemerMap
            && Map.null datMap
            && Set.null langViews
            then SNothing
            else
                SJust $
                    hashScriptIntegrity $
                        ScriptIntegrity rdmrs dats langViews

{- | Zero execution units, used as placeholder when
building a transaction before script evaluation.
After calling @evaluateTx@, patch the redeemers
with the real values.
-}
placeholderExUnits :: ExUnits
placeholderExUnits = ExUnits 0 0

{- | Max-budget execution units for script
evaluation. The ledger evaluator uses redeemer
ExUnits as the execution budget; scripts that
exceed the budget are terminated. This value is
injected before @evaluateTx@ so scripts get enough
room to run, then replaced by the real ExUnits from
the evaluation result.

Sized to mainnet's Conway-era @maxTxExUnits@
(epoch 627+: 16_500_000 mem, 10_000_000_000
steps), so heavy scripts that already run on
mainnet fit under the eval budget locally too.
Submission fails the same way as it would on
mainnet if a script's actual usage exceeds the
cluster's pp.
-}
evalBudgetExUnits :: ExUnits
evalBudgetExUnits = ExUnits 16_500_000 10_000_000_000

{- |
Module      : Cardano.Tx.Evaluate
Description : Evaluate scripts and balance in one step
License     : Apache-2.0

Combines script evaluation, execution unit patching,
integrity hash recomputation, and transaction
balancing into a single function. Evaluation is
iterated against the balanced transaction body so
validators see the same TxInfo shape during local
evaluation and submission.

This is the standard workflow for submitting
transactions with Plutus scripts:

1. Build a tx with 'placeholderExUnits'
2. Call 'evaluateAndBalance', passing an evaluator
   function (typically @evaluateTx provider@ from
   cardano-node-clients's 'Provider')
3. Sign and submit

@
tx <- evaluateAndBalance (evaluateTx prov) pp
        [feeUtxo, scriptUtxo] [refScriptUtxo]
        changeAddr unbalancedTx
let signed = addKeyWitness sk tx
submitTx submitter signed
@

The evaluator function is passed in rather than the full 'Provider'
record so this module has no node-client dependency.
-}
module Cardano.Tx.Evaluate (
    EvaluateTxResult,
    evaluateAndBalance,
) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Lens.Micro ((&), (.~), (^.))

import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (
    TransactionScriptFailure,
 )
import Cardano.Ledger.Alonzo.Scripts (AsIx, PlutusPurpose)
import Cardano.Ledger.Alonzo.TxBody (
    scriptIntegrityHashTxBodyL,
 )
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Tx (
    bodyTxL,
    witsTxL,
 )
import Cardano.Ledger.Api.Tx.Body (
    feeTxBodyL,
    inputsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Api.Tx.Wits (
    datsTxWitsL,
    rdmrsTxWitsL,
 )
import Cardano.Ledger.BaseTypes (
    StrictMaybe (SNothing),
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Plutus (ExUnits)
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Tx.Balance (
    BalanceResult (..),
    balanceTx,
    computeScriptIntegrity,
    evalBudgetExUnits,
    languagesUsedInTx,
 )
import Cardano.Tx.Ledger (ConwayTx)

{- | Per-script evaluation result, matching the shape returned by
'Cardano.Node.Client.Provider.evaluateTx' (and any equivalent evaluator).
Kept here so this module does not import from cardano-node-clients.
-}
type EvaluateTxResult era =
    Map
        (PlutusPurpose AsIx era)
        (Either (TransactionScriptFailure era) ExUnits)

{- | Evaluate Plutus scripts, patch execution units,
recompute the script integrity hash, and balance the
transaction.

The workflow:

1. Merge all input 'TxIn's into the body so the
   evaluator sees the complete input set (spending
   indices must match the redeemers).
2. Call 'evaluateTx' via the 'Provider' to get
   actual 'ExUnits' for each redeemer.
3. Patch each redeemer's 'ExUnits' from the
   evaluation result.
4. Recompute 'scriptIntegrityHash' with the patched
   redeemers.
5. Call 'balanceTx' to add fee inputs and a change
   output.
6. Re-evaluate the balanced transaction and repeat
   until fee and redeemer ExUnits are stable.

Throws an error if script evaluation fails or
balancing fails (insufficient funds).
-}
evaluateAndBalance ::
    -- | Evaluator for one transaction, typically
    --     @'Cardano.Node.Client.Provider.evaluateTx' provider@. Passed
    --     in as a plain function so this module stays decoupled from
    --     cardano-node-clients.
    (ConwayTx -> IO (EvaluateTxResult ConwayEra)) ->
    PParams ConwayEra ->
    -- | All input UTxOs (fee-paying and script).
    --     Their 'TxIn's are unioned with the body's
    --     inputs.
    [(TxIn, TxOut ConwayEra)] ->
    -- | Resolved reference-input UTxOs whose
    --     'referenceScriptTxOutL' carries a Plutus
    --     script. Pass @[]@ if the tx has no
    --     ref-input scripts.
    [(TxIn, TxOut ConwayEra)] ->
    -- | Change address
    Addr ->
    -- | Unbalanced tx with 'placeholderExUnits'
    ConwayTx ->
    IO ConwayTx
evaluateAndBalance evalTx pp inputUtxos refUtxos changeAddr tx =
    go (0 :: Int) txForEval
  where
    -- Pre-add all inputs so the evaluator sees
    -- the complete input set and spending indices
    -- match the redeemers.
    existingIns =
        tx ^. bodyTxL . inputsTxBodyL
    allIns =
        foldl
            ( \s (tin, _) ->
                Set.insert tin s
            )
            existingIns
            inputUtxos
    txForEval =
        tx
            & bodyTxL . inputsTxBodyL
                .~ allIns

    go n candidate
        | n > (10 :: Int) =
            error
                "evaluateAndBalance: ExUnits did not converge"
        | otherwise = do
            evalResult <-
                evalTx (inflateRedeemerBudgets candidate)
            case evalFailures evalResult of
                [] -> do
                    balanced <-
                        balanceFromEval evalResult
                    if n > 0
                        && stableFeeAndExUnits
                            candidate
                            balanced
                        then pure balanced
                        else go (n + 1) balanced
                failures ->
                    error $
                        "evaluateAndBalance: \
                        \script eval failed: "
                            <> show failures

    inflateRedeemerBudgets candidate =
        let Redeemers rdmrMap =
                candidate ^. witsTxL . rdmrsTxWitsL
            inflated =
                Redeemers $
                    fmap
                        ( \(dat, _) ->
                            (dat, evalBudgetExUnits)
                        )
                        rdmrMap
            integrity =
                if Map.null rdmrMap
                    then SNothing
                    else
                        computeScriptIntegrity
                            (languagesUsedInTx candidate refUtxos)
                            pp
                            inflated
                            (candidate ^. witsTxL . datsTxWitsL)
         in candidate
                & witsTxL . rdmrsTxWitsL
                    .~ inflated
                & bodyTxL
                    . scriptIntegrityHashTxBodyL
                    .~ integrity

    evalFailures evalResult =
        [ (p, e)
        | (p, Left e) <-
            Map.toList evalResult
        ]

    balanceFromEval evalResult =
        let Redeemers rdmrMap =
                tx ^. witsTxL . rdmrsTxWitsL
            patched =
                Map.mapWithKey
                    ( \purpose (dat, eu) ->
                        case Map.lookup
                            purpose
                            evalResult of
                            Just (Right eu') ->
                                (dat, eu')
                            _ -> (dat, eu)
                    )
                    rdmrMap
            newRedeemers = Redeemers patched
            integrity =
                computeScriptIntegrity
                    (languagesUsedInTx tx refUtxos)
                    pp
                    newRedeemers
                    (tx ^. witsTxL . datsTxWitsL)
            patched' =
                tx
                    & witsTxL . rdmrsTxWitsL
                        .~ newRedeemers
                    & bodyTxL
                        . scriptIntegrityHashTxBodyL
                        .~ integrity
         in case balanceTx
                pp
                inputUtxos
                refUtxos
                changeAddr
                patched' of
                Left err ->
                    error $
                        "evaluateAndBalance: "
                            <> show err
                Right br -> pure (balancedTx br)

    stableFeeAndExUnits candidate balanced =
        candidate ^. bodyTxL . feeTxBodyL
            == balanced ^. bodyTxL . feeTxBodyL
            && redeemerExUnits candidate
                == redeemerExUnits balanced

    redeemerExUnits candidate =
        let Redeemers rdmrMap =
                candidate ^. witsTxL . rdmrsTxWitsL
         in fmap snd rdmrMap

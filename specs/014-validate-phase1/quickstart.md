# Quickstart: using `validatePhase1` in a signing pipeline

**Feature**: 014-validate-phase1
**Date**: 2026-05-15

## Three-step caller workflow

```haskell
import qualified Data.List.NonEmpty as NonEmpty

import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Conway.Rules (ConwayApplyTxError (..))
import Cardano.Slotting.Slot (SlotNo (..))

import Cardano.Tx.Build (PParamsBound, buildWith, mkPParamsBound)
import Cardano.Tx.Validate (isWitnessCompletenessFailure, validatePhase1)

runPipeline pp utxo slot plan = do
    -- 1. Build the unsigned tx
    case buildWith (mkPParamsBound pp) utxo slot plan of
        Left buildErr -> fail (show buildErr)
        Right tx ->
            -- 2. Pre-flight Phase-1
            case validatePhase1 Mainnet (mkPParamsBound pp) utxo slot tx of
                Right () ->
                    -- happy path: pure-signature txs only; uncommon
                    proceedToSign tx
                Left (ConwayApplyTxError errs) -> do
                    let structural =
                          filter
                            (not . isWitnessCompletenessFailure)
                            (NonEmpty.toList errs)
                    case structural of
                        []  -> proceedToSign tx
                        _xs -> fail
                            ( "Phase-1 structural failures: "
                            <> show _xs )
```

## What you need at the call site

- **`Network`** — `Mainnet` or `Testnet`. Used only to set
  `Globals.networkId`. The remaining `Globals` fields are
  network-invariant per [research.md R3](./research.md#r3-globals-constants).
- **`PParamsBound`** — built from the `PParams ConwayEra` you also
  passed to `buildWith` (single-instance discipline per PR #9 / FR-002
  of issue #8). Wrap with `mkPParamsBound`.
- **`[(TxIn, TxOut ConwayEra)]`** — the resolved UTxO for the tx's
  inputs (and reference inputs, if any). Typically the same list you
  fed to `buildWith`. If you omit entries for inputs the tx
  references, the mempool short-circuits to a duplicate-detection
  failure — covered in
  [contracts/validate-phase1.md "Mempool seeding caveat"](./contracts/validate-phase1.md).
- **`SlotNo`** — the slot you want the tx validated against. For
  pre-submission, use the current chain tip or a slot inside the tx's
  validity interval.
- **`ConwayTx`** — the unsigned tx returned by `buildWith`. (Signed
  txs are also accepted — see edge cases in spec.md — but the primary
  use is pre-flight on unsigned.)

## What you get back

`Either (ApplyTxError ConwayEra) ()`. Match on it directly:

- `Right ()` — every Phase-1 rule passed. Rare on unsigned input
  (only possible if the tx has zero required signers).
- `Left (ConwayApplyTxError errs)` — the `NonEmpty
  ConwayLedgerPredFailure` is the full accumulated failure list.
  Use `isWitnessCompletenessFailure` to filter the expected
  witness-completeness noise; whatever remains is a real structural
  bug.

## What you should NOT do

- Don't pass mismatched `PParams` between `buildWith` and
  `validatePhase1` — same instance, threaded through both. This is
  the single-instance discipline PR #9 introduced (FR-002 of #8).
- Don't pass an empty UTxO list (or one that doesn't cover the tx's
  inputs) — you'll get the mempool duplicate-detection short-circuit
  and miss every other failure.
- Don't wire `validatePhase1` *inside* `buildWith` — it's a separate
  callable by design (FR-005 of spec 014). A future `buildWith` self-validation
  layer would call `validatePhase1` after filtering noise; that's a
  separate ticket.
- Don't expect the witness-completeness failure constructors to be
  free of noise from a future ledger version — when you bump
  `cardano-ledger-conway`, re-check the locked list in
  `ValidateSpec.hs` and update `isWitnessCompletenessFailure` if a
  new noise constructor appears.

## Reading failures

A typical pre-flight failure list on a structurally-clean unsigned
tx with two required signers looks like:

```text
ConwayApplyTxError
    [ ConwayUtxowFailure (MissingVKeyWitnessesUTXOW
        { needed = [vkey1, vkey2] })
    ]
```

`isWitnessCompletenessFailure` returns `True` for the only entry,
so the filtered structural list is empty. Sign the tx.

A pre-flight failure on the pre-fix issue-#8 reproduction (wrong
`script_integrity_hash`) looks like:

```text
ConwayApplyTxError
    [ ConwayUtxowFailure (MissingVKeyWitnessesUTXOW ...)
    , ConwayUtxowFailure (PPViewHashesDontMatch
        { expected = …, provided = … })
    ]
```

The second constructor is NOT recognised as witness-completeness
noise — that's the real bug. Fail the pipeline; do not sign.

## Test fixtures

Live tests for this contract live in
`test/Cardano/Tx/ValidateSpec.hs`. To replay them locally:

```bash
nix develop -c just unit-tests
```

The relevant hspec describe is `"Cardano.Tx.Validate.validatePhase1"`.

# Data Model: Phase-1 pre-flight for unsigned transactions

**Feature**: 014-validate-phase1
**Date**: 2026-05-15

## New typed surface

This feature adds **one public function** and **zero new public
data types**. All types in the function's signature already exist
upstream or in this repo.

| Name | Source | Role |
|---|---|---|
| `validatePhase1` | New, `Cardano.Tx.Validate` | The pre-flight callable. |
| `isWitnessCompletenessFailure` | New, `Cardano.Tx.Validate` | Caller-side filter helper (FR-010). |
| `BaseTypes.Network` | `cardano-ledger-core` (`Cardano.Ledger.BaseTypes`) | Mainnet/Testnet tag. |
| `PParamsBound` | Existing, `Cardano.Tx.Build` (added in PR #9) | Newtype over `PParams ConwayEra`; single-instance discipline. |
| `(TxIn, TxOut ConwayEra)` | `cardano-ledger-core` / `cardano-ledger-conway` | Resolved UTxO pair. List form is `[(TxIn, TxOut ConwayEra)]`. |
| `SlotNo` | `cardano-slotting` (`Cardano.Slotting.Slot`) | Current slot to validate against. |
| `ConwayTx` | Existing, `Cardano.Tx.Ledger` | Type alias `Tx TopTx ConwayEra`. |
| `ApplyTxError ConwayEra` | `cardano-ledger-shelley` (`Cardano.Ledger.Shelley.API.Mempool`) | Ledger's verdict type. Carries `NonEmpty (ConwayLedgerPredFailure ConwayEra)`. |
| `ConwayLedgerPredFailure ConwayEra` | `cardano-ledger-conway` (`Cardano.Ledger.Conway.Rules`) | Individual failure constructor; what `isWitnessCompletenessFailure` pattern-matches over. |

## Internal types (module-private; not exported)

Used inside `validatePhase1` only; not part of the public surface.

| Name | Role |
|---|---|
| `Globals` (`Cardano.Ledger.BaseTypes`) | Synthesised from `Network`; constants per R3 of `research.md`. |
| `NewEpochState ConwayEra` (`Cardano.Ledger.Shelley.LedgerState`) | Seeded from `def`; lens-set with epoch, pparams, UTxO. |
| `MempoolEnv ConwayEra` / `MempoolState ConwayEra` (`Cardano.Ledger.Shelley.API.Mempool`) | Computed via `mkMempoolEnv` / `mkMempoolState`. |

## Validation rules (encoded by `validatePhase1`)

The function does not enforce its own rules — it delegates to
`Mempool.applyTx`. The rules `applyTx` runs (UTXOW + LEDGER) are
upstream-defined; this spec records them only for the test plan's
sake:

- **Structural** (the bug class we care about): script-integrity-hash
  match, fee bounds, min-utxo, collateral sufficiency, validity
  interval, ref-script bytes, language-view consistency,
  value conservation.
- **Witness-completeness** (expected noise on unsigned input):
  `MissingVKeyWitnessesUTXOW`, missing native-script signatures.

## State transitions

None. The function is pure: input → output, no state held.

## Deferred entities (for the cert-state follow-up)

The following types from inspector are deliberately NOT introduced
in this PR (R5 of `research.md`):

- `CertStateRewardEntry` (inspector's
  [Validation.hs:648-651](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L648-L651))
- `seedCertStateRewards` (inspector's
  [Validation.hs:851-871](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L851-L871))

When the follow-up ticket lands they will be ported (still inlined,
not depended-on, per spec.md "Implementation strategy") into
`Cardano.Tx.Validate` as the typed surface for withdraw-zero
validation patterns.

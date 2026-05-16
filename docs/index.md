# cardano-tx-tools

Cardano transaction tooling: Conway transaction builder, structural
diff, Plutus blueprint decoding, Phase-1 pre-flight validation, and
a transaction generator daemon.

This repository was extracted from
[`lambdasistemi/cardano-node-clients`](https://github.com/lambdasistemi/cardano-node-clients)
under tracking issue
[#152](https://github.com/lambdasistemi/cardano-node-clients/issues/152);
the extraction is complete and the package ships under its own
release cadence. See [Migration](migration.md) for the historical
plan.

## What lives here

- **`Cardano.Tx.Build`** — pure, monadic DSL for assembling Conway
  transactions: fee balancing, collateral selection, reference
  scripts, integrity-hash recomputation.
- **`Cardano.Tx.Validate.validatePhase1`** — ledger Phase-1
  pre-flight against `Mempool.applyTx` for unsigned Conway
  transactions, returning the full `ApplyTxError` verbatim.
  Companion `isWitnessCompletenessFailure` recognises the
  signing-step noise so callers can strip it and inspect what's
  structurally left.
- **`Cardano.Tx.Diff`** and the **`tx-diff`** CLI — structural
  comparison of two Conway transactions. Supports Plutus blueprint
  decoding, named collapse views, and opt-in input resolution via
  N2C and Blockfrost-style HTTP endpoints.
- **`Cardano.Tx.Blueprint`** — schema-aware decoding of Plutus
  datums and redeemers into open trees the diff and any future
  tools can address by name.
- **`Cardano.Tx.Generator.*`** and the **`cardano-tx-generator`**
  daemon — generates a configurable mix of Conway transactions
  against a running node for soak / fuzz testing.

## What does **not** live here

- N2C mini-protocol implementation, `Provider` and `Submitter`
  abstractions, UTxO chain-sync indexer — those stay in
  [`cardano-node-clients`](https://github.com/lambdasistemi/cardano-node-clients).
  The boundary is one-way: this repository depends on
  `cardano-node-clients` for node access; the reverse never holds.

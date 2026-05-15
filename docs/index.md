# cardano-tx-tools

Cardano transaction tooling: builder, structural diff, blueprint
decoding.

This repository is being bootstrapped. The actual modules (`Cardano.Tx.Build`,
`Cardano.Tx.Diff`, `Cardano.Tx.Blueprint`, the `tx-diff` executable)
migrate from
[lambdasistemi/cardano-node-clients](https://github.com/lambdasistemi/cardano-node-clients)
under tracking issue
[#152](https://github.com/lambdasistemi/cardano-node-clients/issues/152).

## What lives here

- **Transaction builder** — pure, monadic DSL for building Conway
  transactions, balancing fees, picking collateral, and selecting
  reference scripts.
- **`tx-diff`** — CLI for structural comparison of two Conway
  transactions. Supports Plutus blueprint decoding, named collapse
  views, and opt-in input resolution via N2C and Blockfrost-style
  HTTP endpoints.
- **Plutus blueprint decoder** — schema-aware decoding of Plutus
  datums and redeemers into open trees the diff and any future tools
  can address by name.

## What does **not** live here

- N2C mini-protocol implementation, `Provider` and `Submitter`
  abstractions, UTxO chain-sync indexer — those stay in
  [`cardano-node-clients`](https://github.com/lambdasistemi/cardano-node-clients).
  The boundary is one-way: this repository depends on
  `cardano-node-clients` for node access; the reverse never holds.

## Status

Bootstrap. See the [migration page](migration.md) for the moving
plan, which modules land first, and the rename from
`Cardano.Node.Client.*` to `Cardano.Tx.*`.

# cardano-tx-tools

Cardano transaction tooling: Conway transaction builder, structural
diff, Plutus blueprint decoding, Phase-1 pre-flight validation, and
a transaction generator daemon. Uses [`cardano-node-clients`][cnc]
for `Provider` / N2C access but is not itself a node client. The
dependency direction is one-way:
`cardano-tx-tools → cardano-node-clients`.

Documentation: <https://lambdasistemi.github.io/cardano-tx-tools/>.

## What's here

- `Cardano.Tx.Build` — pure, monadic DSL for assembling Conway
  transactions: fee balancing, collateral selection, reference
  scripts, integrity-hash recomputation.
- `Cardano.Tx.Validate.validatePhase1` — ledger Phase-1 pre-flight
  (`Mempool.applyTx`) for unsigned Conway transactions, returning
  the full `ApplyTxError` verbatim. Companion
  `isWitnessCompletenessFailure` so callers can strip the
  signing-step noise before deciding whether the tx is
  structurally sound.
- `Cardano.Tx.Diff` and the `tx-diff` CLI — structural comparison
  of two Conway transactions with Plutus-blueprint-aware decoding,
  named collapse views, and opt-in input resolution via N2C and
  Blockfrost-style HTTP endpoints.
- `Cardano.Tx.Blueprint` — schema-aware decoding of Plutus datums
  and redeemers into open trees.
- `Cardano.Tx.Generator.*` and the `cardano-tx-generator` daemon —
  generates a configurable mix of Conway transactions against a
  running node for soak / fuzz testing.
- `Cardano.Tx.Sign.*` and the `tx-sign` CLI — age-encrypted
  signing-key vault (`tx-sign vault create`) plus detached Conway
  vkey witness creation (`tx-sign witness`). The cleartext signing
  key is never written to disk and the passphrase is read from an
  inherited file descriptor or a no-echo TTY prompt, never argv.

## Develop

```bash
nix develop --quiet -c just build
nix develop --quiet -c just ci
```

The local gate (`nix flake check --no-eval-cache`) mirrors CI:

```bash
nix flake check --no-eval-cache
```

## License

[Apache 2.0](LICENSE).

[cnc]: https://github.com/lambdasistemi/cardano-node-clients

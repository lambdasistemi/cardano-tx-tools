# cardano-tx-tools

Tooling for Conway-era Cardano transactions. Four command-line
executables plus the Haskell library that backs them.

## Executables

- [**tx-diff**](tx-diff.md) — structural diff between two Conway
  transactions, with Plutus blueprint-aware decoding and opt-in
  input resolution via N2C or Blockfrost-style HTTP.
- [**tx-sign**](tx-sign.md) — age-encrypted signing-key vault and
  detached vkey witness creation. The cleartext signing key never
  touches disk and the passphrase is never read from `argv`.
- [**tx-validate**](tx-validate.md) — Conway Phase-1 pre-flight for
  unsigned transactions, driven via Node-to-Client against a local
  `cardano-node`. Returns the ledger's verdict as a human or JSON
  envelope; exit code is the contract (0 clean, 1 structural, ≥2
  config/resolver error).
- [**cardano-tx-generator**](cardano-tx-generator.md) — long-running
  daemon that drives a configurable mix of Conway transactions
  against a node for soak / fuzz testing.

## Library

The same logic is exposed under `Cardano.Tx.*`. Notable entry
points:

| Module                                 | What                                                       |
|----------------------------------------|------------------------------------------------------------|
| `Cardano.Tx.Build`                     | Monadic DSL for assembling Conway transactions             |
| `Cardano.Tx.Balance`                   | Fee balancing + collateral selection                       |
| `Cardano.Tx.Evaluate`                  | Redeemer re-evaluation against the final body              |
| `Cardano.Tx.Validate.validatePhase1`   | Ledger Phase-1 pre-flight (`Mempool.applyTx`)              |
| `Cardano.Tx.Diff`                      | Structural diff used by `tx-diff`                          |
| `Cardano.Tx.Blueprint`                 | Schema-aware Plutus datum/redeemer decoding                |
| `Cardano.Tx.Sign.*`                    | Vault + witness primitives used by `tx-sign`               |
| `Cardano.Tx.Generator.*`               | Generator engine used by `cardano-tx-generator`            |

Generated API reference: `cabal haddock cardano-tx-tools`.

## Install / develop

```bash
nix develop --quiet -c just build
nix develop --quiet -c just ci
```

Linux release artifacts (AppImage, DEB, RPM) for each executable
are attached to every
[GitHub Release](https://github.com/lambdasistemi/cardano-tx-tools/releases).

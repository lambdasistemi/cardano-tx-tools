# Phase 1 — Data Model

## Migrated modules

The nine library modules below move from cardano-node-clients's main
library (`lib/Cardano/Node/Client/TxGenerator/`) to cardano-tx-tools'
new sublib (`lib-tx-generator/Cardano/Tx/Generator/`). Module names
gain the `Cardano.Tx.Generator` prefix in place of
`Cardano.Node.Client.TxGenerator`. Internal structure (functions,
data types, constructors) is unchanged.

| Module | Role | Public surface |
| --- | --- | --- |
| `Cardano.Tx.Generator.Build` | Tx-building DSL specific to the load-tester (`refillTx`, `transactTx`). Wraps `Cardano.Tx.Build`. | `refillTx`, `transactTx` |
| `Cardano.Tx.Generator.Daemon` | Top-level entry point. Sets up channels, supervisors, server endpoints, persistence; runs the daemon to completion. | `runTxGenerator`, `TxGeneratorConfig`, `RefillResponse`, `TransactResponse`, etc. |
| `Cardano.Tx.Generator.Fanout` | Picks N destinations from the population for a fan-out transaction. | `Destination`, `pickDestinations` |
| `Cardano.Tx.Generator.Persist` | HD-wallet seed persistence + next-index counter on disk. | `loadOrCreateSeed`, `nextHDIndexPath`, `readNextHDIndex`, `writeNextHDIndex` |
| `Cardano.Tx.Generator.Population` | Derives HD addresses + private keys from the seed. | `deriveAddr`, `deriveSignKey`, `enterpriseAddrFromSignKey`, `mkSignKey` |
| `Cardano.Tx.Generator.Selection` | Picks UTxOs to spend each round; verifies inputs are still unspent before broadcasting. | `pickSourceIndex`, `verifyInputsUnspent` |
| `Cardano.Tx.Generator.Server` | Unix-socket control protocol (`refill`, `transact`, `snapshot`, `ready`). | `runServer`, `ServerHooks` |
| `Cardano.Tx.Generator.Snapshot` | Periodic per-population value reporting. | `collectPopulationValues`, `percentiles` |
| `Cardano.Tx.Generator.Types` | Shared request/response types between server and daemon. | `RefillRequest`, `RefillResponse`, `TransactRequest`, `TransactResponse`, `SnapshotResponse`, `ReadyResponse`, `FailureReason` |

## Executable

| Path | Role |
| --- | --- |
| `app/cardano-tx-generator/Main.hs` | Thin wrapper. Parses CLI flags, invokes `Cardano.Tx.Generator.Daemon.runTxGenerator`. |

## Unit test modules (one per non-trivial submodule)

Migrated verbatim with namespace rename. Test fixture data (if any)
moves alongside.

| Test module | Tests |
| --- | --- |
| `Cardano.Tx.Generator.FanoutSpec` | `pickDestinations` against canonical populations. |
| `Cardano.Tx.Generator.PersistSpec` | Seed roundtrip; counter monotonic. |
| `Cardano.Tx.Generator.PopulationSpec` | HD derivation against known vectors. |
| `Cardano.Tx.Generator.SelectionSpec` | `pickSourceIndex` distribution; `verifyInputsUnspent` against staged providers. |
| `Cardano.Tx.Generator.ServerSpec` | Control-socket request/response golden checks. |
| `Cardano.Tx.Generator.SnapshotSpec` | Percentile math on canonical population value vectors. |

## E2E test modules

Migrated from cardano-node-clients's `e2e-tests` test-suite. Each
spec spins up a devnet via `withCardanoNode` from
`cardano-node-clients:devnet` and exercises the daemon against it.

| Test module | What it exercises |
| --- | --- |
| `Cardano.Tx.Generator.E2E.EnduranceSpec` | Long-running fanout/refill loop survives without panic. |
| `Cardano.Tx.Generator.E2E.IndexFreshSpec` | UTxO indexer freshness signalling. |
| `Cardano.Tx.Generator.E2E.ReadySpec` | `ready` socket response after warm-up. |
| `Cardano.Tx.Generator.E2E.RefillSpec` | `refill` builds + submits a valid tx that the node accepts. |
| `Cardano.Tx.Generator.E2E.RestartSpec` | Daemon resumes correctly from on-disk state across restart. |
| `Cardano.Tx.Generator.E2E.SnapshotSpec` | Snapshot endpoint reports population values with the expected shape. |
| `Cardano.Tx.Generator.E2E.StarvationSpec` | Behavior when the faucet runs out of UTxOs. |
| `Cardano.Tx.Generator.E2E.SubmitIdempotenceSpec` | Same transaction submitted twice returns the same `TransactResponse`. |
| `Cardano.Tx.Generator.E2E.TransactSpec` | `transact` builds + submits a value-transfer tx the node accepts. |

## Dependency arrows (new sublib)

Arrows are inside cardano-tx-tools unless noted.

```text
Cardano.Tx.Generator.Daemon
  ├── Cardano.Tx.Generator.Build         (intra)
  ├── Cardano.Tx.Generator.Fanout        (intra)
  ├── Cardano.Tx.Generator.Persist       (intra)
  ├── Cardano.Tx.Generator.Population    (intra)
  ├── Cardano.Tx.Generator.Selection     (intra)
  ├── Cardano.Tx.Generator.Server        (intra)
  ├── Cardano.Tx.Generator.Snapshot      (intra)
  ├── Cardano.Tx.Generator.Types         (intra)
  ├── Cardano.Tx.Build                   (Cardano.Tx.Build in cardano-tx-tools main lib)
  ├── Cardano.Tx.Balance
  ├── Cardano.Tx.Ledger
  ├── Cardano.Node.Client.Provider       (cardano-node-clients pin)
  ├── Cardano.Node.Client.Submitter      (cardano-node-clients pin)
  ├── Cardano.Node.Client.N2C.*          (cardano-node-clients pin)
  ├── Cardano.Node.Client.UTxOIndexer.*  (cardano-node-clients pin + utxo-indexer-lib sublib)
  └── ChainFollower                      (chain-follower pin)
```

No reverse arrows. `Cardano.Tx.{Build, Balance, Ledger}` in the main
library do not import from `Cardano.Tx.Generator.*`. The
`n2c-resolver` sublib does not import from `tx-generator-lib`.

## Public surface preserved

- The `cardano-tx-generator` executable's CLI flags are exactly the
  set that ships from cardano-node-clients at the migration source
  SHA. No flag renamed, removed, or added.
- The daemon's Unix-socket control protocol (`refill`, `transact`,
  `snapshot`, `ready`) is byte-identical: same request JSON, same
  response JSON, same error codes.
- The daemon's on-disk state shape (HD seed file + counter file) is
  unchanged. Existing operator state files keep working after the
  binary is replaced with the cardano-tx-tools build.

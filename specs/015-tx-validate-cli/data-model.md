# Data Model: tx-validate CLI

**Feature**: 015-tx-validate-cli
**Date**: 2026-05-16

## New typed surface

All new types live in `Cardano.Tx.Validate.Cli`. The Blockfrost types (originally planned in `Cardano.Tx.Validate.Cli.Blockfrost`) are deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

| Name | Role |
|---|---|
| `TxValidateCliOptions` | The option record the parser produces. |
| `InputSource` | `InputFile FilePath \| InputStdin`. |
| `OutputFormat` | `Human \| Json`. |
| `N2cConfig` | `{ n2cSocket :: FilePath, n2cMagic :: NetworkMagic }`. |
| `Session` | The acquired N2C session bundle. |
| `Verdict` | The typed verdict before render. |
| `VerdictStatus` | `StructurallyClean \| StructuralFailure \| MempoolShortCircuit`. |

## `Session`

The session is produced by `withSession :: TxValidateCliOptions -> (Session -> IO a) -> IO a`:

```haskell
data Session = Session
    { sessionNetwork       :: Network
    , sessionPParams       :: PParams ConwayEra
    , sessionSlot          :: SlotNo
    , sessionUtxoResolvers :: [Resolver]     -- [n2cResolver provider] in v1
    }
```

Lifecycle: `withSession` brackets the N2C mux. On exit, the mux is torn down. The action runs with the immutable `Session` in scope.

## `Verdict`

The verdict is built by:

1. Calling `validatePhase1` and pattern-matching its `Either`.
2. Filtering the carried `NonEmpty ConwayLedgerPredFailure` through `isWitnessCompletenessFailure` (re-export from `Cardano.Tx.Validate`).

```haskell
data Verdict = Verdict
    { verdictStatus              :: VerdictStatus
    , verdictStructuralFailures  :: [ConwayLedgerPredFailure ConwayEra]
    , verdictWitnessNoiseCount   :: Int
    , verdictUtxoSources         :: Map TxIn ResolverName
    }
```

`ResolverName` is `Text` (the existing field on `Resolver`). In v1 every value will be `"n2c"`; we keep the field for forward-compat with [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

The JSON envelope's `pparams_source` / `slot_source` are derived from `Session`'s sole source (always `"n2c"` in v1).

## Output renderers

Two pure functions:

- `renderHuman :: Verdict -> Text` — verdict line + per-failure lines.
- `renderJson :: Verdict -> Aeson.Value` — JSON envelope.

Both consume the same typed `Verdict`; the executable picks one based on `txValidateCliOutput`.

## Exit code mapping

A pure function `exitCodeOf :: Verdict -> ExitCode`:

| `verdictStatus` | Exit code |
|---|---|
| `StructurallyClean` | `0` |
| `StructuralFailure` | `1` |
| `MempoolShortCircuit` | `1` (treated as structural — the supplied UTxO is stale) |

Configuration / resolver / decode failures don't produce a `Verdict`; they short-circuit before validation and exit with `≥2` per FR-007.

## State transitions

`Session` is immutable post-acquisition. `Verdict` is built once per invocation. No state machine.

## Deferred entities

`BlockfrostClient` / `BlockfrostError` — deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

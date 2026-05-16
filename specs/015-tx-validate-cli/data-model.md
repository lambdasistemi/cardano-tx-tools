# Data Model: tx-validate CLI

**Feature**: 015-tx-validate-cli
**Date**: 2026-05-16

## New typed surface

All new types live in `Cardano.Tx.Validate.Cli` (the public-library module) or in `Cardano.Tx.Validate.Cli.Blockfrost` (the Blockfrost HTTP record-of-functions).

| Name | Module | Role |
|---|---|---|
| `TxValidateCliOptions` | `Cardano.Tx.Validate.Cli` | The option record the parser produces. |
| `InputSource` | `Cardano.Tx.Validate.Cli` | `InputFile FilePath \| InputStdin`. |
| `OutputFormat` | `Cardano.Tx.Validate.Cli` | `Human \| Json`. |
| `PrimarySession` | `Cardano.Tx.Validate.Cli` | `PrimaryN2c \| PrimaryWeb2`. |
| `N2cConfig` | `Cardano.Tx.Validate.Cli` | `{ n2cSocket :: FilePath, n2cMagic :: NetworkMagic }`. |
| `Web2Config` | `Cardano.Tx.Validate.Cli` | `{ web2Base :: Text, web2ApiKey :: Maybe Text }`. |
| `Session` | `Cardano.Tx.Validate.Cli` | The acquired primary-session bundle. |
| `Verdict` | `Cardano.Tx.Validate.Cli` | The typed verdict before render. |
| `VerdictStatus` | `Cardano.Tx.Validate.Cli` | `StructurallyClean \| StructuralFailure \| MempoolShortCircuit`. |
| `BlockfrostClient` | `Cardano.Tx.Validate.Cli.Blockfrost` | Record-of-functions for the two new endpoints. |
| `BlockfrostError` | `Cardano.Tx.Validate.Cli.Blockfrost` | HTTP / decode failure surface for the Blockfrost path. |

## `Session`

The session is produced by `withSession :: TxValidateCliOptions -> (Session -> IO a) -> IO a`:

```haskell
data Session = Session
    { sessionNetwork       :: Network
    , sessionPParams       :: PParams ConwayEra
    , sessionSlot          :: SlotNo
    , sessionPrimary       :: PrimarySession
    , sessionUtxoResolvers :: [Resolver]
      -- ^ Already filtered for the supplied flags; N2C-first if both.
    }
```

Lifecycle: `withSession` brackets the primary connection (N2C mux or HTTP Manager). On exit, both connections are torn down. The action is run with the immutable `Session` in scope.

## `Verdict`

The verdict is built by:

1. Calling `validatePhase1` and pattern-matching its `Either`.
2. Filtering the carried `NonEmpty ConwayLedgerPredFailure` through `isWitnessCompletenessFailure` (re-export from `Cardano.Tx.Validate`).

```haskell
data Verdict = Verdict
    { verdictStatus               :: VerdictStatus
    , verdictStructuralFailures   :: [ConwayLedgerPredFailure ConwayEra]
    , verdictWitnessNoiseCount    :: Int
    , verdictPParamsSource        :: PrimarySession
    , verdictSlotSource           :: PrimarySession
    , verdictUtxoSources          :: Map TxIn ResolverName
    }
```

`ResolverName` is `Text` (the existing field on `Resolver`).

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
| `MempoolShortCircuit` | `1` (treated as structural — the tx's inputs aren't in the supplied UTxO, so the operator's UTxO snapshot is stale) |

Configuration / resolver / decode failures don't produce a `Verdict`; they short-circuit before validation runs and exit with `≥2` per FR-007.

## State transitions

`Session` is immutable post-acquisition. `Verdict` is built once per invocation. No state machine.

## Deferred entities

None. The full surface lands in this PR.

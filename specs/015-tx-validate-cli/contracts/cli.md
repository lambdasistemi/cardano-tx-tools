# Contract: `tx-validate` CLI surface

**Feature**: 015-tx-validate-cli
**Executable**: `tx-validate`
**Stability**: same as the rest of `Cardano.Tx.*` — follows the repo's semver discipline (constitution IV).

## Usage

```
tx-validate
    --input PATH | -
    [--n2c-socket PATH --network-magic WORD32]
    [--blockfrost-base URL [--blockfrost-key STRING]]
    [--output human|json]
    [--help]
```

At least one of `--n2c-socket` or `--blockfrost-base` MUST be supplied.

## Flags

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--input PATH` or `--input -` | yes | — | Conway tx CBOR hex file path, or `-` for stdin. |
| `--n2c-socket PATH` | conditionally (at least one resolver flag must be set) | — | Local cardano-node N2C socket. Triggers the N2C resolver and, if first on the command line, the N2C primary session. |
| `--network-magic WORD32` | with `--n2c-socket` | `764824073` (mainnet) | Network magic for the socket. |
| `--blockfrost-base URL` | conditionally (at least one resolver flag must be set) | — | Blockfrost-style HTTP endpoint base. Triggers the Web2 resolver and, if first on the command line, the Blockfrost primary session. |
| `--blockfrost-key STRING` | when `--blockfrost-base` is set and `BLOCKFROST_PROJECT_ID` is unset | from `BLOCKFROST_PROJECT_ID` env var | Blockfrost API key (`project_id`). |
| `--output human` | no | `human` | One-line verdict on stdout + zero or more structural-failure lines. |
| `--output json` | no | — | One JSON object on stdout. See [json-output.md](./json-output.md). |
| `--help` | no | — | Print usage and exit `0`. |

## Resolver-session contract

- **UTxO chain**: the executable resolves the tx's `inputs ∪ referenceInputs ∪ collateralInputs` via `resolveChain [n2cResolver?, web2Resolver?]`. N2C is tried first if both are supplied.
- **Primary session (PParams + tip slot)**: the **first** resolver source on the command line is the primary session. If `--n2c-socket` precedes `--blockfrost-base`, N2C supplies `PParams` + slot. If `--blockfrost-base` precedes `--n2c-socket`, Blockfrost does. If only one is supplied, that one is primary.
- **No mixing**: `PParams` and slot are sourced from the same primary session — they are never mixed across resolvers. The UTxO chain MAY mix sources (this is the resolver-chain's design).

## Exit-code convention

| Exit | Meaning |
|---|---|
| `0` | The tx is structurally clean: every `ConwayLedgerPredFailure` in the carried `ApplyTxError` was recognised as witness-completeness noise by `isWitnessCompletenessFailure`. Pipelines may proceed to sign. |
| `1` | At least one structural failure remained after filtering noise. Pipelines must NOT sign. The output lists the failures. Also covers `MempoolShortCircuit` (none of the tx's inputs are in the supplied UTxO — the operator's snapshot is stale; treat as a real bug). |
| `2` | Configuration error: missing required flag, conflicting flags, missing API key, missing input file. |
| `3` | Decode error: input CBOR did not decode. |
| `4` | Resolver error: the chain could not resolve one or more inputs (the verdict line is NOT printed). |
| `5` | Primary-session error: N2C connection or Blockfrost HTTP failed before producing `PParams` + slot. |
| `≥6` | Reserved for future surfaces. Callers MAY treat anything ≥ 2 as "not a verdict". |

## Standard output (human format)

Single verdict line, followed by zero or more structural-failure lines.

**Verdict line shape**:

- Clean: `structurally clean: <N> witness-completeness failures filtered`
- Failure: `structural failure: <N> structural; <M> witness-completeness filtered`
- Mempool: `mempool short-circuit: 0 of <T> inputs resolved; treat as structural`

**Structural-failure line shape** (one per failure):

```
  <rule>.<constructor>: <one-line summary>
```

Examples:

```
  UTXOW.ScriptIntegrityHashMismatch: expected 41a7cd57… got 03e9d7ed…
  UTXOW.UtxoFailure.FeeTooSmallUTxO: supplied 0 needed 257345
```

The two-space indent locks the contract: scripts can grep `^  ` to recognise failure rows.

## Standard error

Diagnostic only; not part of the contract. Examples:

- Per-input resolver trace (`txid#ix → n2c` / `txid#ix → unresolved [n2c, web2]`).
- HTTP errors (with `project_id` query parameter redacted).
- N2C handshake errors.

## Stdin / file input

- `--input -`: read CBOR hex from stdin until EOF.
- `--input PATH`: read CBOR hex from the file. Trailing whitespace ignored.

## Environment variables

| Variable | Purpose |
|---|---|
| `BLOCKFROST_PROJECT_ID` | Default `--blockfrost-key`. Per FR-002 the executable does NOT auto-enable the Blockfrost resolver from this var alone — the user must also pass `--blockfrost-base`. |

## What is NOT in the contract

- The exact `<one-line summary>` text in structural-failure lines (it's the ledger's `show` output; subject to upstream change).
- The order of structural-failure lines.
- The exact stderr text (diagnostic only).
- The number of HTTP requests issued during the session (caching is internal).

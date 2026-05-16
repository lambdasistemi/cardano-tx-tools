# Contract: `tx-validate` CLI surface

**Feature**: 015-tx-validate-cli
**Executable**: `tx-validate`
**Stability**: same as the rest of `Cardano.Tx.*` — follows the repo's semver discipline (constitution IV).
**Scope note**: v1 ships N2C-only. Blockfrost flags (`--blockfrost-base`, `--blockfrost-key`) are deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

## Usage

```
tx-validate
    --input PATH | -
    --n2c-socket PATH
    [--network-magic WORD32]
    [--output human|json]
    [--help]
```

## Flags

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--input PATH` or `--input -` | yes | — | Conway tx CBOR hex file path, or `-` for stdin. |
| `--n2c-socket PATH` | yes (v1) | — | Local cardano-node N2C socket. |
| `--network-magic WORD32` | no | `764824073` (mainnet) | Network magic for the socket. |
| `--output human` | no | `human` | One-line verdict on stdout + zero or more structural-failure lines. |
| `--output json` | no | — | One JSON object on stdout. See [json-output.md](./json-output.md). |
| `--help` | no | — | Print usage and exit `0`. |

## N2C session contract

- The CLI opens an LSQ + LTxS mux against the supplied socket, queries `PParams` + tip slot, builds an `n2cResolver`, resolves the tx's `inputs ∪ referenceInputs ∪ collateralInputs`, then closes the mux.
- The resolver chain has exactly one resolver in v1 (`n2cResolver provider`); `resolveChain` is preserved for forward-compat with [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

## Exit-code convention

| Exit | Meaning |
|---|---|
| `0` | The tx is structurally clean: every `ConwayLedgerPredFailure` in the carried `ApplyTxError` was recognised as witness-completeness noise by `isWitnessCompletenessFailure`. Pipelines may proceed to sign. |
| `1` | At least one structural failure remained after filtering noise. Pipelines must NOT sign. The output lists the failures. Also covers `MempoolShortCircuit` (none of the tx's inputs are in the supplied UTxO — the operator's snapshot is stale; treat as a real bug). |
| `2` | Configuration error: missing required flag, missing input file. |
| `3` | Decode error: input CBOR did not decode. |
| `4` | Resolver error: the N2C resolver could not resolve one or more inputs (the verdict line is NOT printed). |
| `5` | N2C session error: handshake failed, or `queryProtocolParams` / `queryLedgerSnapshot` errored before producing `PParams` + slot. |
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

- Per-input resolver trace (`txid#ix → n2c` / `txid#ix → unresolved [n2c]`).
- N2C handshake errors.

## Stdin / file input

- `--input -`: read CBOR hex from stdin until EOF.
- `--input PATH`: read CBOR hex from the file. Trailing whitespace ignored.

## What is NOT in the contract

- The exact `<one-line summary>` text in structural-failure lines (it's the ledger's `show` output; subject to upstream change).
- The order of structural-failure lines.
- The exact stderr text (diagnostic only).
- The number of N2C queries issued during the session.

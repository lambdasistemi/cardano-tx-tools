# Contract: `tx-validate` JSON output envelope

**Feature**: 015-tx-validate-cli
**Triggered by**: `--output json`
**Stability**: top-level keys are stable across minor versions; the per-failure `detail` field is best-effort and may shift with ledger updates.
**Scope note**: v1 ships N2C-only; `pparams_source` / `slot_source` / `utxo_sources` values will all be `"n2c"`. The vocabulary preserves `"blockfrost"` / `"unresolved"` for forward-compat with [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

## Top-level shape

```json
{
  "status": "structurally_clean" | "structural_failure" | "mempool_short_circuit",
  "exit_code": 0 | 1,
  "structural_failures": [
    { "rule": "<RULE>", "constructor": "<Constructor>", "detail": "<one-line summary>" }
  ],
  "witness_completeness_count": <int>,
  "pparams_source": "n2c" | "blockfrost",
  "slot_source": "n2c" | "blockfrost",
  "utxo_sources": {
    "<txId>#<ix>": "n2c" | "blockfrost" | "unresolved"
  }
}
```

## Fields

### `status`

- `structurally_clean`: every failure was filtered as witness-completeness noise.
- `structural_failure`: at least one structural failure remained.
- `mempool_short_circuit`: zero of the tx's inputs were in the supplied UTxO; treated as structural per the data-model spec.

### `exit_code`

The process-level exit code. Duplicated here for callers that pipe the JSON into other tools without also capturing the exit code.

### `structural_failures`

An array of `{rule, constructor, detail}` objects. `rule` is the STS rule short name (`UTXOW`, `CERTS`, `GOV`, `MEMPOOL`, `LEDGER.withdrawals`, `LEDGER.treasury`, `LEDGER.reference_scripts`). `constructor` is the Conway-era `PredicateFailure` constructor name. `detail` is a one-line human summary derived from the ledger's `show` output (NOT stable).

### `witness_completeness_count`

How many `MissingVKeyWitnessesUTXOW` constructors were filtered out. Always `>= 0`.

### `pparams_source` / `slot_source`

Which side of the resolver session supplied each value. Both will be the SAME string per FR-004 (no mixing).

### `utxo_sources`

Per-input mapping from `<txIdHex>#<ix>` to either:

- `"n2c"` — the input was resolved via the N2C resolver.
- `"blockfrost"` — the input was resolved via the Web2 resolver.
- `"unresolved"` — neither resolver could find it. Present only when the chain failed; in that case `exit_code` is `≥2` per CLI contract.

## Stability guarantees

Stable across minor versions:

- Top-level key names and types.
- `status` value vocabulary.
- `pparams_source` / `slot_source` / `utxo_sources` value vocabulary.

Subject to ledger upgrades:

- `structural_failures[*].constructor` values (Conway-era ledger schema; new constructors appear with new ledger versions).
- `structural_failures[*].detail` text (best-effort; do not parse).

## Examples

### Structurally clean

```json
{
  "status": "structurally_clean",
  "exit_code": 0,
  "structural_failures": [],
  "witness_completeness_count": 2,
  "pparams_source": "n2c",
  "slot_source": "n2c",
  "utxo_sources": {
    "59e10ca5…#0": "n2c",
    "59e10ca5…#2": "n2c",
    "f5f1bdfa…#0": "n2c"
  }
}
```

### Structural failure (pre-fix issue-#8)

```json
{
  "status": "structural_failure",
  "exit_code": 1,
  "structural_failures": [
    {
      "rule": "UTXOW",
      "constructor": "ScriptIntegrityHashMismatch",
      "detail": "expected 41a7cd57… got 03e9d7ed…"
    }
  ],
  "witness_completeness_count": 2,
  "pparams_source": "blockfrost",
  "slot_source": "blockfrost",
  "utxo_sources": {
    "59e10ca5…#0": "blockfrost",
    "59e10ca5…#2": "n2c",
    "f5f1bdfa…#0": "blockfrost"
  }
}
```

### Resolver error (exit `≥2`)

When the chain cannot resolve at least one input, `tx-validate` does NOT emit the JSON envelope; it prints a diagnostic to stderr and exits with the resolver error code (`4`). Callers needing a JSON-shaped error must check the exit code before parsing stdout.

(A future revision MAY add an error-shaped envelope at exit `≥2`; out of scope here.)

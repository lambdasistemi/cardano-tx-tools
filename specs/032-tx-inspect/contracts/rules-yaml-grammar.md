# Contract: rewriting-rules YAML grammar

**Branch**: `032-tx-inspect` | **Date**: 2026-05-18

Phase 1 of `/speckit.plan`. Pins the on-disk YAML grammar that
`tx-inspect --rules` and `tx-diff --rules` both consume.

This is the **on-disk contract** between users and the loader. It is
additive over the existing collapse-rules grammar that
`parseCollapseRulesYaml` accepts today.

## Document

```yaml
version: 1                          # optional, integer, defaults to 1
views:                              # optional
  raw: show | hide                  # optional, defaults to show
collapse:                           # optional, defaults to []
  - <CollapseRule>
  - …
rename:                             # optional, defaults to []     ← NEW
  - <RenameRule>
  - …
```

- **Top-level shape**: a single YAML object.
- **Unknown keys**: ignored (matches the existing parser; forward-compatible with future stages).
- **Key order**: irrelevant. `collapse:` may appear before or after `rename:` — output is identical.
- **Required keys**: none. An empty `{}` document parses to "no rules" and the renderer falls back to verbatim output.
- **Versioning**: only `version: 1` is accepted; any other value is a parse error.

## Backwards compatibility

Every existing collapse-only YAML file is **strictly accepted** with no edit. The new loader's only addition is to also read the `rename:` key when present; in its absence the renderer's behaviour is identical to today's `tx-diff` with the same rules file.

## `CollapseRule`

Unchanged from the existing grammar:

```yaml
- name: "Swap output"
  at: body.outputs
  match:
    required:
      - datum.fields.0
      - datum.fields.1
```

(Full grammar in the existing rewriting-rules grammar doc — this contract document only adds the `rename:` extension. The grammar doc is updated in S5 to incorporate the new section.)

## `RenameRule`

Each entry is one of two variants discriminated by `kind:`.

### `kind: address`

```yaml
- kind: address
  key: addr1q9...           # bech32 address (mainnet or testnet)
  match: payment            # OPTIONAL — "full" | "payment", defaults to "payment"
  name: "treasury-party"
```

- **`key`**: a valid bech32 address string. Both mainnet (`addr1…`) and testnet (`addr_test1…`) prefixes are accepted; the loader does **not** enforce a particular network — a rule may match in either context (the rule author is responsible for using the right address for the target network).
- **`match: payment`** (default): the loader extracts the payment credential from the bech32 at parse time and matches against the payment credential of every address site in the rendered transaction. The stake credential of the rendered address is ignored. One rule covers every stake variant of the same payment script.
- **`match: full`**: the loader parses the full bech32 and matches the entire `Addr` value (payment + stake credentials together). Different stake variants of the same payment script will need different rules.
- **`name`**: a non-empty UTF-8 string. Rendered in place of the bech32 wherever the rule matches.

### `kind: script`

```yaml
- kind: script
  key: 9c2e7e15a4c1b2…       # 56 hex chars (Cardano script hash, 28 bytes)
  name: "amaru.swap.v1"
```

- **`key`**: 56 hex characters representing a Cardano script hash (28 bytes). Lowercase or uppercase accepted; the loader canonicalises to lowercase for matching.
- **`match:` is IGNORED for script rules**: script-hash matches are always exact (28 bytes have no sub-structure to vary).
- **`name`**: a non-empty UTF-8 string.

## Parse errors

The loader returns `Left <error>` for any of:

- YAML decode failure (malformed YAML).
- `version:` present but not `1`.
- A `RenameRule` entry whose `kind:` is neither `"address"` nor `"script"`.
- A `kind: address` rule whose `key:` does not parse as bech32.
- A `kind: script` rule whose `key:` is not 56 hex characters.
- A rule whose `name:` is empty or missing.
- An address rule whose `match:` is present but is not `"full"` or `"payment"`.

Conversely, the loader is forgiving on:

- Missing `version:` (defaults to `1`).
- Missing `views:` (defaults to `raw: show`).
- Missing `collapse:` or `rename:` (each defaults to `[]`).
- Unknown top-level keys (ignored).
- Address rules where `match:` is missing (defaults to `payment`).
- Address rules where `match:` is present but the field would be ignored — `match:` is parsed and validated even on `kind: script` (where it is then discarded) to keep error messages predictable.

## Match semantics

For every leaf identifier in the rendered transaction:

- **Payment-bearing field** (`body.inputs.*.resolved.address`, `body.outputs.*.address`, withdrawal addresses, certificate addresses):
  - For each address rename rule whose target matches (per `MatchFull` or `MatchPayment`), render the rule's `name:` in place of the bech32.
  - Multiple matching rules: *first occurrence in the YAML file wins* (see data-model.md "Conflict Resolution").
  - No matching rule: render the bech32 verbatim.
- **Script-hash field** (`body.scriptHashes.*`, `witness.scripts.*.hash`, `referenceScripts.*.hash`):
  - For each script rename rule whose `key:` equals the rendered hash, render the rule's `name:`.
  - No matching rule: render the hash verbatim.

Substitution is *best-effort*: an unmatched identifier is never an error and never causes the surrounding structural element to be omitted.

## Example

```yaml
version: 1
collapse:
  - name: "Swap output"
    at: body.outputs
    match:
      required:
        - datum.fields.0   # counterparty
        - datum.fields.1   # asset
rename:
  - kind: address
    key: addr1q9treasury…
    name: "amaru-treasury"
    match: payment
  - kind: address
    key: addr1q8geniusyield…
    name: "genius-yield-pool"
    # match: payment (default)
  - kind: script
    key: 9c2e7e15a4c1b2…
    name: "amaru.swap.v1"
```

With this file, an Amaru treasury swap transaction renders each swap output as the named `Swap` shape (collapse), with the counterparty slot showing `"genius-yield-pool"`, the asset slot showing the raw value (no rule, verbatim), and the swap-validator reference in the witness set showing `"amaru.swap.v1"`.

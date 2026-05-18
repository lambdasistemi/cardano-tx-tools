# Quickstart: tx-inspect

**Branch**: `032-tx-inspect` | **Date**: 2026-05-18

Phase 1 of `/speckit.plan`. Operator-facing quick path that proves the
P1 user story end-to-end. This file is the human-readable companion to
the formal contracts; the canonical user docs land in `docs/tx-inspect.md`
in slice S5.

## Prerequisites

- A built `tx-inspect` binary (`cabal build exe:tx-inspect -O0`, or a release artifact from `lambdasistemi/cardano-tx-tools`).
- A Conway transaction in CBOR form (hex-encoded file or stdin).
- *(Optional)* A rewriting-rules YAML file. Without one, `tx-inspect` renders the transaction verbatim.
- *(Optional)* Resolver flags (`--n2c-socket-path` for local cardano-node access, `--web2-…` for Blockfrost-compatible HTTP endpoints) — without them, body input resolution is skipped and inputs render as unresolved txin references.

## 1. Verbatim render (no rules, no resolver)

```bash
tx-inspect path/to/tx.cbor.hex
```

Output is the same structural tree `tx-diff` would render for one side of a diff, with raw hashes inline.

## 2. Collapse-only

Use the same collapse-rules YAML you already feed to `tx-diff`:

```bash
tx-inspect path/to/tx.cbor.hex --rules path/to/collapse.yaml
```

The output collapses repeated structural skeletons (e.g. swap outputs) into named shapes that expose only per-instance variable slots. Raw hashes inside the exposed slots remain verbatim.

## 3. Rename-only

```yaml
# rename-only.yaml
version: 1
rename:
  - kind: address
    key: addr1q9treasury…
    name: "amaru-treasury"
  - kind: script
    key: 9c2e7e15a4c1b2…
    name: "amaru.swap.v1"
```

```bash
tx-inspect path/to/tx.cbor.hex --rules rename-only.yaml
```

The structural shape is unchanged (no collapse), but every leaf identifier matched by a `RenameRule` appears under its book name. Unknown identifiers render verbatim.

## 4. The P1 path: Amaru treasury swap, both stages

Once `rules/amaru-treasury.yaml` ships (S4), the operator command is:

```bash
tx-inspect path/to/amaru-swap-tx.cbor.hex \
    --rules rules/amaru-treasury.yaml \
    --n2c-socket-path /run/cardano-node/node.socket
```

Each swap output appears collapsed into the named `Swap` shape, with the counterparty, asset, and script slots showing their address-book names instead of raw hashes.

## 5. Shared substrate proof

The same rules file feeds `tx-diff`:

```bash
tx-diff swap-1.cbor.hex swap-2.cbor.hex --rules rules/amaru-treasury.yaml
```

Each side of the diff applies collapse + rename identically. The diff output's per-side text equals the corresponding `tx-inspect` output byte-for-byte — that is the shared-substrate property the feature ships.

## 6. `--version`, `--help`, no-update env var

```bash
tx-inspect --version          # → "tx-inspect <semver>" on stdout, exit 0
tx-inspect --help             # → usage on stdout, exit 0
TX_INSPECT_NO_UPDATE_CHECK=1 tx-inspect …    # suppress the upgrade banner
```

These match the per-exe pattern shipped by the four pre-existing CLIs.

## 7. Exit codes

| Code | Meaning |
|---|---|
| 0   | Success. Rendered to stdout. |
| 1   | Input error (file not found, CBOR decode failure, malformed `--rules` YAML, …). Diagnostic on stderr. |
| 2   | CLI flag error (e.g. missing required positional). |

The renderer itself never raises a runtime error on an unknown identifier — rename is best-effort, never a failure.

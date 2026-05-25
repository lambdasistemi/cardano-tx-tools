# tx-lattice

`tx-lattice` is a thin Bash wrapper around [`tx-graph`](tx-graph.md)
that resolves a batch of mainnet / testnet Conway transactions —
plus their direct inputs — into one canonical Turtle file per tx,
ready to be queried as a single graph through SPARQL or projected
through [`tx-view`](tx-view.md).

It is shipped as a script under `scripts/tx-lattice` rather than as
a packaged executable: a real Haskell binary that does the same job
will follow, but the wrapper is small enough to read end-to-end and
unblocks the lattice-of-transactions workflows today.

## What it does

Given a list of transaction ids and an operator
[rewriting-rules](rewriting-rules.md) file, for each tx it writes
`OUT_DIR/<txid>.ttl` containing two layers:

1. **Body emit** — the canonical Turtle that `tx-graph --rules
   RULES --tx <tx.cbor>` produces (operator-entity overlay, body
   decomposition, blueprint-decoded datums + redeemers, address
   decompositions).
2. **Resolved-input bridges** — one `_:resolved_input<N>` bnode per
   input of the tx, carrying the parent UTxO's `cardano:atAddress`
   (bech32) and `cardano:lovelace`, plus the parent
   `cardano:fromParentTxId` / `cardano:fromParentIndex` and
   per-role flags (`cardano:isReferenceInput`,
   `cardano:isCollateralInput`). Each input bnode is bridged to its
   resolved twin via `cardano:resolvedTo`, the same predicate
   `tx-graph` would emit had it been given a UTxO file or N2C
   socket directly.

The inputs come pre-resolved in a single Blockfrost API call per
tx (`/txs/<hash>/utxos`) — one HTTP round-trip per tx, two if you
count the CBOR fetch, regardless of how many inputs that tx has.

## Quickstart

```bash
nix build .#tx-graph

export BLOCKFROST_PROJECT_ID=mainnet...

./scripts/tx-lattice \
  --rules rules.yaml \
  --out-dir ./out \
  --network mainnet \
  18d57a4f3094228a05c4d9b04ac41ad07f97c11a3cfff8c30b7d7f902c2306c0 \
  e7e7c6c5d2bd84ac3e7e7ad8d40f86f6e51e9a4b9c3c1a8b9e7e7c6c5d2bd84a
```

This writes `out/18d57a4f...c0.ttl` and `out/e7e7c6c5...4a.ttl`.

Then project the first one through a packaged view:

```bash
nix build .#tx-view
./result/bin/tx-view --graph ./out/18d57a4f...c0.ttl --view cli-tree
```

Or run a SPARQL query across all of them at once, with Apache Jena
pulled in transiently:

```bash
nix-shell -p apache-jena --run \
  "sparql $(printf -- '--data %s ' ./out/*.ttl) --query my-query.rq"
```

Jena re-labels per-file blank nodes uniquely, so multi-file
unions work without collision.

## CLI surface

```text
Usage:
  tx-lattice --rules rules.yaml --out-dir DIR \
             [--network mainnet|preprod|preview] \
             <txId1> <txId2> ... <txIdN>
```

- `--rules` is required and points to a [rewriting-rules
  YAML](rewriting-rules.md) file. The same file is fed to
  `tx-graph` for every tx in the batch — the operator-entity overlay
  is therefore identical across the lattice, which is what makes
  multi-tx SPARQL joins by address bnode (`cred_pay_<base>` /
  `<entity-slug>_s<stake>`) work. **CIP-57 blueprints also flow
  through this file**: the rules grammar has an optional
  `blueprints:` block whose entries pair a declared entity (whose
  script hash is set via `from-address:` or an explicit `script:`)
  with a path to a CIP-57 JSON blueprint, resolved relative to the
  rules file. There is no separate `--blueprint` flag on `tx-graph`
  or `tx-lattice` — every datum / redeemer that hits a registered
  script gets blueprint-decoded automatically, with consistent
  predicate names and `SchemaMap` per-entry triples across the
  whole batch.
- `--out-dir` is the destination directory (created if missing). One
  `<txid>.ttl` per input txid.
- `--network` selects the Blockfrost host. Default `mainnet`.

## Required env

| Variable                | Meaning                                                                 |
|-------------------------|-------------------------------------------------------------------------|
| `BLOCKFROST_PROJECT_ID` | Required. Mainnet / preprod / preview project id from blockfrost.io.    |
| `TX_GRAPH_EXE`          | Optional. Override path to `tx-graph`. Default search order: `$PATH`, then `result/bin/tx-graph`. |

## Dependencies

`curl`, `jq`, `xxd`, plus a built `tx-graph`. All are in the project
`nix develop` shell; outside it you provide them yourself.

## Status

Shell prototype. The expected next step is a packaged
`tx-lattice` executable that re-implements this loop in Haskell
against the same Blockfrost endpoints, with the same on-disk
contract — a directory of canonical-Turtle files keyed by txid.

## See also

- [tx-graph](tx-graph.md) — the per-tx emitter `tx-lattice` invokes.
- [tx-view](tx-view.md) — packaged views over canonical graphs.
- [rewriting-rules grammar](rewriting-rules.md) — the
  operator-entity overlay format both `tx-graph` and (via
  `tx-graph`) `tx-lattice` consume.

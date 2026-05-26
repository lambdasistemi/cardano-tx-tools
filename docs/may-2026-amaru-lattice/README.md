# May 2026 Amaru lattice query bundle

This directory contains the runnable SPARQL used by
`../may-2026-amaru-lattice.md`.

Each query is kept as a standalone file so the presentation can link to
the exact runnable source:

| File | Claim or diagnostic |
|------|---------------------|
| `queries/00-ada-conservation.rq` | ADA UTxO conservation sanity gate. |
| `queries/01-monthly-totals.rq` | Seed transaction count and fee totals. |
| `queries/02-usdm-output-addresses.rq` | USDM output addresses by amount. |
| `queries/03-ada-role-flow.rq` | ADA input/output flow by ledger role. |
| `queries/04-required-signer-distribution.rq` | Required signer count distribution. |
| `queries/05-vendor-payment-overlay.rq` | CAG payee output joined to vendor attestations. |
| `queries/06-disbursement-candidates.rq` | Structural contingency-to-network_compliance disbursement candidates. |
| `queries/07-usdm-role-flow.rq` | USDM input/output flow by ledger role. |
| `queries/08-swap-v2-consumers.rq` | Transactions consuming swap.v2 UTxOs. |
| `queries/09-reference-input-reuse.rq` | Hot reference-input reuse. |
| `queries/10-scoop-output-candidates.rq` | Output candidates from the 9-order swap.v2 consumer. |
| `queries/11-network-compliance-usdm-residual.rq` | End-of-seed-set network_compliance USDM residual. |
| `queries/12-seed-input-resolution-cardinality.rq` | Every seed spending input resolves exactly once. |
| `queries/13-seed-value-conservation-by-asset.rq` | Per-asset conservation over resolved seed inputs. |
| `queries/14-network-compliance-terminal-state.rq` | Graph-derived terminal UTxO state for network_compliance. |
| `queries/15-network-compliance-live-diff.rq` | Row-level diff between graph terminal state and a live-node overlay. |
| `queries/16-network-compliance-live-summary.rq` | Summary diff between graph terminal state and a live-node overlay. |

Run a query across a generated closure directory with Apache Jena:

```bash
export BLOCKFROST_PROJECT_ID=mainnet...
export TX_GRAPH_EXE="$(nix develop --quiet -c cabal list-bin exe:tx-graph -O0)"

scripts/tx-lattice \
  --rules rules/amaru-treasury.yaml \
  --out-dir closure \
  --network mainnet \
  --depth 1 \
  $(tr '\n' ' ' < docs/may-2026-amaru-lattice/seed-txs.txt)

nix-shell -p apache-jena --run \
  "sparql $(printf -- '--data %s ' closure/*.ttl) \
          --data docs/may-2026-amaru-lattice/overlay.ttl \
          --query docs/may-2026-amaru-lattice/queries/00-ada-conservation.rq"
```

The queries assume current canonical `tx-graph` output: every
transaction has `cardano:hasTxId/cardano:bytesHex`, every output has
`cardano:hasIndex`, and every `from-address` entity in the rules
overlay emits `cardano:bech32` with its `rdfs:label`. That lets the
queries JOIN through graph facts instead of carrying a separate
address map.

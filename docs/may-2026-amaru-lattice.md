# Amaru Treasury — May 2026 SPARQL Presentation

Twenty-one real SPARQL queries running over a real on-chain lattice built
end-to-end from `tx-graph` + `tx-lattice` + Apache Jena.

- Seed batch — the 30 user-named txs of May 2026 (3 disbursements + 5
  reorganize + 20 swap orders + 1 swap-cancel + 1 scoop dive).
- Closure — fetched from Blockfrost via `/txs/<hash>/cbor` *only*
  (no `/utxos`, no `/inputs`, no `/outputs`). Every input in a seed
  tx points at a parent UTxO; the parent's CBOR is fetched too so
  the JOIN target lives in the same graph. Depth = 1 → 71 parents.
- Emission — latest `tx-lattice` performs the closure walk in two
  passes and emits seed transactions with `tx-graph --closure-dir`, so
  spending redeemers can be decoded using the parent outputs already in
  the closure.
- Total lattice size = **30 seeds + 71 parents = 101 txs**, each in
  its own canonical Turtle file under `closure/<txid>.ttl`.
- State-audit boundary — Queries 14-16 extend the loaded graph with the
  network_compliance address history through the live snapshot boundary
  (block 13,467,438; slot 188,217,701). The 101-tx seed closure is enough
  for seed-flow questions; the final UTxO proof needs every transaction
  that can produce or spend a network_compliance output before that
  boundary.
- USDM accounting boundary — Queries 17-20 turn that complete
  network_compliance graph into a user-facing proof: the treasury starts
  with 0 USDM, receives 425,131.618692 USDM from swaps, pays 418,750 USDM
  to the CAG payee bridge, and retains 6,381.618692 USDM with zero
  accounting gap.
- Operator rules — `rules.yaml` carries on-chain entities, off-chain
  vendors, IPFS-anchored attestations, and CIP-57 blueprints.
- Engine — Apache Jena 5.6.0 `sparql` CLI.

```mermaid
flowchart LR
  blockfrost[Blockfrost CBOR API]
  txgraph[tx-graph]
  rules[rules.yaml]
  closure[closure directory]
  seeds[30 seed txs]
  parents[71 parent txs]
  history[network_compliance address history]
  live[Live UTxO snapshot]
  jena[Apache Jena]
  answers[SPARQL answers]
  final[Final-state proof]

  blockfrost -->|CBOR only| txgraph
  rules -->|entities blueprints attestations| txgraph
  txgraph -->|Turtle per tx| closure
  closure --> seeds
  closure --> parents
  parents -->|resolves inputs| seeds
  history -->|CBOR only| txgraph
  closure --> jena
  jena --> answers
  jena --> final
  live --> final
```

## Runnable Query Files

The demo rule source and query sources are standalone files. These
links are the single-file query demos used by the rendered page:

Rules source: [`rules.yaml`](may-2026-amaru-lattice/rules.yaml)

| Demo | Explanation | Runnable query |
|------|-------------|----------------|
| Query 0 — ADA conservation | [`what / why / how`](may-2026-amaru-lattice/queries/00-ada-conservation.md) | [`queries/00-ada-conservation.rq`](may-2026-amaru-lattice/queries/00-ada-conservation.rq) |
| Query 1 — Monthly totals | [`what / why / how`](may-2026-amaru-lattice/queries/01-monthly-totals.md) | [`queries/01-monthly-totals.rq`](may-2026-amaru-lattice/queries/01-monthly-totals.rq) |
| Query 2 — Treasury USDM payees | [`what / why / how`](may-2026-amaru-lattice/queries/02-usdm-output-addresses.md) | [`queries/02-usdm-output-addresses.rq`](may-2026-amaru-lattice/queries/02-usdm-output-addresses.rq) |
| Query 3 — ADA role flow | [`what / why / how`](may-2026-amaru-lattice/queries/03-ada-role-flow.md) | [`queries/03-ada-role-flow.rq`](may-2026-amaru-lattice/queries/03-ada-role-flow.rq) |
| Query 4 — Required signer distribution | [`what / why / how`](may-2026-amaru-lattice/queries/04-required-signer-distribution.md) | [`queries/04-required-signer-distribution.rq`](may-2026-amaru-lattice/queries/04-required-signer-distribution.rq) |
| Query 5 — Vendor-payment overlay | [`what / why / how`](may-2026-amaru-lattice/queries/05-vendor-payment-overlay.md) | [`queries/05-vendor-payment-overlay.rq`](may-2026-amaru-lattice/queries/05-vendor-payment-overlay.rq) |
| Query 6 — Disbursement candidates | [`what / why / how`](may-2026-amaru-lattice/queries/06-disbursement-candidates.md) | [`queries/06-disbursement-candidates.rq`](may-2026-amaru-lattice/queries/06-disbursement-candidates.rq) |
| Query 7 — USDM role flow | [`what / why / how`](may-2026-amaru-lattice/queries/07-usdm-role-flow.md) | [`queries/07-usdm-role-flow.rq`](may-2026-amaru-lattice/queries/07-usdm-role-flow.rq) |
| Query 8 — Sundae V3 order consumers | [`what / why / how`](may-2026-amaru-lattice/queries/08-sundae-v3-order-consumers.md) | [`queries/08-sundae-v3-order-consumers.rq`](may-2026-amaru-lattice/queries/08-sundae-v3-order-consumers.rq) |
| Query 9 — Reference-input reuse | [`what / why / how`](may-2026-amaru-lattice/queries/09-reference-input-reuse.md) | [`queries/09-reference-input-reuse.rq`](may-2026-amaru-lattice/queries/09-reference-input-reuse.rq) |
| Query 10 — Sundae V3 scoop output candidates | [`what / why / how`](may-2026-amaru-lattice/queries/10-sundae-v3-scoop-output-candidates.md) | [`queries/10-sundae-v3-scoop-output-candidates.rq`](may-2026-amaru-lattice/queries/10-sundae-v3-scoop-output-candidates.rq) |
| Query 11 — Network compliance USDM residual | [`what / why / how`](may-2026-amaru-lattice/queries/11-network-compliance-usdm-residual.md) | [`queries/11-network-compliance-usdm-residual.rq`](may-2026-amaru-lattice/queries/11-network-compliance-usdm-residual.rq) |
| Query 12 — Seed input resolution cardinality | [`what / why / how`](may-2026-amaru-lattice/queries/12-seed-input-resolution-cardinality.md) | [`queries/12-seed-input-resolution-cardinality.rq`](may-2026-amaru-lattice/queries/12-seed-input-resolution-cardinality.rq) |
| Query 13 — Seed value conservation by asset | [`what / why / how`](may-2026-amaru-lattice/queries/13-seed-value-conservation-by-asset.md) | [`queries/13-seed-value-conservation-by-asset.rq`](may-2026-amaru-lattice/queries/13-seed-value-conservation-by-asset.rq) |
| Query 14 — Network compliance terminal state | [`what / why / how`](may-2026-amaru-lattice/queries/14-network-compliance-terminal-state.md) | [`queries/14-network-compliance-terminal-state.rq`](may-2026-amaru-lattice/queries/14-network-compliance-terminal-state.rq) |
| Query 15 — Network compliance live diff | [`what / why / how`](may-2026-amaru-lattice/queries/15-network-compliance-live-diff.md) | [`queries/15-network-compliance-live-diff.rq`](may-2026-amaru-lattice/queries/15-network-compliance-live-diff.rq) |
| Query 16 — Network compliance live summary | [`what / why / how`](may-2026-amaru-lattice/queries/16-network-compliance-live-summary.md) | [`queries/16-network-compliance-live-summary.rq`](may-2026-amaru-lattice/queries/16-network-compliance-live-summary.rq) |
| Query 17 — Network compliance USDM accounting | [`what / why / how`](may-2026-amaru-lattice/queries/17-network-compliance-usdm-accounting.md) | [`queries/17-network-compliance-usdm-accounting.rq`](may-2026-amaru-lattice/queries/17-network-compliance-usdm-accounting.rq) |
| Query 18 — Beneficiary USDM payments | [`what / why / how`](may-2026-amaru-lattice/queries/18-beneficiary-usdm-payments.md) | [`queries/18-beneficiary-usdm-payments.rq`](may-2026-amaru-lattice/queries/18-beneficiary-usdm-payments.rq) |
| Query 19 — Swap receipts and rates | [`what / why / how`](may-2026-amaru-lattice/queries/19-swap-receipts-and-rates.md) | [`queries/19-swap-receipts-and-rates.rq`](may-2026-amaru-lattice/queries/19-swap-receipts-and-rates.rq) |
| Query 20 — Terminal USDM provenance | [`what / why / how`](may-2026-amaru-lattice/queries/20-terminal-usdm-provenance.md) | [`queries/20-terminal-usdm-provenance.rq`](may-2026-amaru-lattice/queries/20-terminal-usdm-provenance.rq) |

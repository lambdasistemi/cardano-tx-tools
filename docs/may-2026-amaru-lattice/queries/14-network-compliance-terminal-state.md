# Query 14 - Network Compliance Terminal State

Runnable SPARQL: [`14-network-compliance-terminal-state.rq`](14-network-compliance-terminal-state.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query computes the graph-derived terminal UTxO set for the
network_compliance treasury address. It lists outputs at that address
whose `(txid, index)` is not consumed by any transaction in the loaded
graph.

For each terminal UTxO, it reports tx id, output index, lovelace, and
USDM quantity.

## Why

This is the core state-reconstruction query. The user-facing claim is:
given a start graph and all transactions in the interval, we should be
able to recompute the ending state. If this graph-derived terminal set
does not match the expected current state at the chosen boundary, that
is a bug in graph completeness, graph emission, or the boundary
definition.

It is stricter than Query 11. Query 11 only asks about USDM-bearing seed
outputs at network_compliance that are not spent by another seed.
Query 14 asks for every terminal network_compliance output visible in
the loaded graph, regardless of whether it was a seed output or a parent
output.

## How

The query resolves the network_compliance address and USDM asset id from
`rules.yaml`. It scans all loaded transactions, not only seeds, for
outputs at that address.

For each candidate output, it rejects any output whose `(txid, index)`
appears as an input reference anywhere in the loaded graph:

```sparql
FILTER NOT EXISTS {
  ?spendingTx cardano:hasInput ?input .
  ?input cardano:fromTxOutRef ?ref .
  ?ref cardano:hasTxId/cardano:bytesHex ?txId ;
       cardano:hasIndex ?ix .
}
```

That is the UTxO-set rule expressed directly in SPARQL: an output is
unspent in the graph if no input in the graph spends it.

The optional asset branch sums USDM on each terminal output. Outputs
without USDM remain in the result with a zero USDM aggregate. This makes
the result suitable for comparing both ADA and USDM state.

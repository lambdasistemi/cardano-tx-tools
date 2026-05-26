# Query 02 - USDM Output Addresses

Runnable SPARQL: [`02-usdm-output-addresses.rq`](02-usdm-output-addresses.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query lists every address that received USDM from a seed
transaction and sums the USDM quantity per address. When the address is
declared in `rules.yaml`, the query also returns the human-readable
label emitted by the graph.

It answers a direct question: "Where did the USDM outputs go in this
May batch?" It does not yet decide whether a destination is final, change,
pool inventory, or an intermediate script. It only reports output-side
USDM created by the seed transactions.

## Why

This is the first USDM-specific lens. It quickly separates the large
destinations: network compliance change, CAG payee, SundaeSwap pool or
settlement outputs, and any unlabelled wallet outputs.

The query is useful because it avoids narrative mistakes. Seeing USDM at
network_compliance in this output table is not a loss; it can be change
or terminal residual. Later queries compare input and output sides, and
Queries 11, 14, 15, and 16 answer the terminal-state question.

## How

The query first finds the `usdm` entity emitted from `rules.yaml` and
reads its `cardano:hasIdentifier/cardano:bytesHex` asset id. This keeps
the SPARQL independent of hard-coded policy and asset-name literals.

It then scans seed outputs, follows `cardano:hasAssetValue` through the
RDF list of multi-asset quantities, and keeps only assets whose
identifier matches USDM. For each matching output, it reads the output
address via `cardano:atAddress/cardano:bech32`.

An optional join maps the bech32 address back to a rules entity:

```sparql
?labelEntity cardano:bech32 ?outputBech32 ;
             rdfs:label ?knownLabel .
```

That join is why the rendered answer can show both the concrete address
and an operator label where one exists. Unknown addresses are kept as
`unlabelled`, which is important for auditability; the query does not
drop facts just because the operator did not pre-name an address.

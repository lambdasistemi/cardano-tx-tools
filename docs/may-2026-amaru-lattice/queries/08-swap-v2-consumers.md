# Query 08 - Swap.v2 Consumers

Runnable SPARQL: [`08-swap-v2-consumers.rq`](08-swap-v2-consumers.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query finds seed transactions that consume UTxOs controlled by the
`amaru.swap.v2` script. It reports the seed transaction id, how many
swap.v2 inputs it consumed, how many outputs it created, and how many of
those outputs are not swap.v2 outputs.

The query is deliberately named "consumer" rather than "scoop". A batch
scoop and a swap cancel can both consume swap.v2 UTxOs; this query finds
the structural pattern first and leaves interpretation to later review.

## Why

The demo needs to prove that the graph can identify the 9-order scoop
without decoding every swap-order datum. Consumption of script UTxOs is
already enough to identify transactions that interacted with the swap.v2
contract.

This is also a guard against overclaiming. A transaction that consumes
one swap.v2 UTxO might be a cancel or a small settlement, not
necessarily the multi-order scoop the operator wants to inspect. The
`swapV2InputsConsumed` count gives the first ranking signal.

## How

The inner query resolves the swap.v2 payment credential from
`rules.yaml`:

```sparql
?swapV2 rdfs:label "amaru.swap.v2" ;
        cardano:hasIdentifier/cardano:bytesHex ?swapV2Hash .
```

It then walks every seed input to its parent output. If the parent
output address has a payment credential whose identifier is the swap.v2
hash, the seed transaction consumed a swap.v2 UTxO.

The outer query counts all outputs created by that seed transaction and
uses a `FILTER NOT EXISTS` block to count outputs whose address is not
controlled by the same swap.v2 payment credential. That helps separate
transactions that merely roll script state forward from transactions
that produce settlement outputs to other roles.

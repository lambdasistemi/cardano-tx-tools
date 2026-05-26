# Query 09 - Reference-Input Reuse

Runnable SPARQL: [`09-reference-input-reuse.rq`](09-reference-input-reuse.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query lists the most reused reference inputs in the May seed set.
For each referenced `(parent txid, output index)`, it counts how many
distinct seed transactions used that output as a reference input.

It is a script and infrastructure usage view, not a value-flow view.
Reference inputs are read-only; they do not spend the referenced UTxO.

## Why

Treasury and swap transactions often rely on published reference scripts
or shared data UTxOs. A small number of hot reference inputs should
appear across many transactions. Seeing that reuse proves the graph
captures CIP-31 reference-input edges and can expose shared
infrastructure dependencies.

This also helps explain transaction size and fee patterns. Transactions
with multiple reference inputs and script interactions tend to be more
expensive than simple wallet payments.

## Diagram

```mermaid
flowchart LR
  seeds[Seed txs]
  refs[Reference inputs]
  targets[Referenced outputs]
  group[Group by target]
  hot[Most reused refs]

  seeds --> refs
  refs --> targets
  targets --> group
  group --> hot
```

## How

The query scans seed transactions with `cardano:hasReferenceInput`. It
follows each reference input to `cardano:fromTxOutRef`, then reads the
referenced transaction id and output index:

```sparql
?refTxOutRef cardano:hasTxId/cardano:bytesHex ?parentTxId ;
             cardano:hasIndex ?ix .
```

It groups by `(parentTxId, ix)` and counts distinct seed transactions
using each reference. The `LIMIT 5` keeps the result focused on the
hot entries that explain most of the month's reference-script reuse.

If this query returned no rows for a script-heavy month, that would
suggest the graph failed to emit reference inputs or the seed set does
not include the expected script transactions.

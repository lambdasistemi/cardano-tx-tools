# Query 16 - Network Compliance Live Summary

Runnable SPARQL: [`16-network-compliance-live-summary.rq`](16-network-compliance-live-summary.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query is the aggregate form of Query 15. It compares graph-derived
terminal totals with live-node totals for network_compliance and reports
the count, lovelace, and USDM gap.

It does not identify individual mismatching UTxOs. It tells whether the
two state views balance at the summary level.

## Why

The row-level diff is best for debugging. The summary is best for a
quick correctness gate and for presentation. A zero lovelace gap and
zero USDM gap means the graph-derived terminal state and live overlay
agree in aggregate.

This is useful after fixing row-level mismatches. Once Query 15 returns
no rows, Query 16 should also show zero gaps. If Query 16 shows a gap,
use Query 15 to find the exact rows causing it.

## How

The query contains two subqueries.

The graph subquery recomputes the terminal network_compliance UTxO set:
all outputs at the network_compliance address for which no loaded input
spends the same `(txid, index)`. It counts those terminal outputs and
sums lovelace and USDM.

The live subquery scans the `live:CurrentUtxo` overlay and counts/sums
the live rows.

The final projection computes:

```text
liveLovelace - graphTerminalLovelace
liveUsdm - graphTerminalUsdm
```

Positive gaps mean the live overlay has more value than the graph's
terminal set. Negative gaps mean the graph terminal set has more value
than the live overlay. A correct complete graph at the same boundary
should produce zero for both gaps.

# Query 19 - Swap Receipts And Rates

Runnable SPARQL: [`19-swap-receipts-and-rates.rq`](19-swap-receipts-and-rates.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query lists each SundaeSwap V3 order consumer that returned USDM to
the network_compliance treasury. For each swap receipt it reports:

- the consumer transaction id,
- the number of consumed order inputs,
- the lovelace locked in those order inputs,
- the USDM returned to the treasury,
- the realized USDM-per-ADA rate in parts per million.

`245000` in the rate column means `0.245000 USDM / ADA`.

## Why

The accounting query says the treasury received `425,131.618692` USDM
from swaps. Query 19 shows the individual swap receipts and their
realized rates, so the aggregate is inspectable instead of a black-box
sum.

This is also a rate sanity check. The realized rates cluster around the
submitted floor and the actual scoop outcomes; outliers are visible by
sorting or filtering the returned rows.

## Diagram

```mermaid
flowchart LR
  orders[Sundae V3 order outputs]
  consumers[Order consumer txs]
  receipts[USDM outputs to network_compliance]
  rate[received USDM / order lovelace]
  table[Swap-rate rows]

  orders --> consumers
  consumers --> receipts
  orders --> rate
  receipts --> rate
  rate --> table
```

## How

The query has two subqueries joined by transaction node.

The first subquery finds producer transactions that consume outputs at
the SundaeSwap V3 order script hash. It sums the lovelace at those
consumed order UTxOs and records the consumed order references.

The second subquery finds USDM outputs from the same producer
transactions back to the network_compliance treasury address.

The final projection computes:

```text
round(receivedUsdm * 1,000,000 / orderLovelace)
```

Because both lovelace and USDM base units have six decimal places, that
ratio is USDM per ADA in parts per million.

## SPARQL

```sparql
--8<-- "docs/may-2026-amaru-lattice/queries/19-swap-receipts-and-rates.rq"
```

## Result

This summary is computed from the 51 rows returned by the query. USDM
quantities are base units; rates are parts per million USDM per ADA.

| rows | totalOrderLovelace | totalReceivedUsdm | minRatePpm | maxRatePpm | weightedRatePpm |
|---:|---:|---:|---:|---:|---:|
| 51 | 1655434240000 | 425131618692 | 243397 | 263640 | 256810 |

Selected rows from the same result set:

| swapTxId | orderInputs | orderLovelace | receivedUsdm | realizedUsdmPerAdaPpm | orderRefs |
|---|---:|---:|---:|---:|---|
| `26542f223ee27990e35555a7a328299c61e6f802b075b1e00b01befcdb597871` | 9 | 38146539249 | 10056971059 | 263640 | `3d1a9c0033b36eb911a68bba9c4d2e6216077356576ec7356399d9d0e5060afe#0`, `3b6c77dcad3365b4b3b4a4dc3d874b13558440a24af7917e65be93ef42ad8769#0`, `7e972848364a8869a54ad433f1e5115733e1f3c7e64fefd675f329a6ba378bd9#0`, `b9c1741359470cad8b267a6549ddb703aeb9ac9bdab5e72719d31dc3645fc1fd#0`, `7ffdc2761bf058cf05bafcaa0878e9f4795e95cba74da3e022acae8b49427d97#0`, `22e914892e83c22e19514937914ca32a0c059f9d1c5b555429edde0ea3406ae4#1`, `4ef9201c7a117def4e636a204ca40a8fce36ee5553048dcbcf7b04c38d164428#0`, `846f454977c9e4ca3a05069b837d4bae692f5cffc69925dc71e2f7b210e3aaa7#0`, `6e2b682763438c391d7b05c8a96ff1b421bde3617900b04142bbfc118227e104#0` |
| `68a1277af23755376967e788752c603044f45ea0d99220b3b5dfc7d617642b6b` | 1 | 20411443266 | 5011215241 | 245510 | `9f119393a85bb9aa0c94f8c649288dabb956b88dcbe055b10e741a2237123420#0` |
| `cda0126e9ea7b336bbb338d2bfc7622a41b584e3bebc33c9c320e8895b9bc082` | 2 | 85783609 | 20879498 | 243397 | `10a5c1dafe7dd8d4ab680e35dc53b8b550da90bea55f2c758f36474064f2e598#1`, `10a5c1dafe7dd8d4ab680e35dc53b8b550da90bea55f2c758f36474064f2e598#0` |

The full runnable query returns all 51 swap receipt rows with their
order references.

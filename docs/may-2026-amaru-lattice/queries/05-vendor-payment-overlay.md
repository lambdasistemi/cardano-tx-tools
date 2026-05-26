# Query 05 - Vendor-Payment Overlay

Runnable SPARQL: [`05-vendor-payment-overlay.rq`](05-vendor-payment-overlay.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query connects on-chain USDM movement to off-chain vendor context.
It finds the USDM sent to the CAG payee address and joins that bridge
output to vendors and IPFS attestations declared in `rules.yaml`.

The result is not just "USDM reached this address". It says which
off-chain vendor entities are paid through that address and which
invoice, contract, or review artefacts are attached to those entities.

## Why

On-chain transactions can prove value movement, but they cannot by
themselves explain why a bridge address matters. The rules overlay gives
the graph enough operator context to answer a reviewer question:
"What vendor evidence is this payment connected to?"

This page is also the post-#105 simplification. The demo no longer needs
an extra `overlay.ttl` side input. `tx-graph --rules` emits the
off-chain facts as graph triples:

```text
cardano:OffChainEntity
cardano:paidVia
cardano:Attestation
cardano:attests
cardano:ipfs
```

That means the same rule source used to label on-chain addresses also
anchors the off-chain explanation.

## Diagram

```mermaid
flowchart LR
  network[Network compliance]
  cag[CAG payee]
  antithesis[Antithesis vendor]
  castellum[Castellum vendor]
  invoiceA[Invoice INV 635]
  contract[Contract]
  invoiceC[Invoice 3508]
  review[Cycle review]

  network -->|USDM output| cag
  antithesis -->|paid via| cag
  castellum -->|paid via| cag
  invoiceA -->|attests| antithesis
  contract -->|attests| castellum
  invoiceC -->|attests| castellum
  review -->|attests| castellum
```

## How

The subquery finds the bridge entity by label:

```sparql
?bridgeEntity rdfs:label "amaru.cag-payee" ;
              cardano:bech32 ?bridgeBech32 .
```

It also pins the full on-chain USDM asset id in a `VALUES` block. It
then scans seed outputs at the bridge address, follows the multi-asset
RDF list, and sums USDM quantity.

The outer query joins vendors to the same bridge entity:

```sparql
?vendor cardano:paidVia ?bridgeEntity .
```

Then it joins attestations to those vendors:

```sparql
?attestation cardano:attests ?vendor ;
             cardano:ipfs ?ipfs .
```

The important correctness property is that the bridge amount and the
vendor evidence are not stitched together by a presentation script. They
are joined inside SPARQL over one emitted graph.

## SPARQL

```sparql
PREFIX cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#>
PREFIX rdfs:    <http://www.w3.org/2000/01/rdf-schema#>
PREFIX rdf:     <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

SELECT ?vendor ?vendorLabel ?attestation ?attestationLabel ?ipfs ?usdmTotalAtBridge
WHERE {
  {
    SELECT ?bridgeEntity (SUM(?qty) AS ?usdmTotalAtBridge)
    WHERE {
      ?bridgeEntity rdfs:label "amaru.cag-payee" ;
                    cardano:bech32 ?bridgeBech32 .
      VALUES ?usdmAssetId {
        "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad0014df105553444d"
      }

      ?seed cardano:hasLatticeRole "seed" ;
            cardano:hasOutput ?out .
      ?out cardano:atAddress/cardano:bech32 ?bridgeBech32 ;
           cardano:hasAssetValue/rdf:rest*/rdf:first ?asset .
      ?asset cardano:hasIdentifier/cardano:bytesHex ?usdmAssetId ;
             cardano:quantity ?qty .
    }
    GROUP BY ?bridgeEntity
  }
  ?vendor cardano:paidVia ?bridgeEntity .
  ?attestation cardano:attests ?vendor ;
               cardano:ipfs ?ipfs .
  OPTIONAL { ?vendor rdfs:label ?vendorLabel . }
  OPTIONAL { ?attestation rdfs:label ?attestationLabel . }
}
ORDER BY ?vendor ?attestation

```

## Result

This table is the CSV result produced by Apache Jena over the May 2026 lattice. ADA quantities are lovelace; USDM quantities are base units.

| vendor | vendorLabel | attestation | attestationLabel | ipfs | usdmTotalAtBridge |
|---|---|---|---|---|---|
| https://lambdasistemi.github.io/cardano-tx-tools/fixtures/may-2026-amaru-lattice#amaru_antithesis | amaru.antithesis | b0 | Invoice INV-635 | ipfs://bafkreicnoadlgnc6cqxggxboho7yt532lkonxcusj3ndsxdnv5szyswyam | 418750000000 |
| https://lambdasistemi.github.io/cardano-tx-tools/fixtures/may-2026-amaru-lattice#amaru_castellum | amaru.castellum | b1 | May 2026 cycle review | ipfs://bafybeihdmnitrbu2oir3r2fefnpqy3bk7zdz42olzmltmxyt5xag4i2t5a | 418750000000 |
| https://lambdasistemi.github.io/cardano-tx-tools/fixtures/may-2026-amaru-lattice#amaru_castellum | amaru.castellum | b2 | Contract | ipfs://bafybeib3jef34ndw6oe24mkmifdvxe5jrv7ulh63rdllovyth27mqfj2da | 418750000000 |
| https://lambdasistemi.github.io/cardano-tx-tools/fixtures/may-2026-amaru-lattice#amaru_castellum | amaru.castellum | b3 | Invoice #3508 | ipfs://bafybeigy37ui2ikn7bim2vw6cojcbxkcndpjwh7cj5fv3vzs4cszezipxu | 418750000000 |

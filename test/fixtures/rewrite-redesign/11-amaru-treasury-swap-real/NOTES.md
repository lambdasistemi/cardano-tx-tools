# 11-amaru-treasury-swap-real — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Provenance

Mirrors mainnet tx
`5fc04113da630ec676a5a7a66d82f53c0e64527ee592c3e6c5e1dccad67732ea`.
See `test/fixtures/amaru-treasury-swap/swap-1.source.md`
(cardano-tx-tools) for the real on-chain provenance.

## Cross-leaf identity

The `amaru-treasury.network_compliance` script hash
(`fa6a58... fc8f3077`) appears in both the treasury-leftover
output's payment credential and, semantically, in each
swap-order's datum `recipient` field. The Turtle below pins the
shared identifier via a single bnode (`_:treasuryComplianceId`)
that both `PaymentCredential` instances reference; the future
#47 emitter must mint that node once under the
`cardano:hasIdentifier` `(leafType, bytesHex)` OWL key.

## Transaction body

2 inputs, 5 outputs, 1 collateral input.

## Inputs

- Input 1 — user wallet (96.8 ADA, also sources collateral).
- Input 2 — treasury (1_137_000 ADA).

## Outputs

- Outputs 1 & 2 — two swap-order chunks at the `amaru.swap.v2`
  script.
- Output 3 — treasury leftover (back at
  `amaru-treasury.network_compliance`).
- Outputs 4 & 5 — user payments back to `amaru.network-wallet`.

## Collateral

Sourced from the same user wallet.

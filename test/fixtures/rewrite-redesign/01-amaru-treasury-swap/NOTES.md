# 01-amaru-treasury-swap — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Story (044 Story 1)

Load-bearing P1 fixture — 33 SwapOrder UTxOs at the `amaru.swap.v2`
script settle into one USDM-bearing treasury output, with a small
ADA change output and a collateral input both sourced from the
user wallet. The 044 narrative pins the per-input `datum.recipient`
field to `amaru-treasury.network_compliance` (i.e. the same script
hash that also lives at `body.outputs[0].address.payment`) — the
cross-leaf identity reproducer for issue #43.

This structural slice surfaces the identity-bearing surface only:

- 34 inputs (33 swap-order + 1 network-wallet);
- 2 outputs (treasury + network-wallet change);
- 1 collateral input;
- a single `_:treasuryComplianceId` `Identifier` bnode shared by
  the `amaru-treasury.network_compliance` entity and the treasury
  output's `PaymentCredential` — the structural projection of the
  recipient cross-leaf identity that the future #47 emitter will
  extend with blueprint-decoded `datum.recipient` links from every
  swap-order input.

Body-data (per-input swap-order coin, the 95 USDM mint asset value,
the 0.85 ADA change coin, the 0.65 ADA fee in `expected.txt`) live
in `expected.txt` / the future #47 emitter, not in this structural
graph — matching the convention used by the merged B-side fixtures.

## Operator-declared entities

The script-hash values for `amaru-treasury.network_compliance`,
`amaru.swap-order`, and `amaru.swap.v2` mirror the real on-chain
bytes carried by the sibling `11-amaru-treasury-swap-real` fixture
so reviewers can spot the hypothetical-vs-real pairing at a glance;
the structural OWL key on `(leafType, bytesHex)` treats them as
the same identity.

The `amaru.network-wallet` credentials are synthetic placeholders
(this fixture's bech32 is hypothetical, not bech32-decodable to
the placeholder bytes), flagged with the `0101...` / `0202...`
prefix.

## Transaction body

34 inputs (33 swap-order at the `amaru.swap.v2` script + 1
network-wallet input), 2 outputs (treasury USDM-bearing + change),
1 collateral input. No certs/withdrawals/proposals/refs/mint.

## Swap-order inputs

Thirty-three swap-order inputs at `amaru.swap.v2`. Each input's
datum carries a `SwapOrder` record whose `recipient` field decodes
(via the future #47 emitter) to the same `_:treasuryComplianceId`
bnode pinned below — the structural graph models the INPUT count
here and leaves the datum-decode triples to #50/#47.

## Network-wallet input

Sources the fee and the collateral.

## Output 1

1.5 ADA + 95 USDM to `amaru-treasury.network_compliance`. The
`PaymentCredential` reuses the `_:treasuryComplianceId` bnode the
entity already declared, pinning the cross-leaf identity surface
from issue #43 at the structural level.

## Output 2

0.85 ADA change back to `amaru.network-wallet`.

## Collateral

Sourced from the same user wallet.

## Address decompositions

The treasury output's `PaymentCredential` and the
`amaru-treasury.network_compliance` entity share the same
`_:treasuryComplianceId` bnode (the #43 cross-leaf reproducer at
the structural surface); the swap-order address and the
`amaru.swap.v2` script entity share the same `_:swapOrderPaymentId`
bnode (the script-hash cross-reference at the witness/output
surface).

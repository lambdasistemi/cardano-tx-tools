# 07-vote-delegation — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Operator-declared entities

`alice` reuses the same 28-byte payment / stake key hashes as
`02-alice-bob-ada` and the same bnode targets used by
`06-stake-pool-delegation`.

`cardano-foundation-drep` is a single-leaf entity — a DRep
identified by its 28-byte DRep-key-hash, the lenient bech32
decoding of the CIP-129 form
`drep1y2v5h0g4qjqj9p6h9rp3z5lyqz3xczvqj5x3z7c7gj7nf2c52u7m3`.

The CIP-129 bech32 body is 29 bytes: a 1-byte header (`0x22`,
identifying a `DRepKey` credential) followed by the 28-byte
key-hash. The leaf's `bytesHex` pins the 28-byte tail; the header
byte's "DRepKey vs DRepScript" discriminator is carried by the
`leafType "DRepKey"` code instead, alongside `"PoolId"` (T018)
and the
`"PaymentKey"`/`"StakeKey"`/`"PaymentScript"`/`"StakeScript"`/`"AssetClass"`
leaf-type codes already in use by T015..T018.

## Certificate 1

`VoteDelegation`. Structurally identical to T018's
`StakeDelegation`: Phase A declares `cardano:hasCertificate` as
the body→cert property but does not (yet) declare a `Certificate`
class, so the blank node carries no `rdf:type`. The cert binds
two leaves:

- the delegator's stake credential (alice's stake-key) via
  `cardano:hasStakeCredential`, reusing the same
  `_:aliceCredStake` bnode emitted by the address decomposition
  below;
- the target DRep's 28-byte DRep-key-hash, surfaced as a bare
  `cardano:hasIdentifier` link to `_:cardanoFoundationDRepId` —
  Phase A has no `DRepCredential` class and the
  (`leafType "DRepKey"`, `bytesHex`) pair is sufficient to pin
  the DRep identity.

The 044 `AlwaysAbstain` sibling variant would produce a cert with
a `DRepAlwaysAbstain` delegatee carrying no
`cardano:hasIdentifier` link at all; that case is out of scope
for this fixture, which exercises the explicit-DRep arm only
(S07 module header).

## Address decompositions

Same bech32 + same identifier targets as
`02-alice-bob-ada` / `03` / `05` / `06`. The delegator's stake
credential bnode (`_:aliceCredStake`) is the same one bound by
the certificate above.

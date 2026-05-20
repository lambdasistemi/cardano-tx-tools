# 06-stake-pool-delegation — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Operator-declared entities

`alice` reuses the same 28-byte payment / stake key hashes as
`02-alice-bob-ada`.

`iog-pool-1` is a single-leaf entity — a stake pool identified
by its 28-byte pool-key-hash, the lenient bech32 decoding of
`pool1z22x50lqsrwent6en0llzzs32wadml78v300fl6yrqlqp9q5e07`.
Phase A vocab has no `PoolCredential` class, so the pool surfaces
as a bare `Identifier` with `leafType "PoolId"` — a new
leaf-type code alongside
`"PaymentKey"`/`"StakeKey"`/`"PaymentScript"`/`"StakeScript"`/`"AssetClass"`
already used by T015..T017.

## Certificate 1

`StakeDelegation`. Phase A declares `cardano:hasCertificate` as
the body→cert property but does not (yet) declare a `Certificate`
class, so the blank node carries no `rdf:type` — matching T017's
`hasWithdrawal` pattern. The cert binds two leaves structurally:

- the delegator's stake credential (alice's stake-key) via
  `cardano:hasStakeCredential`, reusing the same
  `_:aliceCredStake` bnode emitted by the address decomposition
  below;
- the target pool's 28-byte pool-key-hash, surfaced as a bare
  `cardano:hasIdentifier` link to `_:iogPool1Id` — Phase A has
  no `PoolCredential` class and the (`leafType "PoolId"`,
  `bytesHex`) pair is sufficient to pin the pool identity.

T019 (vote-delegation) follows the same convention with a `DRep`
leaf in place of the pool leaf.

## Address decompositions

Same bech32 + same identifier targets as
`02-alice-bob-ada` / `03` / `05`. The delegator's stake
credential bnode (`_:aliceCredStake`) is the same one bound by
the certificate above.

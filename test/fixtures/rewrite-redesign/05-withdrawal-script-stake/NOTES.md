# 05-withdrawal-script-stake — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Operator-declared entities

`alice` reuses the same 28-byte payment / stake key hashes as
`02-alice-bob-ada` — identical bech32 + identifier bytes.

`amaru-treasury.network_compliance` is a script-style base
address: both the payment and stake credentials are script
hashes. They surface as two distinct `Identifier` instances
with `leafType "PaymentScript"` / `"StakeScript"`. In this
particular address the on-chain payment-side and stake-side
script-hashes are the same 28-byte value, so both `Identifier`
instances carry an identical `bytesHex` but distinct
`leafType`s — matching the kmaps#53 `(leafType, bytesHex)` key.

The dot in the entity name is rewritten to an underscore in the
CURIE local-part (`:amaru-treasury_network_compliance`) to avoid
the Turtle `PN_LOCAL` trailing-dot trap; `rdfs:label` preserves
the operator-declared spelling.

## Output 1

51.825 ADA change back to alice (50 ADA goes to the withdrawal
target via the body `@withdrawals@` map, not via this output).

## Withdrawal 1

50 ADA claimed from a reward account whose stake credential is
the `amaru-treasury.network_compliance` stake script. Phase A
declares `cardano:hasWithdrawal` as a property but does not (yet)
declare a `Withdrawal` class, so the blank node carries no
`rdf:type`. It binds the reward-account stake credential via
`cardano:hasStakeCredential` — the same `_:amaruTreasuryCredStake`
bnode reused from the address decomposition below — pinning the
(`leafType "StakeScript"`, `bytesHex`) identity of the
reward-account holder. The withdrawn lovelace amount is body-data
and lives in `expected.txt` / the future #47 emitter, not in this
structural graph.

## Address decompositions

The `amaru-treasury.network_compliance` address is a script-script
base address; both credentials are script-hash and resolve to the
same decoded 28-byte hash (see entity block above).

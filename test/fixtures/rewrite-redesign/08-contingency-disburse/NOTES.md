# 08-contingency-disburse — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Operator-declared entities

`user-wallet` reuses the same 28-byte payment / stake key hashes
as alice in `02-alice-bob-ada` (entity IRI renamed; identifier
bytes unchanged); `recipient` reuses the same 28-byte payment /
stake key hashes as bob there.

The third entity, `amaru-treasury.contingency.account`, is a
script-style base address — both the payment and stake
credentials are script hashes — paralleling the
`amaru-treasury.network_compliance` precedent in T017
(`05-withdrawal-script-stake`). The two script-hash leaves
surface as two distinct `Identifier` instances with
`leafType "PaymentScript"` / `"StakeScript"`; in this particular
address the on-chain payment-side and stake-side script-hashes
are the same 28-byte value, so both `Identifier` instances carry
an identical `bytesHex` but distinct `leafType`s — matching the
kmaps#53 `(leafType, bytesHex)` key.

The dots in the entity name are rewritten to underscores in the
CURIE local-part (`:amaru-treasury_contingency_account`) to
avoid the Turtle `PN_LOCAL` trailing-dot trap; `rdfs:label`
preserves the operator-declared spelling.

## Transaction body

2 inputs, 2 outputs, 1 collateral input, 175_000 fee. This is
the first B-side fixture to populate the collateral field, so it
is also the first to surface `cardano:hasCollateralInput` on the
transaction blank node — the structural counterpart to
`cardano:hasInput` already used by T015..T019. Collateral inputs
share the `Input` class with body inputs (both carry
`cardano:resolvedTo` → `Output` → `atAddress`) and differ only
in the body→input property name that pins them. No certificates,
withdrawals, proposals, reference inputs, or mint entries.

## Inputs

Two UTxOs both held at the contingency self-script address (60 +
50 ADA on the 044 side; coin values are body-data and live in
`expected.txt` / the future #47 emitter, not in this structural
graph).

The `rules.yaml` collapse rule pins `resolved.address` in
`required:`, so the future emitter elides the per-input address
row in favour of a collapsed `@Input × 2@` header — that pinning
is the #43 reproducer trigger and is verified by the future #47
emitter against `expected.txt`, not here.

## Collateral input

First B-side encounter of `cardano:hasCollateralInput`. Phase A
declares this body→input property but does not (yet) declare a
`CollateralInput` class; the blank node carries the same `Input`
`rdf:type` as a body input and resolves the same way, via
`cardano:resolvedTo` → `Output` → `atAddress`. The collateral
`TxIn` bytes themselves are not inspected by the structural
goldens — only the count is — so the (collateral-input →
`user-wallet`) attribution surfaced here is the
`rules.yaml`/`expected.txt` narrative the future #47 emitter is
expected to render. T020's `assertShape` only checks
`@collateralInputsTxBodyL@ length == 1`; the
`bytesHex`/`atAddress` join is part of the B-side pin.

## Output 2

9.825 ADA change back to the contingency account (60 + 50 ADA
in minus 100 ADA disbursed minus 0.175 ADA fee).

## Address decompositions

The `user-wallet` bech32 is identical to alice's in
`02-alice-bob-ada` and the `recipient` bech32 is identical to
bob's there; the contingency-account address is a script-script
base address whose payment and stake credentials both resolve to
the same decoded 28-byte hash (see entity block above). The
contingency-account stake credential bnode is reusable from any
future cert/withdrawal that points at the same script — Phase A
has no separate `CollateralStakeCredential` class.

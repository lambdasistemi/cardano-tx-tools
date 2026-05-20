# 04-mint-spend-script-overlap — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Operator-declared entities

`usdm-control` is a script-style 28-byte hash declared with
`keys: [PaymentScript, Policy]` — the 044 Story 4 cross-leaf
identity surface. The SAME 28-byte `bytesHex` surfaces as TWO
distinct `Identifier` instances under the same `Entity`: one with
`leafType "PaymentScript"` (locking the input UTxO at the
self-script address), one with `leafType "Policy"` (governing
the USDM mint). The future #47 emitter is contracted to mint
both `Identifier` nodes under the same `Entity`; the kmaps#53
`(leafType, bytesHex)` key (declared in Phase B) does NOT
collapse them — the role distinction is intentional — but any
future `hasIdentifier` reasoner sees a single `Entity` holding
both leaves.

Three identity-bearing references reuse these two identifier
bnodes elsewhere in the file, surfacing the cross-leaf property
at the Turtle level:

- the input UTxO's payment credential resolves to
  `_:usdmCtrlPayment` (via `hasPaymentCredential` →
  `hasIdentifier`);
- the mint entry's `hasPolicy` resolves to `_:usdmCtrlPolicy`;
- the witness-set script's `hasHash` resolves to
  `_:usdmCtrlPayment`.

All three reuse identifier bnodes already declared under the
`usdm-control` entity; the file mints no fresh `Identifier`
triples for these reuses.

`usdm` reuses the T016 (`03-multi-asset-transfer`) `AssetClass`
convention: a single `Identifier` with `leafType "AssetClass"`
and a `bytesHex` concatenating the 28-byte policy with the
hex-encoded ASCII asset name (`"USDM"` → `55534d4d`). The
structural Policy↔AssetClass cross reference is exposed
downstream by the mint entry's `hasPolicy` edge, not by an extra
triple here; the kmaps#53 `(leafType, bytesHex)` key does not
collapse the `AssetClass` identifier with the `Policy` identifier
because their leafTypes differ — that's the intended Phase B
behaviour.

`alice` reuses the same 28-byte payment / stake key hashes as
`02-alice-bob-ada` — identical bech32 string + identical
identifier bytes.

## Transaction body

1 input at the `usdm-control` self-script address, 1 output to
alice (carrying 1000 USDM), 1 mint entry under the `usdm-control`
policy, a witness-set blank node, 500_000 fee. No certificates,
withdrawals, proposals, collateral inputs, or reference inputs.

This is the first B-side fixture to surface `cardano:hasMint`
and `cardano:hasWitnessSet` on the transaction blank node — both
properties are declared in kmaps#53 Phase A.

## Input

A 5 ADA UTxO at the `usdm-control` self-script address. The
input's payment credential is the `usdm-control` `PaymentScript`
identifier (see the address decomposition below). The locked ADA
quantity is body-data and lives in `expected.txt` / the future
#47 emitter, not in this structural graph — same precedent
T015..T020 set for coin values.

## Output 1

4.5 ADA + 1000 USDM to alice. The USDM asset quantity is
body-data and lives in `expected.txt` / the future #47 emitter,
not in this structural graph; the asset identity is anchored by
the `:usdm` `Entity` above.

## Mint entry

+1000 USDM under the `usdm-control` policy. The mint entry blank
node is typed `cardano:Asset` and binds:

- `cardano:hasPolicy` → `_:usdmCtrlPolicy` (cross-leaf: reuses
  the `usdm-control` `Policy` identifier — same 28-byte
  `bytesHex` as the input's `PaymentScript` identifier, different
  `leafType`);
- `cardano:hasAssetName "USDM"` (4-byte ASCII literal; the hex
  form `55534d4d` appears as the trailing 8 hex digits of
  `:usdm`'s `AssetClass` `bytesHex` above).

Phase A does not (yet) declare a property for the per-entry mint
amount; the +1000 quantity is body-data and lives in
`expected.txt` / the future #47 emitter, paralleling the
precedent set by T015..T020 of leaving coin / asset quantities
out of the structural graph.

## Witness set

The spending-validator script witness for the input above. Phase A
declares `cardano:hasWitnessSet` as the body-level binding and
declares the `cardano:Script` class plus the `cardano:hasHash`
property, but does not (yet) decompose witness sets into keys /
scripts / datums / redeemers — no published Phase A property
wires a witness-set blank node to a `Script` blank node.

The slice anticipates a kmaps#53 follow-up by introducing the
slice-local `cardano:hasScript` edge below; the property is NOT
declared in Phase A, the `TurtleShim` does not validate vocab
terms, and a Phase B / follow-up rename remains a mechanical sed.

The cross-leaf identity is anchored at the script's
`cardano:hasHash`: its target is the SAME identifier bnode
(`_:usdmCtrlPayment`) that the input's payment credential
targets, making the script witness, the locking script, and the
mint's policy share a single 28-byte hash surfaced under two
`leafType` codes (`"PaymentScript"`, `"Policy"`) under the single
`:usdm-control` `Entity`.

## Address decompositions

The `usdm-control` address is a script-style enterprise address:
its payment credential is the `PaymentScript` identifier, and it
carries no stake credential (no `cardano:hasStakeCredential`
triple — Phase A tolerates absent stake credentials on enterprise
addresses).

The `usdm-control` bech32 is also absent: the operator declared
`bytes:` only in `rules.yaml` (no `from-address`), so the full
address has no operator-pinned bech32 string the structural graph
could carry — matching the `expected.txt` convention of
`@<addr-under-usdm-control-script>@` as a verbatim placeholder.

Alice's bech32 + identifier targets are identical to
`02-alice-bob-ada`.

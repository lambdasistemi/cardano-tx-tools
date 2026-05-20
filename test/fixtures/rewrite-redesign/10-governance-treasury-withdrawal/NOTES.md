# 10-governance-treasury-withdrawal — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Operator-declared entities

`operator` reuses the same 28-byte payment / stake key hashes as
alice in `02-alice-bob-ada` (entity IRI renamed; identifier bytes
unchanged); `cardano-foundation.ops` reuses the same 28-byte
payment / stake key hashes as bob there.

The dot in the `cardano-foundation.ops` name is rewritten to an
underscore in the CURIE local-part (`:cardano-foundation_ops`)
to avoid the Turtle `PN_LOCAL` trailing-dot trap; `rdfs:label`
preserves the operator-declared spelling, paralleling the T020
(`08-contingency-disburse`) precedent for
`:amaru-treasury_contingency_account`.

## Transaction body

1 input, 1 output, 1 governance proposal, 175_000 fee. No
certificates, withdrawals, collateral, reference inputs, or mint
entries. This is the first B-side fixture to populate the
`proposalProcedures` field, so it is also the first to surface
`cardano:hasProposal` on the transaction blank node — the
structural counterpart to `cardano:hasCertificate` (T018 / T019),
`cardano:hasWithdrawal` (T017), and
`cardano:hasCollateralInput` (T020) already used by earlier
B-side slices.

## Input

Operator's 100_001 ADA UTxO funding both the 100_000 ADA proposal
deposit and the 0.175 ADA fee, with 0.825 ADA change returned in
output 1.

## Output 1

0.825 ADA change back to operator (100_001 ADA in minus the
100_000 ADA proposal deposit minus the 0.175 ADA fee).

## Proposal 1

`ProposalProcedure` carrying a `TreasuryWithdrawals` action
requesting 50_000 ADA paid to `cardano-foundation.ops`. Phase A
declares `cardano:hasProposal` as the body→proposal binding but
does not (yet) declare a `ProposalProcedure` class or per-variety
subclasses — and the (`deposit`, `returnAddr`,
`action.withdrawals.{address: amount}`) shape from 044 Story 10
carries coin amounts (body-data), not structural-leaf data. The
structural graph therefore surfaces only the identity-bearing
surface of the proposal:

- the proposal's variety tag is pinned via `cardano:Datum` +
  `cardano:decodedAs "TreasuryWithdrawals"` — reusing the
  `decodedAs` property Phase A declares for datum/redeemer
  payloads to label the action variant — and parallels the
  precedent set by T015..T021 of leaving body-data quantities
  (deposit, mint amounts, coin values) out of the structural
  graph while pinning the kind of action;
- the proposer's `returnAddr` is the operator's stake credential,
  so the proposal carries a `cardano:hasIdentifier` link to the
  same `_:operatorIdStake` bnode the address decomposition emits;
- the `TreasuryWithdrawals` target reward-account is
  `cardano-foundation.ops`'s stake credential, surfaced as a
  second `cardano:hasIdentifier` link to the same
  `_:cardanoFoundationOpsIdStake` bnode emitted by that entity's
  address decomposition.

Both stake-side identifiers — `returnAddr` vs withdrawal target —
attach to the proposal under the same `cardano:hasIdentifier`
property because Phase A has no separate `hasReturnAddr` /
`hasWithdrawalTarget` terms; the kmaps#53 `(leafType, bytesHex)`
key on each leaf still pins which is which through the address
decomposition. A future kmaps follow-up can mint richer terms
(deposit amount, per-withdrawal coin, `returnAddr`/target role
discriminators) and the rename remains a mechanical sed across
this fixture and the future #47 emitter.

The 50_000 ADA withdrawal amount and the 100_000 ADA deposit
live in `expected.txt` / the future #47 emitter, not in this
structural graph — matching the same convention as the earlier
B-side fixtures (cert deposits, withdrawal amounts, mint
quantities, coin values).

## Address decompositions

The operator bech32 is identical to alice's in
`02-alice-bob-ada` and the `cardano-foundation.ops` bech32 is
identical to bob's there. Both address decompositions reuse the
identifier bnodes declared in the entity blocks above; the
operator stake-credential bnode (`_:operatorIdStake`) is the
same one referenced by the proposal's `returnAddr` link, and
the `cardano-foundation.ops` stake-credential bnode
(`_:cardanoFoundationOpsIdStake`) is the same one referenced by
the proposal's `TreasuryWithdrawals` target link — the
cross-leaf identity surface kmaps#53 pins.

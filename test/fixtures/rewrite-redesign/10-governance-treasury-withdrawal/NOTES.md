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
requesting 50_000 ADA paid to `cardano-foundation.ops`. T108 / S7
emits the D-006 fallback shape: the proposal subject itself is
typeless (typing under `cardano:Proposal` is deferred to follow-on
F3) and carries only a single `cardano:hasDatum` edge to an inline
sub-block; the sub-block IS typed `cardano:Datum` and carries

- `cardano:decodedAs "TreasuryWithdrawals"` — the variety tag,
  parallel to how Phase A uses `decodedAs` for datum/redeemer
  payloads; and
- `cardano:hasRawBytes "<cbor-hex>"` — the CBOR wire-encoding of
  the `ProposalProcedure` itself (deposit + return-addr + action
  + anchor), serialized at the Conway era's protocol version.

The proposer's `returnAddr` and the `TreasuryWithdrawals` target
reward-account are dropped from the structural surface — Phase A
has no `proposerReturnAddr` / `withdrawalTarget` predicates, so
their identifier links are deferred to follow-on F3. Until F3,
the typed inline-datum payload preserves enough information to
recover both addresses via CBOR decode without minting under-
specified `cardano:hasIdentifier` links to the proposal subject.

The 50_000 ADA withdrawal amount and the 100_000 ADA deposit
live in `expected.txt` / the future #47 emitter, not in this
structural graph — matching the same convention as the earlier
B-side fixtures (cert deposits, withdrawal amounts, mint
quantities, coin values).

## Address decompositions

This fixture's body has 1 spending input + 1 change output, so
the deduped address-decomposition section carries a single
`cardano:PaymentCredential` entry for the operator's payment
key (no stake-credential leaves are emitted at this slice — the
return-addr + withdrawal-target stake credentials live inside
the proposal's inline CBOR raw bytes per D-006, not as
`hasIdentifier` links on the proposal subject).

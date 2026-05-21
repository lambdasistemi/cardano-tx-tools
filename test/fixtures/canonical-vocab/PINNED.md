# Canonical vocab pin — provenance

Vendored snapshot of the canonical `cardano:` vocab from
[lambdasistemi/cardano-knowledge-maps](https://github.com/lambdasistemi/cardano-knowledge-maps),
the source of truth for predicate declarations consumed by the
body emitter.

## Current pin

- **File**: [`transactions.ttl`](./transactions.ttl)
- **Source**: `data/rdf/transactions.ttl`
- **Repo**: `lambdasistemi/cardano-knowledge-maps`
- **SHA**: `e0602fe` (branch `phase-a2-tx-semantic-completeness`
  tip on 2026-05-21, after the force-push to derived content).
- **Branch state**: draft PR
  [kmaps#56](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/56),
  not yet merged to `main`. Base kmaps `main` @
  `cce9625b7cf6f1215fcb0c29815ea2ad3176c0f9` (Phase A.1 merged).
  The branch HEAD is a single commit replacing the previous
  Phase A.1.5 guess content with the Vocab.hs-derived patch
  verbatim, per T122b/T123a + operator A-007/A-008 ordering.
- **Version label** declared in the file: `0.1.0-phaseA` (now with
  Phase A.2 additions appended at the tail: `cardano:Certificate`
  parent + 11 Conway-era cert subclasses, `cardano:Proposal`
  parent + 7 proposal subclasses, `cardano:Vote` + `Voter` parent
  + 3 voter subclasses, `hasRequiredSigner`, `totalCollateral`,
  `hasCollateralReturn`, `currentTreasuryValue`,
  `treasuryDonation`, `onCredential`, `withAmount`, `toPool`,
  `toDRep`, `retireAtEpoch`, `hasAnchor`, `anchorUrl`,
  `anchorHash`, `hasDeposit`, `hasRefund`, `hasVote`, `hasVoter`,
  `hasVotingAction`, `hasVerdict`, `hasReturnAddress`,
  `hasGovActionId`, plus the `cardano:Mint` / `Policy` /
  `Withdrawal` / `Pool` / `DRep` / `StakeDelegation` /
  `VoteDelegation` #58-inherited drift classes).
- **History** (previous pins):
  kmaps@`cce9625b7cf6f1215fcb0c29815ea2ad3176c0f9` (Phase A.1
  merged main, vendored at T110b);
  kmaps@`8ed218cf6dc905c7e3139b9f5a418d278b0acf9c` (382 lines,
  pre-`hasAssetValue` tip refreshed at T103);
  kmaps@`8597fbd571188b42999ee0b24a8247bda7e717b9` (303 lines,
  vendored at T101 / S0).

## Why pin?

The `VocabTraceabilitySpec` invariant (per spec FR-013, the
strict vocab-traceability extension) asserts that every emitted
CURIE in the body emitter's output traces to a term declared in
the canonical vocab. To keep that check deterministic and
offline-buildable, this directory carries a verbatim copy of the
canonical file rather than reaching out to GitHub at test time.

The pin is refreshed in dedicated `chore(070): refresh
canonical-vocab pin to kmaps@<sha>` commits — never on the same
commit as a behavior-changing slice (per A-002's decoupling
rationale).

## Lifecycle (per A-002 / A-004 / A-005)

1. T101 / S0 — pin at kmaps@8597fbd57 (Phase A header only).
2. T103 — refresh to kmaps@8ed218cf (Phase A.1 branch tip with
   `@prefix xsd:` fix).
3. T110a — refresh to kmaps@5536df0f (Phase A.1 branch tip with
   `hasAssetValue` predicate added).
4. T110b — refresh to kmaps@cce9625b (Phase A.1 merged to main).
5. T114b — refresh to kmaps@a9b5d96 (Phase A.2 branch tip,
   Phase A.1.5 guess content). Enabled the type-driven
   exhaustive ConwayDiffValue coverage work (T115..T122).
6. **T123a (this commit)** — refresh to kmaps@e0602fe after the
   parent force-pushed kmaps#56 to the Vocab.hs-derived patch
   verbatim (operator A-008). The strict VocabTraceabilitySpec
   gate flips ON at this slice — every emitted CURIE must trace
   to a declaration in this pin.
7. **T123 (finalization, after Path A merge)** — refresh to the
   merged kmaps `main` SHA once kmaps#56 lands. Blocks PR #77
   finalization (T126).

## Refresh recipe

```bash
# Fetch the latest version from a known SHA:
curl -sL "https://raw.githubusercontent.com/lambdasistemi/cardano-knowledge-maps/<sha>/data/rdf/transactions.ttl" \
  -o test/fixtures/canonical-vocab/transactions.ttl

# Update this file's "Current pin" section with the new SHA + date.
# Commit subject: `chore(070): refresh canonical-vocab pin to kmaps@<sha>`.
```

## Related

- Spec FR-013 — strict vocab-traceability CI check
- Plan D-001..D-006 — predicate-shape decisions consuming the pin
- Companion kmaps PR — [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55)
  (Phase A.1 additions, draft)
- Sub-orchestrator's draft of the additions —
  `/tmp/epic-046/tx-70/transactions-additions.ttl` (out-of-tree)

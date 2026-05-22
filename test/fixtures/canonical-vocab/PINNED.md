# Canonical vocab pin — provenance

Vendored snapshot of the canonical `cardano:` vocab from
[lambdasistemi/cardano-knowledge-maps](https://github.com/lambdasistemi/cardano-knowledge-maps),
the source of truth for predicate declarations consumed by the
body emitter.

## Current pin

- **File**: [`transactions.ttl`](./transactions.ttl)
- **Source**: `data/rdf/transactions.ttl`
- **Repo**: `lambdasistemi/cardano-knowledge-maps`
- **SHA**: `51088551a73f4b92f6611879908a2ea1f2bcd105` (kmaps
  `main` after kmaps#59 squash-merged).
- **Branch state**: merged. kmaps#59 (Phase A.4 — `cardano:decodeError`
  datatype property for CIP-57 blueprint typed-decoding failures)
  landed on kmaps main. Base of that commit was Phase A.3 merged @
  `f8ca27549f22b3bbfd42528439253a48182fca16`.
- **T109 verification**: fetched kmaps `origin/main` on 2026-05-22;
  `git rev-parse origin/main` returned
  `51088551a73f4b92f6611879908a2ea1f2bcd105`, and
  `data/rdf/transactions.ttl` was byte-identical to this vendored
  snapshot.
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
  `VoteDelegation` #58-inherited drift classes; and the Phase
  A.3 witness-set seaboard: classes `cardano:KeyWitness`,
  `cardano:BootstrapWitness`, `cardano:ExUnits`; properties
  `cardano:hasRedeemer`, `cardano:hasKeyWitness`,
  `cardano:hasDatumWitness`, `cardano:hasScriptWitness`,
  `cardano:hasBootstrapWitness`, `cardano:hasPurpose`,
  `cardano:hasData`, `cardano:hasExUnits`, `cardano:memoryUnits`,
  `cardano:cpuUnits`, `cardano:hasSignature`,
  `cardano:hasVerificationKey`; and the Phase A.4 single
  predicate: `cardano:decodeError` — the CIP-57 typed-decoding
  failure literal emitted alongside the opaque-bytes fallback
  whenever blueprint decoding fails).
- **History** (previous pins):
  kmaps@`f8ca27549f22b3bbfd42528439253a48182fca16` (Phase A.3
  witness-set seaboard merged main, vendored at T128g);
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
6. T123a — refresh to kmaps@e0602fe after the parent
   force-pushed kmaps#56 to the Vocab.hs-derived patch verbatim
   (operator A-008). The strict VocabTraceabilitySpec gate
   flipped ON at this slice — every emitted CURIE must trace to
   a declaration in this pin.
7. T123 — refresh to the merged kmaps `main`
   SHA `cfb599b7e9f83df821a4566573f46d83be118ffb` after the
   parent squash-merged kmaps#56.
8. T128g — refresh to the merged kmaps `main`
   SHA `f8ca27549f22b3bbfd42528439253a48182fca16` after the
   parent merged kmaps#57 (Phase A.3 — witness-set seaboard).
   Brings 15 net-new declarations into the pin: classes
   `cardano:KeyWitness`, `cardano:BootstrapWitness`,
   `cardano:ExUnits`; properties `cardano:hasRedeemer`,
   `cardano:hasKeyWitness`, `cardano:hasDatumWitness`,
   `cardano:hasScriptWitness`, `cardano:hasBootstrapWitness`,
   `cardano:hasPurpose`, `cardano:hasData`, `cardano:hasExUnits`,
   `cardano:memoryUnits`, `cardano:cpuUnits`,
   `cardano:hasSignature`, `cardano:hasVerificationKey`.
   `VocabTraceabilitySpec.pendingPhaseA3` empties on this slice.
9. **T107 (this commit)** — refresh to the merged kmaps `main`
   SHA `51088551a73f4b92f6611879908a2ea1f2bcd105` after the
   parent merged kmaps#59 (Phase A.4 — `cardano:decodeError`).
   Brings 1 net-new declaration into the pin: the
   `cardano:decodeError` datatype property emitted by the
   CIP-57 blueprint walker on the Datum / Redeemer / Script /
   OpaqueLeaf subject whenever `decodeBlueprintData` returns
   `Left`. Fixture 14 (`14-blueprint-decode-fail`) exercises
   the emission via the wrong-shape `swap-v2-wrong-shape.cip57.json`
   blueprint. `VocabTraceabilitySpec` is concurrently extended
   (in this commit) to (a) enumerate fixture 14 and (b) thread
   `rulesBlueprints` from the rules.yaml loader through to the
   `emit` call site — without that wiring the strict gate
   passes vacuously because the spec was previously calling
   `emit … []`, masking blueprint-driven predicates. T106
   (kmaps Phase A.4 patch draft) closes as the
   PARENT-ACTION-satisfied parent of this slice.

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
  (Phase A.1 additions, draft);
  [kmaps#59](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/59)
  (Phase A.4 — `cardano:decodeError`, merged)
- Sub-orchestrator's draft of the additions —
  `/tmp/epic-046/tx-70/transactions-additions.ttl` (out-of-tree)

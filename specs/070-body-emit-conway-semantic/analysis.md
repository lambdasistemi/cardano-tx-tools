# Specification Analysis Report — #70 Body emitter Conway semantic completeness

**Worker**: `tx-70/analyzer` (read-only analyzer subagent)
**Inputs** (HEAD `1f46114`): [spec.md](./spec.md) (717 L), [plan.md](./plan.md) (371 L), [tasks.md](./tasks.md) (299 L)

## 1. Executive summary

**Verdict: GO** — no FIX-BEFORE-S0 blockers. The artifact triangle is internally consistent: every #70 *Scope* row maps to an FR + slice + task; every FR has a task home; the kmaps lifecycle is correctly decoupled via the vendored pin. Two MEDIUM and four LOW findings; all are improve-as-you-go items the sub-orchestrator can fold opportunistically without blocking dispatch.

D-006 (proposal class deferral) is correctly flagged inline and is consistent with epic #46's terminal gates: under the inline-datum fallback the proposal subject still carries ≥2 non-`rdf:type` triples (`cardano:hasDatum` + `cardano:decodedAs`), so the no-stub SPARQL view (FR-012) still returns zero rows on fixture 10.

**Top 3 findings:**

1. **M-001 (MEDIUM)** — FR-004 ([spec.md:407-410](./spec.md)) names `cardano:resolvedTo` to a resolved-output subject block carrying address+lovelace+multi-asset+datum+scriptRef. T103 ([tasks.md:62-79](./tasks.md)) doesn't list `resolvedTo` wiring; S2's title is "fromTxOutRef + reference inputs". The resolved-output payload lands implicitly across S2..S4 with no single coverage assertion.
2. **M-002 (MEDIUM)** — `SubjectDeDupSpec` is named under cross-slice invariants as "T102+" ([tasks.md:270](./tasks.md)) and is the load-bearing US2 invariant — but T102's file list ([tasks.md:50-53](./tasks.md)) does not include `test/Cardano/Tx/Graph/Emit/SubjectDeDupSpec.hs`. Wire-up gap.
3. **L-003 (LOW)** — plan.md's slice table ([plan.md:252-267](./plan.md)) lists S9a at table-row 9 (between S8 and S10), but tasks.md T110a `Sequencing` ([tasks.md:188-192](./tasks.md)) correctly notes the **commit-order** position is BEFORE S2. A reader of plan.md alone could mis-order.

## 2. Cross-artifact consistency — FR → slice → task

All 18 FRs are mapped:

| FR | Slice | Task |
|---|---|---|
| FR-001 (Emit monad) | S1 | T102 |
| FR-002 (per-leaf tellTriple) | S1 + S2..S7 | T102 + T103..T108 |
| FR-003 (subject de-dup) | S1 | T102 |
| FR-004 (input semantic) | S2 | T103 (see M-001) |
| FR-005 (output semantic) | S3, S4 | T104, T105 |
| FR-006 (cert semantic) | (preserved from #58; only mint/withdrawal half active in S5) | T106 |
| FR-007 (withdrawal) | S5 | T106 |
| FR-008 (mint) | S5 | T106 |
| FR-009 (governance proposal) | S7 | T108 |
| FR-010 (body-root) | S6 | T107 |
| FR-011 (ref input) | S2 | T103 |
| FR-012 (no-stub SPARQL) | S8 | T109 |
| FR-013 (vocab pin) | S0, S9a, S9b | T101, T110a, T110b |
| FR-014 (regen fixtures) | inline S2..S8 | T103..T108 |
| FR-015 (cast re-record) | S10 | T111 |
| FR-016 (#58 invariants GREEN) | cross-slice | inherited |
| FR-017 (Hackage-ready) | cross-slice | inherited |
| FR-018 (no #50 creep) | scope guard | n/a |

**Orphans**: none.

## 3. Acceptance coverage — #70 *Scope* + #46 "Per-field minimum coverage"

| Coverage row | US1 acc. | FR | Slice |
|---|---|---|---|
| input `fromTxOutRef` | 1, 2 | FR-004 | S2 |
| reference inputs distinguishable | 2 | FR-011 | S2 |
| collateral inputs distinguishable | 2 | FR-004/011 | S2 |
| resolved-input (`resolvedTo`) | (implicit) | FR-004 | S2 (M-001) |
| output `atAddress` | preserved #58 | FR-005 | preserved |
| output `lovelace` | 3 | FR-005 | S3 |
| output multi-asset | 4 | FR-005 | S3 |
| output inline datum | 5 | FR-005 | S4 |
| output datum hash | 6 | FR-005 | S4 |
| output `scriptRef` | 7 | FR-005 | S4 |
| cert typed subclass + attrs | 8 | FR-006 | preserved + S5 mint |
| withdrawal account + amount | 9 | FR-007 | S5 |
| mint policy/asset/signed quantity | 10 | FR-008 | S5 |
| governance proposal | 11 | FR-009 (D-006 fallback) | S7 |
| body-root predicates | 12 | FR-010 | S6 |
| reference input (no-fail) | 13 | FR-011 | S2 |

**Orphans**: none.

## 4. Deliverables wire-up (12 surfaces)

| # | Surface | Status |
|---|---|---|
| 1 | Linux release pipeline | "no per-PR change" — explicit |
| 2 | Darwin release pipeline | "no per-PR change" — explicit |
| 3 | Darwin dev-Homebrew | review-only at T111 |
| 4 | MkDocs deploy | manual review at S10 |
| 5 | Nix exe + check | "no per-PR change" — explicit |
| 6 | `docs/tx-graph.md` | T111 |
| 7 | Asciinema cast + script | T111, FR-015 |
| 8 | Homebrew taps (external) | "no per-PR change" — explicit |
| 9 | `README.md` | T111 |
| 10 | `CHANGELOG.md` | T112 |
| 11 | `views/no-stub-triples.rq` | T109, FR-012 |
| 12 | Vendored canonical-vocab pin | T101 / T110a / T110b |

**Orphans**: none.

## 5. Scope drift risk

- plan.md introduces `src/Cardano/Tx/Graph/Emit/Monad.hs` as a NEW file (FR-001 says "or new helper module if you want"). Acceptable elaboration, not drift.
- D-005 withdrawal predicate rename is technically "#58 inherited drift cleanup" otherwise deferred — but plan.md correctly justifies it as cleanup-in-passing ([plan.md:143-155](./plan.md)). Not drift.
- tasks.md carries no surface beyond what plan.md authorizes.
- User Story 4 (#58 invariants GREEN) is correctly P1 carry-over via cross-slice invariants — not new work.

## 6. D-006 deferral consistency with epic #46

Epic [#46](https://github.com/lambdasistemi/cardano-tx-tools/issues/46)'s "Completeness — non-negotiable" governance row demands typed proposal/vote/voter triples. D-006 ships an inline-datum fallback for `TreasuryWithdrawals` only, preserving `cardano:decodedAs "TreasuryWithdrawals"`. Against epic terminal gates:

- (a) per-field coverage: SATISFIED — proposal subject carries `hasDatum` + `decodedAs` (≥2 non-type triples).
- (b) no-stub SPARQL: SATISFIED — filter passes since proposal subjects have non-`rdf:type` triples.
- (c) cast demonstrates rich emission: SATISFIED — cast shows the fallback shape just fine.

**Verdict**: D-006 does NOT materially shift the epic's terminal state. F3 closes the predicate shape, not the epic gate. Risk correctly flagged at [plan.md:181-186](./plan.md).

## 7. Slice-order safety

S0..S12 is bisect-safe. Critical check: T110a (pin refresh to [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55) branch tip) is correctly placed **BEFORE** the first slice emitting a Phase A.1 predicate. [tasks.md:188-192](./tasks.md) ("Sequencing: lands before T103 — recommended commit order S0 → S1 → S9a → S2 → S3 …") makes this explicit.

**However**, plan.md's slice table ([plan.md:252-267](./plan.md)) lists S9a at table-row 9 (between S8 and S10) without a footnote saying the commit-order is BEFORE S2. **Flagged as L-003.**

## 8. kmaps lifecycle decoupling

FR-013 vendored-pin pattern consistently applied:

- spec.md FR-013 ([spec.md:454-465](./spec.md))
- plan.md S0 / S9a / S9b ([plan.md:254, 263-264](./plan.md))
- tasks.md T101 (kmaps@8597fbd57) / T110a (kmaps#55 branch tip) / T110b (merged main SHA)

**Pin SHA consistency**: kmaps@8597fbd57 at plan.md:254 + tasks.md:35 matches A-004's confirmation of [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55) base. kmaps#55 cited at plan.md:263, 354-355 and tasks.md:174-192. No inconsistency.

## 9. Follow-on tickets (F1..F4)

| ID | Description | Trigger |
|---|---|---|
| F1 | Expose monadic `traverseConwayDiff` from `Cardano.Tx.Diff` | #51/#52 surface shared-walker need (A-001) |
| F2 | Phase B vocab refresh (cert/governance classes + #58 drift) | A-002 deferral |
| F3 | Proposal subject typing (`cardano:Proposal` + predicates) | D-006 closure |
| F4 | Per-variant family (non-StakeDeleg/VoteDeleg certs, non-TreasuryWithdrawals proposals) | Operator-authored fixture |

**Missing**: votes + voting procedures (spec.md *Out of Scope* line 654-658) — F4 wording is cert/proposal-shaped, not vote-shaped. **Flagged as L-004.**

## 10. Open risks for first dispatch

- **R1** — Fixture 11's real on-chain CBOR is the strongest live-boundary signal at T103. If `assertEmptyLeavesForT008` relaxation surfaces a second unsupported leaf (e.g. required signers), T103 needs Q-file escalation, not silent skip.
- **R2** — kmaps#55 review timing controls T110b. If reviewers push back on a name, parent surfaces via Q-file; affected slice's commits rework — cheap since rename touches one predicate per slice.
- **R3** — Asciinema cast (T111) is opaque to RDF tooling; preview-URL manual review is the only gate. If player JS fails silently, cast shows stub text. Explicit reviewer attention at S10. (Named in [plan.md:336](./plan.md).)
- **R4** — `groupBySubject` order preservation (T102, [plan.md:75](./plan.md)) is load-bearing for reproducibility — fixture 02 byte-diff at S1 is the smoke. If S1's byte-diff drifts, the ordering assumption is wrong.

## Findings table

| ID | Category | Severity | Location | Summary | Recommendation |
|---|---|---|---|---|---|
| M-001 | Coverage gap | MEDIUM | spec.md FR-004, tasks.md T103 | FR-004 names `cardano:resolvedTo` to a resolved-output subject block. T103 doesn't list `resolvedTo` wiring. Resolved-output payload lands implicitly across S2..S4 with no single coverage assertion. | Add a one-line acceptance check in T103's brief — "every spending input under the UTxO map carries `cardano:resolvedTo _:resolvedN`, and `_:resolvedN` carries lovelace by T104 + datum/scriptRef by T105". |
| M-002 | Wire-up gap | MEDIUM | tasks.md T102 file list, cross-slice invariants | `SubjectDeDupSpec` named under cross-slice ("T102+") but T102's file list omits `test/Cardano/Tx/Graph/Emit/SubjectDeDupSpec.hs`. Spec.md US2 names it as the de-dup invariant. | Add `test/Cardano/Tx/Graph/Emit/SubjectDeDupSpec.hs` to T102's file list. |
| L-001 | Naming overlap | LOW | plan.md S5, tasks.md T106 | S5 / T106 bundles FR-007 (withdrawal) + FR-008 (mint). Bisect-safe but commit subject covers two FRs. | Acceptable; if worker prefers, split into T106a (withdrawal) + T106b (mint). Non-blocking. |
| L-002 | Surface enumeration | LOW | tasks.md T113, cross-slice | Post-T113 (gate.sh deletion), the CI surface picking up `NoStubViewSpec` is implicit via hspec discovery. T109 says "verify hspec discovery" but doesn't restate the post-T113 surface. | Add one-line confirmation in T109 or T113 that `NoStubViewSpec` survives gate.sh drop via `cabal test` / nix-check. |
| L-003 | Documentation clarity | LOW | plan.md slice table | Slice table lists S9a at table-row 9 (between S8 and S10); tasks.md T110a Sequencing correctly notes commit-order is BEFORE S2. Reader of plan.md alone could mis-order. | Footnote on plan.md slice table: "S9a's commit-order position is BEFORE S2 — see tasks.md T110a Sequencing note." |
| L-004 | Missing follow-on | LOW | spec.md Out of Scope, tasks.md F1..F4 | Out of Scope names "votes + voting procedures" deferred; F4 wording is cert/proposal-shaped, not vote-shaped. | Widen F4 to include votes + voting procedures, or add F5. Non-blocking. |

## Coverage summary

| Requirement | Has Task? | Task IDs |
|---|---|---|
| FR-001..FR-018 | Yes | T101..T113 |
| SC-001..SC-009 | Yes | cross-slice + T109 (no-stub) + T103 (ref input) + T111 (cast) |

## Constitution alignment

No conflicts. Plan.md `Constitution gate` section ([plan.md:11-37](./plan.md)) addresses each of the seven principles. Default-Offline reinforced by the vendored-pin pattern. Strict warnings continue to surface unhandled `ConwayDiffValue` constructors via `-Wincomplete-patterns`.

## Unmapped tasks

None.

## Metrics

- Total Requirements: 18 FR + 9 SC = 27
- Total Implementation Tasks: 13 (T101..T113) + 6 pre-implementation
- Coverage: 100% (every FR + SC has ≥1 task)
- Ambiguity Count: 0 (no [NEEDS CLARIFICATION], no TODO, no TKTK)
- Duplication Count: 0
- Critical Issues: 0
- High Issues: 0
- Medium Issues: 2 (M-001, M-002)
- Low Issues: 4 (L-001..L-004)

## Next actions

- **No CRITICAL or HIGH issues.** Dispatch first implementation slice (T101 / S0) as planned.
- **MEDIUM follow-ups** (M-001, M-002) — fold into T102's and T103's briefs opportunistically; do not block dispatch.
- **LOW follow-ups** — apply during slice review.

---

## One-paragraph verdict summary

**GO.** The spec/plan/tasks triangle for #70 is internally consistent and free of CRITICAL or HIGH issues. Every FR maps to a slice and a task; every #70 *Scope* and #46 per-field-coverage row maps to a US1 acceptance scenario + FR + slice; all 12 deliverables surfaces have a wire-up home or are explicitly marked "no per-PR change"; the kmaps lifecycle decoupling via the vendored pin (FR-013) is consistently applied across spec/plan/tasks with matching SHAs; T110a is correctly sequenced before T103 in commit-order per the tasks.md Sequencing note; D-006's proposal-class deferral still satisfies the epic [#46](https://github.com/lambdasistemi/cardano-tx-tools/issues/46) terminal gates because the inline-datum fallback emits ≥2 non-`rdf:type` triples on the proposal subject. Top 3 findings — M-001 (`resolvedTo` wiring not explicit in T103), M-002 (`SubjectDeDupSpec` test file missing from T102's file list), L-003 (plan.md slice table doesn't footnote S9a's commit-order position) — are all improve-as-you-go items. The parent may proceed to dispatch T101.

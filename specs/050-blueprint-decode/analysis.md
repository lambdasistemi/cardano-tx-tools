# Specification Analysis Report — #50 Blueprint decode → typed triples

**Worker**: `tx-50/analyzer` (read-only self-pass)
**Inputs** (HEAD `d3257b7`): [spec.md](./spec.md) (633 L), [plan.md](./plan.md) (286 L), [tasks.md](./tasks.md) (378 L)

## 1. Executive summary

**Verdict: GO** — no FIX-BEFORE-S0 blockers. The artifact triangle is internally consistent: every #50 *Scope* row maps to an FR + slice + task; every FR has a task home; every fixture slug is pinned per D-001f. Two MEDIUM and three LOW findings; all are improve-as-you-go items the sub-orchestrator can fold opportunistically without blocking dispatch.

The seven A-001 decisions (D-001a..D-001g) are consistently quoted at every layer of the triangle. The kmaps Phase A.4 dependency for `cardano:decodeError` is correctly decoupled via the vendored-pin pattern (T106 drafts → T107 refresh-to-branch-tip → T109 refresh-to-merged-SHA), matching the post-#70 lifecycle that has already proven this works in practice.

**Top 3 findings:**

1. **M-001 (MEDIUM)** — Redeemer-path coverage is unit-only. FR-007 ([spec.md:412-426](./spec.md)) names blueprint-decoded redeemer emission keyed by `Spend/Mint/Cert/Reward/Propose/Vote` purposes. T101's `BlueprintSpec` ([tasks.md:106-117](./tasks.md)) covers the structural side via synthetic inputs, but the three new fixtures (11/12/13) only exercise the **datum** path. Neither vendored blueprint (`swap-v2-datum.cip57.json`, `mpfs-fact.cip57.json`) declares a `redeemer:` shape. **The fixture-level redeemer-path coverage gap is a deferral, not a blocker** — the structural logic is identical (lookup → decode → mint), and the unit tests cover it.
2. **M-002 (MEDIUM)** — FR-013 ([spec.md:441-446](./spec.md)) says the `build-fixture.hs` regen harness is extended to drive blueprint-loading "without per-fixture builder changes". T100's file list ([tasks.md:46-66](./tasks.md)) lists the loader files but does NOT name the `build-fixture.hs` regen entry point. If the regen path is byte-stable as the spec asserts, the work is zero; if it needs threading, the gap surfaces only when T103 runs the regen. Wire-up risk.
3. **L-001 (LOW)** — plan.md's slice table ([plan.md:177-189](./plan.md)) carries a "Note on commit order" inline mentioning `S6 → S7 → S5` could be the alternative path "if S5's `expected.ttl` can't ship before kmaps Phase A.4 lands". The conditional is correct but a reader might miss it. tasks.md T107 ([tasks.md:233-246](./tasks.md)) doesn't restate the order pin one way or the other.

## 2. Cross-artifact consistency — FR → slice → task

All 18 FRs are mapped:

| FR | Slice | Task |
|---|---|---|
| FR-001 (`rulesBlueprints` field + loader) | S0 | T100 |
| FR-002 (`Emit.Blueprint` module + decoder functions) | S1 | T101 |
| FR-003 (`emit` signature extension) | S2 | T102 |
| FR-004 (`emitOutputDatum` consults blueprint index) | S2 | T102 |
| FR-005 (decode-failure path; first-error-only) | S2 (logic), S5 (fixture proof) | T102, T105 |
| FR-006 (datum-witness emitter mirrors FR-004/005) | S2 | T102 |
| FR-007 (redeemer emission per purpose) | S2 | T102 (see M-001 — fixture coverage gap) |
| FR-008 (predicate naming + `DuplicateBlueprintPredicate` hard error) | S0 (error variant), S1 (minter) | T100, T101 |
| FR-009 (`cardano:decodeError` to canonical vocab) | S6, S7 | T106, T107 |
| FR-010 (`BlueprintPredicateTraceabilitySpec` set-equality) | S4 | T104 |
| FR-011 (new `RulesLoadError` variants) | S0 | T100 |
| FR-012 (three new fixtures with pinned slugs) | S3, S4, S5 | T103, T104, T105 |
| FR-013 (`build-fixture.hs` regen extension) | S0 (implicit) | T100 (see M-002) |
| FR-014 (stderr warning per failed decode) | S5 | T105 |
| FR-015 (asciinema cast re-record) | S8 | T108 |
| FR-016 (`CHANGELOG.md` entry) | S10 | T110 |
| FR-017 (no new CLI flags) | cross-cutting scope guard | n/a (negative requirement) |
| FR-018 (existing 11 fixtures byte-stable) | S0, S2 + cross-slice | T100, T102 + EmitGoldenSpec |

**Orphans**: none.

## 3. Acceptance coverage — #50 *Acceptance* + ticket-body rows

| Ticket-body acceptance row | US | FR | Slice |
|---|---|---|---|
| A tx whose script has a blueprint registered produces typed datum triples | US1 | FR-004, FR-008 | S3 (T103) |
| A tx whose script has NO blueprint produces opaque datum triples only | US2 | FR-005 (negation) | S4 (T104) |
| A blueprint that fails to decode produces raw bytes + `cardano:decodeError`; pipeline exits 0 | US3 | FR-005, FR-014 | S5 (T105) |
| Blueprint-named predicates + entity rules + reasoner produce `owl:sameAs` deductions | (deferred per D-001e to #49) | n/a in #50 | n/a |

**Orphans**: ticket acceptance row 4 is correctly deferred to #49 per D-001e — flagged inline at spec.md FR-005, plan.md D-001e quote, tasks.md F1.

## 4. Deliverables wire-up (14 surfaces)

| # | Surface | Status |
|---|---|---|
| 1 | Library modules (Emit.Blueprint, Project, Witness, Emit, Rules.Load.*) | T100, T101, T102 |
| 2 | Tests (BlueprintSpec, BlueprintPredicateTraceabilitySpec, golden ext.) | T101, T104, T103 |
| 3 | Fixtures 11 / 12 / 13 | T103, T104, T105 |
| 4 | Linux release pipeline | "no per-PR change" — explicit |
| 5 | Darwin release pipeline | "no per-PR change" — explicit |
| 6 | Darwin dev-Homebrew validation string | review-only at T108 |
| 7 | MkDocs deploy | manual review at T108 |
| 8 | Nix exe + check | "no per-PR change" — explicit |
| 9 | `docs/tx-graph.md` | T108 |
| 10 | Asciinema cast + script | T108 / FR-015 |
| 11 | Homebrew taps (external) | "no per-PR change" — explicit |
| 12 | `README.md` | T108 |
| 13 | `CHANGELOG.md` | T110 |
| 14 | Vendored canonical-vocab pin | T107 / T109 |

**Orphans**: none.

## 5. Scope drift risk

- spec.md FR-002 names `decodeRedeemerForPurpose` as a sibling to `decodeDatumForOutput`. plan.md T101 includes both. No drift.
- The new `Emit.Blueprint` module is the only new src file; the rest are extensions of existing modules. Scope contained.
- The new `RulesLoadError` variants (six of them) extend an existing ADT — additive only, no breaking change for downstream callers other than the `renderRulesLoadError` exhaustiveness check (which the compiler catches via `-Wincomplete-patterns`).
- User Story 4 (existing #58/#70/#77 invariants stay GREEN) is correctly P1 carry-over via cross-slice invariants — not new work.
- The decode-failure stderr line format (FR-014) is pinned in spec.md as
  `tx-graph: WARN: blueprint decode failed for <position-name> under script <hash>: <reason>`. tasks.md T105 doesn't restate this format; reader of tasks.md alone might bikeshed. Acceptable — fixture 13's `expected.txt` byte-equality is the binding contract.

## 6. D-001e deferral consistency with epic #46

Epic #46's acceptance row 4 ("blueprint-named predicates + entity rules + reasoner produces `owl:sameAs` deductions") is consistently deferred to #49 across the triangle:

- spec.md User Story 1 last paragraph names the deferral with the explicit "#49's contract, not #50's".
- plan.md D-001e quote (`Constitution gate → Pinned decisions`) ratifies the same.
- tasks.md F1 ("OWL annotations for blueprint-derived predicates") records the follow-on closure.

**Verdict**: D-001e does NOT materially shift the epic's terminal state. The OWL annotations that would close acceptance row 4 are #49's responsibility; #50 ships the typed triples that #49 consumes. No #50 gate broken.

## 7. Slice-order safety

S0..S11 is bisect-safe. Critical question: does S5 (fixture 13 emitting `cardano:decodeError`) ship BEFORE T107 (canonical-vocab pin refresh adding `cardano:decodeError`)?

- If `VocabTraceabilitySpec` runs against fixture 13's `expected.ttl` and the canonical pin does NOT yet declare `cardano:decodeError`, the strict check fails on the new term → GATE-FAIL on S5.
- plan.md's "Note on commit order" ([plan.md:177-189](./plan.md)) acknowledges the choice: either ship S5 before T107 (and accept a temporary `VocabTraceabilitySpec` regression that T107 closes) or reorder to commit T107 before S5.
- tasks.md T107 ([tasks.md:233-246](./tasks.md)) marks "Depends on: T106 PARENT-ACTION acknowledgement" but doesn't pin the slice ordering one way or the other.

**Recommendation**: pin the commit order `S0 → S1 → S2 → S3 → S4 → S6 → S7 → S5 → S8 → S10 → S9 → S11` in plan.md and re-state it in tasks.md T107 ("Sequencing: T107 lands BEFORE T105 so `VocabTraceabilitySpec` stays GREEN on every commit"). **Flagged as L-001.**

## 8. kmaps lifecycle decoupling

FR-009 vendored-pin pattern consistently applied:

- spec.md FR-009 ([spec.md:447-454](./spec.md))
- plan.md S6 / S7 / S9 ([plan.md:155-159, 162-165](./plan.md))
- tasks.md T106 (draft) / T107 (pin to branch tip) / T109 (pin to merged SHA)

The pattern matches the #70 / kmaps#55 lifecycle that already proved this decoupling works (see #70 analysis.md section 8). Only one new term ships (`cardano:decodeError`) — smaller cross-repo surface than #70's 10-property batch.

## 9. Follow-on tickets (F1..F4)

| ID | Description | Trigger |
|---|---|---|
| F1 | OWL annotations for blueprint-derived predicates | #49 / #51 integration test owns this |
| F2 | SHACL shapes for operator-extensible decode (Phase C) | #51 follow-up |
| F3 | Cross-blueprint predicate-namespace handling | Real operator workflow surfaces a need beyond fixture-scoped `:` |
| F4 | `--no-blueprint-decode` debug flag | Operator workflow surfaces a need to emit opaque despite registered blueprint |

**Missing**: redeemer-path fixture coverage. M-001 names this; the closure is either (a) extend one of the existing fixtures (e.g. fixture 04 mint-spend-script-overlap) with a redeemer blueprint, or (b) file F5 "Redeemer-path fixture coverage" and defer. **Recommendation (a)** — fold into T103/T104/T105 if cheap; **otherwise (b)** — flag F5. **Flagged as L-002.**

## 10. Open risks for first dispatch

- **R1** — Fixture 11's typed-emission byte shape (`:SwapOrder_recipient _:datum1_recipient ; _:datum1_recipient a cardano:Identifier`) is **not pinned in any file** before T103 authoring time. plan.md mentions an "ADR-style note inside the fixture's `NOTES.md`" (R2), but the byte shape needs to be decided in T103's brief, not at write-time, so the driver/navigator pair don't bikeshed. **Flagged as L-003.**
- **R2** — kmaps#58 review timing controls T109. If reviewers push back on the `cardano:decodeError` name (e.g. propose `cardano:hasDecodeError` for predicate-vs-class consistency), parent surfaces via Q-file; affected slices' commits rework — cheap since rename touches one term across the canonical pin + fixture 13's `expected.ttl`.
- **R3** — Asciinema cast (T108) is opaque to RDF tooling; preview-URL manual review is the only gate. If player JS fails silently, cast shows stub text. Explicit reviewer attention at T108.
- **R4** — `RulesLoadResult` is consumed by multiple callers — the `tx-graph` exe, the test harness `EmitGoldenSpec` enumerator, the `build-fixture.hs` regen path (M-002), and potentially the upstream `tx-diff` integration in `Diff/Cli.hs`. T100 ships the pattern-match audit + callsite updates in the same commit; CI build catches misses.

## Findings table

| ID | Category | Severity | Location | Summary | Recommendation |
|---|---|---|---|---|---|
| M-001 | Coverage gap | MEDIUM | spec.md FR-007, tasks.md T103/T104/T105 | Redeemer-path emission has unit-test coverage (T101 `BlueprintSpec`) but no fixture-level coverage; both vendored blueprints declare only `datum:`, not `redeemer:`. | Either (a) author a `redeemer:` extension on `swap-v2-datum.cip57.json` and extend one of fixtures 11..13 to exercise the redeemer path, or (b) file F5 "Redeemer-path fixture coverage" and defer. Non-blocking for first dispatch; T101 unit tests are sufficient for the structural contract. |
| M-002 | Wire-up gap | MEDIUM | tasks.md T100 file list | FR-013 names the `build-fixture.hs` regen harness extension; T100's file list doesn't enumerate it. If the regen path is byte-stable as the spec asserts, the work is zero; if it needs threading, the gap surfaces at T103. | Add to T100's file list a verification step "confirm `build-fixture.hs` (or equivalent regen entry point) accepts the new `rulesBlueprints` index without modification". Non-blocking; can be folded into T100's brief. |
| L-001 | Slice ordering | LOW | plan.md slice table, tasks.md T107 | Commit order between T105 (fixture 13 emits `cardano:decodeError`) and T107 (canonical-vocab pin adds `cardano:decodeError`) is not pinned. `VocabTraceabilitySpec` could regress on S5 if T107 isn't committed first. | Pin the commit order `S0..S4 → S6 → S7 → S5 → S8 → S10 → S9 → S11` in both plan.md ("Note on commit order" line) and tasks.md T107 ("Sequencing: lands BEFORE T105"). |
| L-002 | Missing follow-on | LOW | tasks.md F1..F4 | M-001 closure path (b) needs an F5 follow-on entry. | Add F5 to tasks.md "Follow-on tickets" if M-001 is deferred. |
| L-003 | Documentation clarity | LOW | tasks.md T103 NOTES.md mention | Fixture 11 typed-emission byte shape is named in T103's brief but the exact ADR-style decision (e.g. "constructor's title `SwapOrder` joins with field title `recipient` via underscore to form `:SwapOrder_recipient` predicate; nested constructor recipient at index 1 emits as a fresh bnode with the inner `_:datum1_recipient_pubKeyHash` shape") is not written down before T103 dispatch. Risk of bikeshed at write time. | Add a "Pinned typed-emission byte shape" sub-section to plan.md (after the slice table) or to tasks.md T103's brief covering: top-level constructor → fresh bnode; field → predicate `:<Ctor>_<field>`; `bytes` leaf → `cardano:Identifier` sub-bnode with correct `leafType`; `integer` leaf → `OIntLit`; nested constructor → fresh bnode + recursive typed predicates; `anyOf` → first-match wins (existing decoder semantics). |

## Coverage summary

| Requirement | Has Task? | Task IDs |
|---|---|---|
| FR-001..FR-018 | Yes | T100..T111 |
| SC-001..SC-009 | Yes | cross-slice + T107 (vocab strict 33→34) + T103 (US1 SPARQL) + T108 (cast) |

## Constitution alignment

No conflicts. Plan.md `Constitution gate` section ([plan.md:11-37](./plan.md)) addresses each of the seven principles. Default-Offline reinforced by the rules.yaml-directory-relative blueprint path policy (mirrors `owl:imports`); absolute / `file://` / `http(s)://` paths rejected via the new `AbsoluteBlueprintPath` / `HttpsBlueprintPath` loader errors.

## Unmapped tasks

None.

## Metrics

- Total Requirements: 18 FR + 9 SC = 27
- Total Implementation Tasks: 12 (T100..T111) + 3 pre-implementation (T000..T002)
- Coverage: 100% (every FR + SC has ≥1 task)
- Ambiguity Count: 0 (no [NEEDS CLARIFICATION], no TODO, no TKTK)
- Duplication Count: 0
- Critical Issues: 0
- High Issues: 0
- Medium Issues: 2 (M-001, M-002)
- Low Issues: 3 (L-001, L-002, L-003)

## Next actions

- **No CRITICAL or HIGH issues.** Dispatch first implementation slice (T100 / S0) as planned.
- **MEDIUM follow-ups** (M-001, M-002) — fold into T100/T103 briefs opportunistically; do not block dispatch.
- **LOW follow-ups** — L-001 (slice-order pin) should be folded into the upcoming T100 dispatch's commit-order callout; L-003 (byte-shape ADR) should be written into T103's subagent brief before dispatch.

---

## One-paragraph verdict summary

**GO.** The spec/plan/tasks triangle for #50 is internally consistent and free of CRITICAL or HIGH issues. Every FR maps to a slice and a task; every #50 acceptance row maps to a US + FR + slice (with row 4 correctly deferred to #49 per D-001e); all 14 deliverables surfaces have a wire-up home or are explicitly marked "no per-PR change"; the kmaps Phase A.4 lifecycle decoupling via the vendored pin (FR-009 / T106 → T107 → T109) consistently mirrors the proven #70 / kmaps#55 pattern. Top 3 findings — M-001 (redeemer-path fixture coverage gap), M-002 (`build-fixture.hs` regen wire-up not enumerated in T100), L-001 (commit-order between T105 emit and T107 vocab refresh not explicitly pinned) — are all improve-as-you-go items. The sub-orchestrator may proceed to dispatch T100.

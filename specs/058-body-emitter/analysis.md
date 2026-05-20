VERDICT: LOOP-BACK-TO-tasks: T006 promises fixture-10 GREEN but its leaf scope ("mint + asset-class") does not cover the Vote + TreasuryWithdrawal leaves that research R2 attributes uniquely to fixture 10; SC-005 ("every URI is `cardano:` vocab or `:` local") has no test backing in any slice.

# tx-58 speckit-analyze findings

**Artifacts inspected**

- `specs/058-body-emitter/spec.md`
- `specs/058-body-emitter/plan.md`
- `specs/058-body-emitter/research.md`
- `specs/058-body-emitter/tasks.md`
- `.specify/memory/constitution.md` (v1.0.0, ratified 2026-05-15)

**Metrics**

- Functional Requirements: FR-001 … FR-015 (15)
- Success Criteria:        SC-001 … SC-008 (8)
- User Stories:            US1 … US5 (5; P1×2, P2×3)
- Implementation slices:   T000, T001, T001a, T002 … T014 (15 tasks, one orchestrator gate)
- Coverage % (FR with ≥1 backing task): 13/15 → 86.7%
- Coverage % (SC with ≥1 backing task): 6/8  → 75.0%
- Critical findings: 0
- High findings: 2 (H1, H2)
- Medium findings: 4 (M1–M4)
- Low findings: 3 (L1–L3)
- Constitution conflicts: 0

## Specification Analysis Report

| ID  | Category        | Severity | Location(s)                                            | Summary                                                                                                                                                                                                       | Recommendation                                                                                                                                                                                                                                                  |
|-----|-----------------|----------|--------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| H1  | Coverage gap    | HIGH     | spec.md SC-005:494-496; FR-009:411-415; tasks.md       | SC-005 ("every URI is `cardano:` vocab IRI or `:` fixture-local; no leaked `_internal:`, no external-vocab cross-talk") + FR-009 ("internal helpers MUST NOT mint top-level URIs without going through the vocab module") have **no explicit test backing**. Byte-diff against regenerated `expected.ttl` catches URI deviation only indirectly (and only after the regen is itself accepted). | Add a `VocabTraceabilitySpec` (or extend `EmitGoldenSpec`) that scans the emitter's prefix-declaration list + every IRI in the rendered output and asserts: (a) every prefix is in the allowed set {`cardano:`, `rdfs:`, `:`}; (b) no IRI uses any other namespace; (c) no `_internal:` substring leaks. Cheap; closes SC-005 directly. Wire into T005's GREEN proof or add as T005a. |
| H2  | Inconsistency   | HIGH     | plan.md slice 6:372; tasks.md T006:254-266; research.md R2:65-89 | T006 declares fixture 10 (governance treasury withdrawal) GREEN but scopes its new projection cases to only "mint + policy + assetClass leaves". Research R2 attributes **Vote** and **TreasuryWithdrawal** leaves uniquely to fixture 10 (no other fixture uses them). With T006's stated scope, fixture 10's byte-diff cannot reach GREEN; either T006 expands or fixture 10 moves to T010. | Pick one: (a) extend T006's owned scope to add Vote + TreasuryWithdrawal projection cases (rename to "mint + governance-action leaves"); (b) drop fixture 10 from T006's GREEN list and move it to T010 (which already claims "every leaf type used by any fixture"); (c) split governance-action leaves into a new T009.5 slice. Whichever path, also update the GREEN proof bullets in T006 + T010 so the subagent contract is unambiguous. |
| M1  | Underspecification | MEDIUM | spec.md FR-002:369-372; US5:288-316; tasks.md          | FR-002 ("emitter MUST walk via `Cardano.Tx.Diff.conwayDiffProjection`; direct `Cardano.Ledger.*` calls forbidden") + US5 acceptance scenario 2 ("hypothetical new projection variant → emitter fails with `-Wincomplete-patterns`") are **not enforced by any task**. US5's "static check (Haddock + code-review checklist)" is mentioned but unbacked. | Decide explicitly: either (a) leave it as a code-review-only invariant (note this in T005's commit body) or (b) add a tiny `hlint` rule / module-header `{-# LANGUAGE … #-}` plus a test that imports `Cardano.Tx.Graph.Emit` and `Cardano.Ledger.*` and statically asserts the boundary (e.g. a `cabal-fmt`-style check on imports of `src/Cardano/Tx/Graph/Emit*.hs`). |
| M2  | Sequencing      | MEDIUM   | tasks.md T002:104-128; T003:130-164; T005:204-243; plan D5:213-268 | T003 (CLI flags) lands **before** the Turtle serializer in T005, yet T003's GREEN proof requires the executable to emit overlay + "trailing `# Transaction body.` comment with no triples below it" for joint mode. The canonical Turtle serializer (plan D5) is only built at T005. T003 must either (a) ship a minimal serializer shim or (b) reuse #48's overlay-only render path + a hand-rendered "# Transaction body." literal. Spec/plan don't clarify which. | Add one sentence to T003's "Owned files" or "GREEN proof" pinning the intermediate-serializer story: either explicit T003 ownership of a minimal pre-T005 emitter (e.g. "emits the overlay verbatim then writes `# Transaction body.\n` as a literal trailer") or an acknowledgement that body-only / joint exe modes return an `EmitError NoSerializerYet` at T003 with the smoke test asserting that variant. Avoid the subagent inventing the boundary mid-slice. |
| M3  | Underspecification | MEDIUM | spec.md FR-009:411-415; plan.md architecture:55-73   | FR-009 references "the vocab module" (single source of truth for `cardano:` IRIs) but the plan's architecture diagram does NOT include a `Cardano.Tx.Graph.Emit.Vocab` (or analogous) module. T005's owned-files list (Project.hs + Serialize/Turtle.hs) doesn't either. The vocab terms could end up inlined across multiple modules. | Either name an explicit `Vocab.hs` (or `Emit/Vocab.hs`) module in T005's owned files and pin where the IRIs live, or strike "vocab module" from FR-009 and replace with "vocab term registry (a single top-level constant list)". Pair with H1's traceability spec so the registry is testably the source of truth. |
| M4  | Risk completeness | MEDIUM | plan.md R-1..R-7:441-486; research.md R2 caveats:91-117 | Research R2 caveat #2 acknowledges "predicates not on the kmaps#53 Phase A vocab (e.g., new vocab terms needed for a leaf that the artisan files never had) trigger a research-time decision". This is a known unknown but is NOT elevated to a plan-level R-N risk. The 11 fixtures are claimed within Phase A "by design" — but if regen reveals a gap, the emitter blocks. | Add R-8 to plan.md Risks: "kmaps#53 Phase A vocab term gap — if a fixture's regen needs an IRI not declared in the merged kmaps vocab, the emitter blocks. Mitigation: research R2's enumeration is closed against the artisan layouts before T005; if a gap surfaces at T005–T010, a kmaps PR + cross-PR contract pause is required (escalate via Q-file)." |
| L1  | Style           | LOW      | tasks.md T001a strategy hint:91-95                     | T001a's "Strategy hint" repeats Q-003 → A-003's already-approved "one bulk commit" decision. Slight redundancy with the Q-file log. | Leave as-is (defensive restatement is harmless) or trim to `(see Q-003 → A-003 for the bulk-commit rationale)`. |
| L2  | Terminology     | LOW      | spec.md glossary:551-559; spec.md ¶1-12                 | "Joint graph" defined in glossary as "overlay + body union". Spec body uses both "joint graph" and "joint `expected.ttl`" / "joint Turtle file" — fine but cross-reference would help reviewers. | Optional: add `(joint graph, see Glossary)` annotation on the first non-title body mention (line 23: "one joint Turtle file per fixture"). |
| L3  | Documentation   | LOW      | tasks.md T013:362-378                                  | T013 lists `README.md` + `CHANGELOG.md` + `docs/` (if applicable) but the GREEN proof is "docs render cleanly via `nix develop -c just mkdocs` (if used)". No assertion on **content** (e.g., the three CLI modes documented). | Tighten T013's GREEN proof: "README's `tx-graph` section documents all three modes (overlay-only, body-only, joint); CHANGELOG entry mentions FR-010 + the regen of 11/11 `expected.ttl` files; `docs/` (if applicable) updated for the new flags." |

## Coverage Summary Table

| Requirement | Has Task? | Task IDs                | Notes                                                                                                                            |
|-------------|-----------|-------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| FR-001      | ✓         | T002, T005              | Module + entry-point. Stub in T002; wiring in T005.                                                                              |
| FR-002      | partial   | T005 (impl)             | Implemented by T005's Project.hs but **enforcement** (forbid Cardano.Ledger.* direct calls) has no test. **See M1.**             |
| FR-003      | ✓         | T005, T006–T010         | One triple per leaf, vocab terms. Coverage tracked per fixture across T005–T010.                                                 |
| FR-004      | ✓         | T004                    | Credential lookup → entity bnode or raw-bytes fallback.                                                                          |
| FR-005      | ✓         | T004                    | Raw-bytes naming scheme with N=16 + injectivity property test.                                                                   |
| FR-006      | ✓         | T012                    | Reproducibility / determinism spec.                                                                                              |
| FR-007      | ✓         | T005 (Turtle), T011 (JSON-LD) | Two formats.                                                                                                                |
| FR-008      | ✓         | T003                    | CLI flags + dispatcher.                                                                                                          |
| FR-009      | ✗         | (none)                  | "Every URI traces to vocab module" — no test, no module pinned. **See H1 + M3.**                                                 |
| FR-010      | ✓         | T001                    | RulesLoadResult.rulesEntities field.                                                                                             |
| FR-011      | ✓         | T005–T010               | Cross-PR contract: 11 fixtures byte-equal.                                                                                       |
| FR-012      | ✓         | T003                    | Structured errors on exe failure.                                                                                                |
| FR-013      | ✓         | T004 + T005–T010        | 9 leaf types pinned by #48 + `UnsupportedLeafType` error variant in T002's EmitError.                                            |
| FR-014      | ✓         | every slice via gate    | Haddock enforced by `./gate.sh`'s `cabal haddock` step.                                                                          |
| FR-015      | ✓         | implicit                | Offline-by-default — no I/O in `emit` per plan D9; no test asserts "no network" but in-house serializers ensure by construction. |
| SC-001      | ✓         | T010                    | 11/11 byte-diff under EmitGoldenSpec.                                                                                            |
| SC-002      | ✓         | T003 + T010             | Exe diff = library-path diff. Exe smoke covers fixture 02 in T003; library path covers all 11 by T010.                            |
| SC-003      | ✓         | T011                    | JSON-LD set-equality.                                                                                                            |
| SC-004      | ✓         | T012                    | Back-to-back byte-equality.                                                                                                      |
| SC-005      | ✗         | (none)                  | URI namespacing assertion has no test. **See H1.**                                                                               |
| SC-006      | ✓         | every slice             | `./gate.sh` GREEN per slice; CI mirrors.                                                                                         |
| SC-007      | ✓         | implicit                | `cabal check` clean, no new deps — gate-anchored. No new direct dep is introduced.                                               |
| SC-008      | ✓         | T001                    | T001's GREEN proof explicitly asserts existing `RulesLoadGoldenSpec` stays GREEN after the field addition.                       |

## Constitution Alignment Issues

**No constitution conflicts found.**

- **Principle I (One-Way Dependency)**: The new `Cardano.Tx.Graph.Emit` module imports only from `Cardano.Tx.*` and from `Cardano.Ledger.*` types re-exported via `Cardano.Tx.Diff`. No reverse arrow into `cardano-node-clients` is introduced. ✓
- **Principle II (Module Namespace)**: New module sits under `Cardano.Tx.Graph.*` (graph subtree reserved for epic #46). ✓
- **Principle III (Conway-Only)**: The emitter consumes `ConwayTx` and Conway-era projections. ✓
- **Principle IV (Hackage-Ready)**: FR-014 mandates Haddock; ./gate.sh runs `cabal haddock` per commit. SC-007 asserts `cabal check` clean. ✓
- **Principle V (Strict Warnings)**: Plan D2 explicitly relies on `-Wincomplete-patterns` to surface new projection variants. ✓
- **Principle VI (Default-Offline)**: FR-015 inherits the baseline. ✓
- **Principle VII (TDD / Bisect-Safe)**: Every slice in tasks.md is one bisect-safe commit with RED+GREEN folded. ✓

**Second-opinion on parent's framing of the in-house JSON-LD serializer**

The parent asked specifically whether the in-house JSON-LD serializer (research R1) violates Principle I. **It does not.** Principle I governs the `cardano-tx-tools` ↔ `cardano-node-clients` boundary, not RDF library choice. The in-house decision is grounded in:

- **CLAUDE.md DSL stress-test policy** (project-level convention, not constitution)
- **#48's precedent** (the overlay serializer is already in-house and 11/11 GREEN)
- **Bounded JSON-LD subset** (research R1 explicitly out-of-scopes framing, c14n, typed literals — set-equality acceptance only per SC-003)
- **Zero new direct deps** (`aeson` is already in the dep closure)

This is a sound style choice, not a principle compromise. No analyzer concern.

## Unmapped Tasks

None. Every implementation task (T001–T014) maps to at least one FR / SC. T000 (orchestrator gate) and T001a (NOTES.md migration) are documented as orchestrator-owned / docs-typed respectively; that's the expected shape for this PR's phase-0 + chore work.

## Pre-implementation prereqs — analyzer confirmation

The plan asks the analyzer to confirm PRE-2, PRE-3, PRE-4 (PRE-1 + PRE-5 are locked by Q-001 → A-001 and not in scope).

- **PRE-2 (FR-010 / D7 — loader API extension)**: **CONFIRMED.** Research R5 weighs three alternatives and picks "new field on `RulesLoadResult`" with rationale (backwards-compat at type level via record-update syntax; one canonical loader path; shared in-memory entity list with the overlay serializer). The change is additive — existing `RulesLoadGoldenSpec` byte-diff on `rulesOverlayTurtle` stays GREEN (SC-008). No analyzer concern. T001 enforces the GREEN-preservation contract.
- **PRE-3 (D4 — raw-bytes-bnode prefix N=16)**: **CONFIRMED.** Research R3 pins N=16 with +4-char safety margin over the collision floor. T004's injectivity property test enumerates every fixture's credentials and asserts the projection is injective. If a future fixture violates the property, the test fails RED at fixture-add time and a single-constant bump + regen migration is the remediation path (documented in R3). Analyzer flags only the **non-finding** caveat: the property test must be wired before the first regen slice (T005) so a regression at T006–T010 fails RED on the lookup table, not on the golden. T004 lands at the right point in the sequence.
- **PRE-4 (D8 — flag-presence CLI dispatch)**: **CONFIRMED.** Research R6 weighs three alternatives and picks flag-presence dispatch for back-compat with #48's `--rules`-only invocation. The 5-arm case in `Main.hs` is small and the help text (research R6) spells out the modes. M2 (T003 sequencing) is a tactical clarification, not a PRE-4 reversal.

## Loop-back rationale (verdict explanation)

Two issues warrant tasks.md adjustment before T001 starts:

**H2 (T006 vs fixture-10 leaf scope)** is a tasks-file inconsistency that will surface as a mid-slice contradiction for a subagent. T006's commit-subject reads "mint + policy + assetClass leaves; fixtures 03, 10" but fixture 10's regen cannot reach byte-equal without Vote + TreasuryWithdrawal leaves that T006 does not include in its owned scope. A subagent running T006 either expands the owned scope (breaching the slice contract) or fails GREEN. The fix is a one-line edit to either expand T006 or move fixture 10 to T010 (cheap; orchestrator-level).

**H1 (SC-005 / FR-009 traceability)** is a coverage gap: the spec promises a URI-namespacing invariant that no slice asserts directly. Byte-diff against the regenerated `expected.ttl` catches it only indirectly (and only after the regen is itself accepted into the contract). A small per-emit assertion would close the loop. Fix is to fold a `VocabTraceabilitySpec` into T005 or add T005a.

Neither blocks implementation conceptually — the spec/plan are internally coherent enough that T001–T005 can land without harm. But fixing both before T001 dispatches is cheap (one tasks.md edit) and removes the foreseen subagent contradiction at T006.

**Recommended remediation path** (orchestrator-level):

1. Edit tasks.md T006 to either (a) extend "owned scope" to include `Vote` + `TreasuryWithdrawal` projection cases (rename commit subject accordingly) OR (b) drop fixture 10 from T006's GREEN list and add it to T010's GREEN list.
2. Edit tasks.md T005 (or add T005a) to back SC-005 with a `VocabTraceabilitySpec` (scan emitter output, assert prefixes ∈ {cardano, rdfs, fixture-local}; no `_internal:` substring; no external-vocab IRIs).
3. Optionally fold M2 (T003 sequencing), M3 (`Vocab.hs` module pinning), M4 (R-8 risk on kmaps vocab gaps) into the same edit pass.

These edits do not require a re-spec or a re-plan; they are pure tasks-level clarifications and target the resolve-ticket "Analyzer Loop-back" path. Estimated edit size: <40 lines in tasks.md + a 2-line addition to plan.md Risks.

After the edits land, the artifacts are READY-FOR-IMPLEMENTATION at T001.

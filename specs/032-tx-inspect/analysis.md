# Cross-Artifact Analysis: tx-inspect

**Branch**: `032-tx-inspect` | **Date**: 2026-05-18 | **Analyzer**: speckit-analyze (read-only subagent)

Run by the orchestrator after spec.md, plan.md, and tasks.md were committed. Captures the gaps the analyzer flagged and what was done about each. Mirrors the format of resolve-ticket's Analyzer Subagent return.

## Inputs analyzed

- [spec.md](./spec.md) (17 FR, 7 SC, 4 user stories, 4 clarifications)
- [plan.md](./plan.md) (six slices S1–S6 + S7 orchestrator chore)
- [tasks.md](./tasks.md) (T000..T049 across seven phases)
- [research.md](./research.md), [data-model.md](./data-model.md), [contracts/rules-yaml-grammar.md](./contracts/rules-yaml-grammar.md), [quickstart.md](./quickstart.md)
- [.specify/memory/constitution.md](../../.specify/memory/constitution.md) (seven core principles + operational constraints)

## Coverage map (post-correction)

| Requirement | Status | Backing task(s) |
|---|---|---|
| FR-001 (tx-inspect exe + wiring) | covered | T005, T006, T007 |
| FR-002 (CBOR input forms) | covered | T005 (inherits tx-validate input chain) |
| FR-003 (resolver flags) | covered | T005 |
| FR-004 (RewriteRules + RenameRule types) | covered | T003 |
| FR-005 (additive: no API change) | covered | T012 (byte-stability guard) |
| FR-006 (engine-enforced stage order) | covered | T024 (apply), T002(c) parse, T023a render |
| FR-007 (YAML shape) | covered | T002(a/b/c/d), T003, T024 |
| FR-008 (shared render code path) | covered | T004 extraction; T015a + T033 cross-check |
| FR-009 (rename site list) | covered | T024 (site walker) |
| FR-010 (best-effort unknown leaf) | covered | T023 |
| FR-011 (`rules/amaru-treasury.yaml`) | covered | T032 |
| FR-012 (Golden #1 pure collapse) | covered | T014 |
| FR-013 (Golden #2 pure rename) | covered | T022 |
| FR-014 (Golden #3 both stages + cross-check) | covered | T033 |
| FR-015 (docs) | covered | T039, T040 |
| FR-016 (`--version` / `--help` / env var) | **covered (patched)** | T011 (three smoke assertions) |
| FR-017 (release pipeline) | covered | T044, T045 |
| SC-001 | covered | T033 |
| SC-002 | covered | T002(a) |
| SC-003 | covered | T033 cross-check |
| SC-004 (stage order invariant under YAML key order) | **covered (patched)** | T002(c) parse, T023a render |
| SC-005 (`tx-inspect --version`) | **covered (patched)** | T011 (smoke assertion #1) |
| SC-006 | covered | T023 |
| SC-007 | covered | T044, T045 |
| US1 Acceptance | covered | T033 |
| US2 Acceptance #1 | covered | T014 |
| US2 Acceptance #2 (existing collapse-only YAML → tx-inspect output == one side of tx-diff) | **covered (patched, with fallback)** | T015a (self-diff cross-check; falls back to T033 evidence if tx-diff self-diff does not emit a per-side render — subagent reports the chosen path in `WIP.md`) |
| US3 Acceptance | covered | T022 |
| US4 Acceptance | covered | T033 |

## Findings from the analyzer (and what we did)

### CRITICAL — none

### MEDIUM — patched

- **G1 / FR-016 / SC-005**: no `--version` / `--help` / banner-suppression smoke. **Patched**: T011 now carries three smoke assertions (exit-0 + version line; `--help` exit 0; `TX_INSPECT_NO_UPDATE_CHECK=1` banner suppression).
- **SC-004**: no test asserts stage-order invariance under YAML key order. **Patched**: T002(c) covers the parse-level invariance (key order in `parseRewriteRulesYaml`); T023a covers the render-level invariance (engine always runs collapse before rename regardless of how `RewriteRules` was constructed).
- **G3 / Edge case "Unresolved input under rename"**: no apply-level test. **Patched**: T023 now includes the unresolved-input edge case.
- **`Rewrite.LoadSpec` rename-parsing coverage**: T002 was scoped to legacy-compat only. **Patched**: T002 expanded to four sub-cases — (a) legacy compat, (b) rename-section parse (all kinds + parse errors), (c) stage-order invariance, (d) empty document.
- **US2 Acceptance #2**: explicit cross-check missing. **Patched**: T015a added — a collapse-only self-diff cross-check, with an explicit fallback to T033's Amaru cross-check if tx-diff's self-diff mode does not emit a per-side render; the subagent reports the chosen path in WIP.md.

### MEDIUM — addressed by clarification (no code change)

- **C1 / T035 wording**: T035 now explicitly states it is a non-blocking contingency that is marked complete on slice acceptance when no gap was found.
- **R-E / T029 fallback owner**: T029 now names the fallback chain (Amaru journal → Blockfrost → orchestrator-chosen recipe / synthetic stand-in / defer) and emphasises **the subagent never silently substitutes a synthetic fixture**.

### LOW — accepted as-is

- **D1**: Golden #1/#2/#3 are listed in both spec.md (FR-012/013/014) and plan.md (Proof Strategy table). Intentional — spec is the contract, plan summarises for slice ownership.
- **I2**: plan.md's per-slice forecast IDs (T001-T006 for S1) is stale; the actual S1 owns T001-T011. tasks.md is the authority; plan.md's forecast lines are intentionally non-authoritative ("forecast"). No change.
- **I4**: CLAUDE.md header reads "cardano-tx-tools-issue-8 Development Guidelines". Stale from earlier feature. Cosmetic; not in scope.
- **R-B**: S6 operator follow-up is in PR body, not in tasks.md as a tracked item. Per workflow that is the correct location (operator follow-up belongs in the PR body, not the tasks list).
- **R-C**: "first matching rule wins" conflict policy is silently shipped. Documented in [data-model.md § Conflict Resolution](./data-model.md); no test required because conflict resolution is out-of-scope per spec.
- **R-D**: S5 grammar-doc location open question (T037) handles the contingency at slice time.
- **CA store assertion for tx-inspect** (constitution operational constraint): tx-inspect does not perform HTTPS itself; the CA bundling is inherited from the existing flake `makeWrapper` over `apps.tx-inspect`. No additional task needed; called out in plan.md Constitution Check.

## Resolve-ticket invariants — slice vs commit conformance

Walked all six invariants; **all pass**:

1. One slice = one bisect-safe commit — six slices, six commits, plus S7 chore. ✓
2. RED before GREEN folded into one commit — every slice's tasks.md section names RED tasks before GREEN tasks. ✓
3. `Tasks:` trailer on every behavior-changing commit — T012 / T020 / T028 / T036 carry trailers; T042 (docs) / T046 (chore) exempt per commit message gate. ✓
4. Vertical bisect-safe slices — each slice ships a compiling, testing executable. ✓
5. Live-boundary smoke or named operator follow-up for every behavior change — S1–S4 ship per-slice gate.sh smokes; S5 docs uses `mkdocs --strict`; S6 has in-repo grep gate + named operator follow-up (paolino, `gh release view`). ✓
6. `Tasks:` trailer accuracy — T012's trailer lists T001..T011; T020's trailer updated to include T015a; T028's trailer updated to include T023a. ✓

## Constitution check (post-correction)

Seven principles + operational constraints — **all pass**. Documented in [plan.md § Constitution Check](./plan.md#constitution-check); no exceptions tracked; complexity-tracking table empty.

## Final verdict

**Ready for implementation.** All MEDIUM gaps addressed in tasks.md by the corrections above; the four LOW items are accepted as-is with rationale; the resolve-ticket invariants pass; no constitution violations.

Re-running the analyzer is **not gated** — the corrections are mechanical (adding test sub-cases and a smoke block to a recipe), explicitly enumerated above, and self-verifiable by `grep "T011\|T002\|T015a\|T023a" tasks.md`. The next phase is the S1 implementation subagent.

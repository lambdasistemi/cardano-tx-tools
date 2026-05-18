# Specification Quality Checklist: collapse engine — nested rules + `raw: omit`

**Purpose**: Validate specification completeness and quality before proceeding to planning.
**Created**: 2026-05-18
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details bleed into the requirements section beyond what the issue itself names (Haskell field names appear because the issue does; this is a library-API ticket and the field shape is part of the contract).
- [X] Focused on user value (treasury reviewer scanning a 33-chunk swap as one bucket) and the migration safety property (every existing rules YAML still parses).
- [X] Written so a non-Haskell reviewer can read US1–US5 and Edge Cases without needing the engine internals.
- [X] All mandatory sections completed.

## Requirement Completeness

- [X] No `[NEEDS CLARIFICATION]` markers remain.
- [X] Every FR is testable: FR-001–FR-009 are unit-testable in `Rewrite.LoadSpec` / `Rewrite.ApplySpec`; FR-010–FR-013 are golden / fixture assertions; FR-014 is a docs-check; FR-015 is a cross-tool golden.
- [X] Success criteria are measurable: SC-001 (≤ 5% line-count), SC-002 / SC-003 (zero regressions), SC-004 (depth-3 fixture), SC-005 (no-op identity), SC-006 (parse-error message shape), SC-007 (cross-tool render equality).
- [X] Success criteria mostly technology-agnostic — they cite the *behaviour* of the rendered output, not framework choices. The Haskell type names that appear (e.g. `CollapseRule`, `CollapseRawView`) are unavoidable because they are the public-API surface the issue extends, and the user (the issue author) named them explicitly.
- [X] All acceptance scenarios are stated for every user story.
- [X] Edge cases identified (10 cases).
- [X] Scope clearly bounded (explicit Out-of-Scope section, six exclusions matching the issue).
- [X] Dependencies and assumptions listed (Assumptions section, four entries).

## Feature Readiness

- [X] Every FR maps to a user story:
  - US1 → FR-001/002/003/005/006/007/009/010
  - US2 → FR-002 (legacy) / FR-008 / FR-011 (legacy compat tests)
  - US3 → FR-003 / FR-007 (under `show`/`hide`) / FR-012
  - US4 → FR-005/006/007/008 / FR-012
  - US5 → FR-004 / FR-012 (depth > 1)
  - Cross-tool symmetry → FR-015
- [X] User scenarios cover the primary flows (one P1 motivating story + one P1 backwards-compat story + three orthogonal-axis P2/P3 stories).
- [X] Feature meets the measurable outcomes in SC-001–SC-007.
- [X] No implementation tactics (which module to edit, which function to add) leak into the spec — those decisions are deferred to plan.md.

## Notes

- The spec deliberately commits to the exact Haskell type / field names from the issue (`collapseRuleNested`, `CollapseRawOmit`) because the issue is a library-API ticket whose public surface IS the contract. Treating those as "implementation details to defer to planning" would dilute the spec into restating the issue with fewer constraints.
- US1 and US2 are co-P1: the feature is incomplete if either fails. Implementation slicing should NOT separate them — every implementation slice that touches the engine MUST keep the US2 regression contract green via the existing #032 goldens before adding US1 behaviour.
- US5 (depth > 1) is P3 because no current fixture exercises depth > 2 (`SwapOrder` → `ScopeOwners` is depth 2). The spec still commits to arbitrary depth so future identifier-family follow-ups don't require an engine re-architecture.

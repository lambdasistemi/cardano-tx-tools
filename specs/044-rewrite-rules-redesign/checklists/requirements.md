# Specification Quality Checklist: Rewrite-rules redesign

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-05-19
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs) — internal ADT shape is referenced only in the discussion section because the user explicitly asked for an ADT redesign; the user-facing surface (YAML grammar, rendered output) carries the FRs.
- [x] Focused on user value and business needs — reviewer-facing cross-leaf identity is the load-bearing goal stated in every section.
- [x] Written for non-technical stakeholders — yes for User Scenarios and Success Criteria; the Background and Clarifications sections are necessarily technical because they motivate an ADT redesign.
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous — each FR maps to at least one User Story's Acceptance Scenarios
- [x] Success criteria are measurable — SC-001 (10/10 goldens), SC-002 (≥2/3 reviewer recall), SC-006 (<500ms render)
- [x] Success criteria are technology-agnostic — render-time budget is the only borderline case; described purely as "developer laptop"
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified — 8 edge cases covering loader rejection, blueprint absence, blueprint failure, role-class collision, path absence, blueprint-decoded-path collapse interaction
- [x] Scope is clearly bounded — Assumptions section identifies what is deferred (predicate DSL, rule generator, blueprint override map)
- [x] Dependencies and assumptions identified — CIP-57 stability, predicate DSL downstream, loader backwards compatibility

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria — FR-001..FR-016 each map to specific user stories
- [x] User scenarios cover primary flows — P1 (cross-leaf identity), P2 (each identifier role + collapse properties), P3 (governance)
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification — modulo the deliberate ADT discussion in Background, which is part of the spec's motivation per user direction

## Cross-references against open tickets

Closing this spec must close or refine each of:

| Issue | Story | Closure mechanism |
|---|---|---|
| #34 stake | Story 5 | Role class `StakeScript` / `StakeKey`, `from-address` loader sugar |
| #35 pool | Story 6 | Role class `PoolId`, `pool: <bech32>` loader sugar |
| #36 DRep | Story 7 | Role classes `DRepKey` / `DRepScript`, `drep: <bech32>` loader sugar |
| #37 asset-policy | Story 3 + Story 4 | Role class `Policy`; `AssetClass` for the asset; same entity under both roles allowed |
| #38 asset-name | Story 3 | Role class `AssetClass` with compound `(policy, name)` key |
| #39 datum rename | Story 1 + Story 9 | Blueprint decode produces typed leaves; same entity index fires |
| #40 nested collapse + raw:omit | Story 1 + Story 9 | `nested:` field + per-rule `view: omit` |
| #43 collapse-suppresses-rename | Story 8 | Typed-leaf walker descends into matched subtree; rename always fires |

## Notes

- Items marked incomplete require spec updates before `/speckit.clarify` or `/speckit.plan`
- Per project policy (no_specs_means_invented, speckit_stop_at_spec): no `/speckit.plan` and no `/speckit.tasks` until the user approves spec.md.
- Per user direction in this session: the test-fixture harness is a separate ticket; this spec assumes it as a dependency rather than absorbing the work.

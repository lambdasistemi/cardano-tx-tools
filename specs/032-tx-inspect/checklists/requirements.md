# Specification Quality Checklist: tx-inspect — shared-substrate transaction renderer

**Purpose**: Validate specification completeness and quality before proceeding to planning.
**Created**: 2026-05-18
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
  - *Note*: Spec names existing Haskell types (`CollapseRule`, `OpenValue`, etc.) and Haskell modules (`Cardano.Tx.Diff.Resolver`) because issue #32 explicitly anchors the additive refactor on those types and those modules. That is not implementation freedom for the planner — it is the load-bearing additivity contract.
- [x] Focused on user value and business needs (treasury reviewer use case is P1)
- [x] Written for non-technical stakeholders (the user stories are operator-facing)
- [x] All mandatory sections completed (User Scenarios, Requirements, Success Criteria)

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
  - *Status*: Four clarifications recorded under "Clarifications > Session 2026-05-18" in `spec.md` and applied to FR-004 (module name = `Cardano.Tx.Rewrite`), FR-007 (YAML shape = the existing top-level `{ version?, views?, collapse? }` object extended with an additional optional `rename:` key — additive only; no "legacy bare-list" form ever existed, corrected after code inspection of `parseCollapseRulesYaml`), FR-009 + Key Entities (`RenameRule` shape = `{ kind, key, name, match? }` with `match: full | payment`), and the Edge Cases section (payment-credential-only matching for base addresses with differing stake credentials).
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined (FR-012/13/14 + per-story Acceptance Scenarios)
- [x] Edge cases are identified (unknown identifier, collapse-only, rename-only, empty rules, unresolved input, --version/--help, banner)
- [x] Scope is clearly bounded (Out of Scope section enumerates explicit exclusions from issue #32)
- [x] Dependencies and assumptions identified (Assumptions section)

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria (each FR maps to a user-story scenario or SC measurement)
- [x] User scenarios cover primary flows (P1 = the operator command path; P2 = collapse-only, rename-only, shared-substrate)
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification beyond the additivity anchors required by the issue

## Notes

- All clarifications resolved in the 2026-05-18 session — spec is ready for `/speckit.plan`.
- Two questions deferred to clarification per the issue body are answered: module name (`Cardano.Tx.Rewrite`) and YAML shape (sectioned `collapse:`/`rename:` with legacy bare-list compatibility).
- Two additional questions surfaced by the structured ambiguity scan are also answered: the `RenameRule` entry shape (kind-tagged record) and address-match granularity (`match: full | payment`, defaulting to `payment`).

# Specification Quality Checklist: collapse no longer disables rename for `required:`-pinned leaves

**Purpose**: Validate specification completeness and quality before proceeding to planning.
**Created**: 2026-05-18
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details bleed into the requirements section beyond the named typed-value identifiers (`ConwayAddressValue`, `ConwayScriptValue`, `ConwayReferenceScriptValue`). These appear because the bug is about typed-identity preservation in the engine, and the type names are the contract.
- [X] Focused on operator value (the reviewer's "same address, same name everywhere" expectation) and the backwards-compatibility regression contract (every existing golden stays byte-identical).
- [X] Written so a non-Haskell reviewer can read US1–US5 + Edge Cases without engine internals.
- [X] All mandatory sections completed.

## Requirement Completeness

- [X] No `[NEEDS CLARIFICATION]` markers remain.
- [X] Every FR is testable: FR-001 / FR-002 / FR-003 are observable in the golden tests; FR-004 is the backwards-compat fallback path; FR-005 is the cross-bucket grouping property; FR-006 is the zero-recapture invariant; FR-007 / FR-008 / FR-009 are explicit new `it` blocks; FR-010 is a grep assertion on the docs; FR-011 is a `cabal check` assertion.
- [X] Success criteria are measurable: SC-001 (string-identical address rendering), SC-002 (zero golden recaptures), SC-003 (kind:script render), SC-004 (grep-no-match), SC-005 (single index-range row), SC-006 (regression-catching property test), SC-007 (cabal check clean).
- [X] Success criteria mostly technology-agnostic. The Haskell type names that appear (`ConwayAddressValue`, `ConwayScriptValue`) are unavoidable because they are the typed-value identities the engine fix preserves.
- [X] All acceptance scenarios stated for every user story.
- [X] Edge cases identified (7 cases including the load-bearing cross-bucket grouping case).
- [X] Scope bounded (explicit Out-of-Scope, 7 exclusions matching the issue + the additional "no opt-in flag" exclusion).
- [X] Dependencies and assumptions listed.

## Feature Readiness

- [X] Every FR maps to a user story:
  - US1 → FR-001 / FR-003 / FR-004 / FR-005 / FR-008
  - US2 → FR-006 (the zero-recapture regression contract)
  - US3 → FR-002 / FR-009 (symmetric script-hash axis)
  - US4 → FR-010 (docs deletion)
  - US5 → FR-007 (cross-stage property)
- [X] User scenarios cover the primary flows (two co-P1 stories — the operator fix + the backwards-compat invariant; one co-P1 for symmetric script-hash; two P2 for docs + property test).
- [X] Feature meets the measurable outcomes in SC-001–SC-007.
- [X] No implementation tactics (which function to edit, which type to change) leak into the spec — those are deferred to plan.md.

## Notes

- The spec elevates the cross-bucket grouping change (FR-005 / SC-005) to first-class even though the issue does NOT call it out. Engine inspection showed it's a load-bearing edge case: today the grouping compares raw `Aeson.Value`s, but after the typed-snapshot fix, two addresses sharing a payment credential but differing in stake credential would both render as the same rename name yet appear as separate index-range rows. The spec promotes this so the implementation cannot accidentally regress on it.
- US2 (backwards compatibility) is co-P1 with US1, NOT P2. The whole point of a defect fix in a shared engine is that other operators' workflows don't break as collateral. Tagging US2 as anything less than P1 would invite a "ship the fix, accept the recapture noise" shortcut, which is wrong.
- The spec deliberately commits to fixing both the `kind: address` and `kind: script` axes in one engineering change (US3 / FR-002). The issue speculates the script defect exists; engine inspection confirmed it. Splitting into two PRs would be worse — one engine seam, one orthogonality fix.
- The docs deletion (US4 / FR-010) is intentionally permissive in wording: it requires the workaround section to be gone but lets the doc author rewrite the surrounding context as needed. This avoids over-prescribing the doc shape at spec time.

# Specification Quality Checklist: Phase-1 self-validation for signed transactions

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-05-15
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
  - The function signature in FR-001 is intentionally surfaced as a contract — the issue called it out and the predecessor PR added the scaffolding types. This is contract, not implementation. Module path and synthesis details are left to `/speckit.plan`.
- [x] Focused on user value and business needs — signing pipeline gets a callable gate before submission.
- [x] Written for non-technical stakeholders where possible — the technical surface is unavoidable (callable library function), but the user stories are framed around the workflow (sign → validate → submit).
- [x] All mandatory sections completed (User Scenarios, Requirements, Success Criteria).

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain.
- [x] Requirements are testable and unambiguous (each FR has a corresponding SC or acceptance scenario).
- [x] Success criteria are measurable (SC-001..SC-006 are observable from `nix flake check` + grep + fixture diffs).
- [x] Success criteria are technology-agnostic where it makes sense; where they reference Haskell types (`ConwayTx`, `ApplyTxError`) they do so because the spec inherits a contract from PR #9 and the issue itself.
- [x] All acceptance scenarios are defined (Story 1 has four, Story 2 has one).
- [x] Edge cases are identified (mempool short-circuit on duplicate-detection, empty UTxO, NetworkId mismatch, AccountState seeding, default-offline test discipline).
- [x] Scope is clearly bounded (see "Out of Scope" section).
- [x] Dependencies and assumptions identified ("Assumptions" section; relies on `cardano-ledger-api` `applyTx` and existing PR-#9 scaffolding).

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria (FR-001..FR-010 each tie to a Story / SC).
- [x] User scenarios cover primary flows (sign-then-validate and full-failure-collection).
- [x] Feature meets measurable outcomes defined in Success Criteria.
- [x] No implementation details leak into specification beyond the contract surface inherited from PR #9 and explicitly called out in the issue.

## Notes

- The signature in FR-001 is contractual (taken from the issue verbatim, refined to add `NetworkId`). The plan/tasks phase decides on the module path, the synthesis helpers, and the test-fixture layout.
- **Pre-flight shape (vs the original post-signing framing)**: helper runs against the UNSIGNED `ConwayTx` that `buildWith` returns. `applyTx` always raises `MissingVKeyWitnesses` / native-script-signature failures on unsigned input — these are documented as expected noise; FR-010 forces the docstring to enumerate them so caller filters are greppable. This was a course correction after the first draft framed the helper as post-signing — the user chose pre-flight (unsigned, no filtering inside the helper).
- **Implementation strategy: inline, not depend.** [`cardano-ledger-inspector`](https://github.com/lambdasistemi/cardano-ledger-inspector) already has the recipe in [`Conway.Inspector.Validation`](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs); we deliberately duplicate the ~60-line kernel rather than take a cross-repo source-repository-package pin. The kernel is small enough that the pin cost outweighs the LoC saved, and tx-tools doesn't yet have a second use case for inspector's other operations. Upstream ticket [inspector#73](https://github.com/lambdasistemi/cardano-ledger-inspector/issues/73) is the consolidation hook if the picture changes.
- Open question for `/speckit.plan`: whether `validatePhase1` lives in `Cardano.Tx.Ledger` (extending the existing module) or in a new `Cardano.Tx.Validate` module. Defer.

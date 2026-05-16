# Specification Quality Checklist: tx-validate CLI

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-05-16
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
  - The CLI flag names + library module path are part of the contract (the user is the shell, and the flags ARE the user-facing API). Beyond that, no language / framework choice leaks. The fact that the library is Haskell is inherited from the project context, not invented here.
- [x] Focused on user value and business needs — signing pipelines / CI gates get a callable validator without writing Haskell.
- [x] Written for stakeholders — Story-driven; technical surface is the CLI shape, which is the user-facing API.
- [x] All mandatory sections completed (User Scenarios, Requirements, Success Criteria).

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain.
- [x] Requirements are testable and unambiguous (each FR has a matching SC or acceptance scenario).
- [x] Success criteria are measurable (exit-code-driven; reproducible against committed fixtures; observable from `nix flake check`).
- [x] Success criteria are technology-agnostic in spirit (SC-001 is exit-code, SC-002 / SC-003 are reproducible against fixtures across three resolver sources, SC-005 / SC-006 are pipeline-level).
- [x] All acceptance scenarios are defined (Story 1 has three, Story 2 has three, Story 3 has two).
- [x] Edge cases are identified (no resolver supplied, both supplied, `--output` invalid, CBOR decode failure, mempool short-circuit, stdin input, empty input, network-access opt-in).
- [x] Scope is clearly bounded (see "Out of Scope").
- [x] Dependencies and assumptions identified (existing `Resolver` chain, `Provider` calls, Blockfrost endpoints, env var convention).

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria (FR-001..FR-012 each map to a Story / SC).
- [x] User scenarios cover primary flows (local-N2C, Blockfrost, chain-fallback).
- [x] Feature meets measurable outcomes defined in Success Criteria.
- [x] No implementation details leak beyond the user-facing CLI contract.

## Notes

- **Resolver reuse**: the spec re-uses `Cardano.Tx.Diff.Resolver*` as-is. The "rename to `Cardano.Tx.Resolver.*`" path is explicitly out of scope; recorded in Assumptions.
- **Network access**: opt-in via flags, never via env-only fallback.
- **Scope reduction (2026-05-16)**: the Blockfrost-side resolver session (originally User Stories 2 + 3) is deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21). Reason: Blockfrost's `/epochs/latest/parameters` JSON shape is incompatible with `cardano-ledger-conway`'s `FromJSON (PParams ConwayEra)` instance; bridging it requires a custom ~50-field decoder that doesn't fit this PR's scope. v1 is N2C-only.

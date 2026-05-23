# Implementation Plan: Amaru disburse DSL fixtures

**Branch**: `90-amaru-disburse-fixtures-dsl` | **Date**: 2026-05-23 |
**Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from
`specs/090-amaru-disburse-fixtures-dsl/spec.md`

## Summary

Add two DSL-reconstructed rewrite-redesign fixtures for real
amaru-treasury disburse transactions: network-compliance fixture 15 and
contingency fixture 17. The fixtures pin the current SchemaMap typed
output from #80, including the opaque child bnode for the
`OpenArray [OpenObject {"key", "value"}]` amount shape. Per A-001, this
PR does not change typed-emit walker semantics or blueprint decoding code.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via the existing Nix shell  
**Primary Dependencies**: Existing `cardano-tx-tools` library, CIP-57
blueprint loader, rewrite-redesign fixture harness  
**Storage**: Checked-in fixture modules, fixture directories, and golden
outputs  
**Testing**: Hspec unit/golden specs through `just unit`; full gate
through `./gate.sh`  
**Target Platform**: Offline Conway transaction tooling  
**Project Type**: Haskell library + CLI test harness  
**Performance Goals**: No runtime performance target; fixture
verification must remain deterministic and byte-stable  
**Constraints**: No new `cardano:*` vocab predicates, no
`src/Cardano/Tx/Graph/Emit/*` changes, no `src/Cardano/Tx/Blueprint.hs`
changes, no release-pipeline surfaces, no changes to other repositories,
no pre-built CBOR fixture construction  
**Scale/Scope**: Two fixture directories, two DSL builder modules, one
shared blueprint fixture, golden enumeration, fixture notes, changelog

## Constitution Check

- **One-Way Dependency**: Pass. The work consumes local source
  transaction artifacts and does not introduce reverse dependencies.
- **Module Namespace**: Pass. New Haskell modules live in the established
  fixture namespace.
- **Conway-Only**: Pass. Both fixtures mirror Conway transactions.
- **Hackage-Ready Quality**: Pass if `./gate.sh` succeeds, including
  `cabal check` and Haddock.
- **Strict Warnings**: Pass if `just build` and `just unit` succeed under
  the existing warning set.
- **Default-Offline Semantics**: Pass. Committed fixtures are
  self-contained and do not require live network resolution.
- **TDD With Vertical Bisect-Safe Commits**: Pass. Each fixture lands as
  a reviewed driver+navigator slice; task checkboxes are amended into the
  same slice commit during acceptance.

## Project Structure

### Documentation (this feature)

```text
specs/090-amaru-disburse-fixtures-dsl/
├── spec.md
├── checklists/requirements.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── analysis.md
└── tasks.md
```

### Source Code And Fixtures

```text
test/Cardano/Tx/Graph/EmitGoldenSpec.hs
test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/
test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/
test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S15_AmaruDisburseNetworkCompliance.hs
test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S17_AmaruDisburseContingency.hs
test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json
CHANGELOG.md
gate.sh
```

**Structure Decision**: Use the established rewrite-redesign fixture
layout. The new blueprint is shared under `blueprints/` and referenced
from fixture-local `rules.yaml` files. Fixture modules follow the S11
DSL reconstruction pattern.

## Owned File Set

Worker-owned implementation files:

- `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S15_AmaruDisburseNetworkCompliance.hs`.
- `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S17_AmaruDisburseContingency.hs`.
- `test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/{rules.yaml,expected.ttl,expected.entities.ttl,expected.txt,NOTES.md}`.
- `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/{rules.yaml,expected.ttl,expected.entities.ttl,expected.txt,NOTES.md}`.
- `test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json`.
- `test/Cardano/Tx/Graph/EmitGoldenSpec.hs`.
- `CHANGELOG.md`.
- `specs/090-amaru-disburse-fixtures-dsl/tasks.md` checkbox updates only,
  amended into the worker commits during acceptance.

Orchestrator-owned files:

- `specs/090-amaru-disburse-fixtures-dsl/*`.
- `gate.sh` lifecycle commits and final PR metadata.

Forbidden without Q-file:

- Any new `cardano:*` vocabulary predicate.
- Any `src/Cardano/Tx/Graph/Emit/*` change.
- Any `src/Cardano/Tx/Blueprint.hs` change.
- Changes to `amaru-treasury-tx`, `amaru-treasury`, or any other
  repository.
- `.github/`, `flake.nix`, `nix/`, or `docs/`.
- Non-DSL fixture construction, including loading pre-built CBOR from the
  test harness.

## Vertical Slices

| Slice | Subject | Commit Subject | Tasks |
|---|---|---|---|
| S0 | Bootstrap committed `gate.sh` for this draft PR. | `chore: add gate.sh for issue 90` | T000 |
| S1 | Spec Kit requirement artifacts. | `docs(090): specify amaru disburse fixture requirements` | T001 |
| S2 | Plan, research, data model, quickstart, task list, and analysis. | `docs(090): plan amaru disburse fixture implementation` | T002-T004 |
| S3 | Worker implementation: fixture 15 network-compliance DSL builder, fixture files, shared blueprint if not already present, golden enumeration, provenance notes, focused and full gate proof. | `feat(090): amaru-disburse network-compliance fixture` | T200-T208 |
| S4 | Worker implementation: fixture 17 contingency DSL builder, fixture files, golden enumeration/provenance, focused and full gate proof. | `feat(090): amaru-disburse contingency fixture` | T300-T307 |
| S5 | Mechanical changelog and final accepted feature commit shape if slices are squashed by the pair or reviewer policy requires one final feature commit. | `feat(090): amaru-disburse fixtures (network_compliance + contingency)` | T400 |
| S6 | Drop gate and mark PR ready after final audit. | `chore(090): drop gate.sh (ready for review)` | T401 |

The preferred final reviewer-facing behavior subject is
`feat(090): amaru-disburse fixtures (network_compliance + contingency)`.
If separate fixture commits remain, the ticket owner must coordinate with
the epic owner before final history shaping; implementation workers still
produce one bisect-safe commit per slice and do not push.

## Test Strategy

### RED/GREEN Contract For Fixture Slices

Each fixture slice must create RED evidence before GREEN:

- The golden enumeration or focused golden check fails before the new
  fixture directory and builder module exist.
- The expected output fails byte equality until generated from the
  current emitter.
- The fixture notes/provenance and traceability requirements are checked
  before commit handoff.

The GREEN commit must then:

- add the DSL builder module for the slice;
- add the fixture directory and golden files;
- register the Sundae treasury blueprint through `rules.yaml`;
- enumerate the fixture in `EmitGoldenSpec`;
- preserve fixtures 01 through 14;
- run `./gate.sh` successfully.

### Focused Commands For The Pair

Minimum focused checks before the full gate:

```sh
nix develop --quiet -c just unit
./gate.sh
```

The pair may use narrower Hspec patterns after inspecting local test
recipes, but acceptance requires the full gate.

### Live-Boundary Diagnostic

The load-bearing boundary is real Conway transaction shape plus real
CIP-57 blueprint metadata crossing into the typed RDF emitter. Fixture 15
may use live/source inspection to reconstruct the shape, but committed
fixtures remain offline. Fixture 17 is explicitly self-contained because
the on-chain inputs are spent. If either source shape cannot be mirrored
with the DSL, the worker pair must Q-file.

## PR Lifecycle

The PR stays draft during implementation. The ticket owner verifies each
worker commit, amends task checkboxes into that commit, re-runs
`./gate.sh`, and records status before push or final history
coordination. Finalization drops `gate.sh` only after all tasks are
checked, the final gate is green, and the commit-message audit passes.

# Implementation Plan: Real Conway amaru disburse fixtures

**Branch**: `80-amaru-disburse-fixtures` | **Date**: 2026-05-22 |
**Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from
`specs/080-amaru-disburse-fixtures/spec.md`

## Summary

Add three real Conway disburse fixtures sourced from
`amaru-treasury-tx/transactions/` and close the observed CIP-57
JSON-Pointer resolver gap by decoding RFC 6901 `$ref` tokens before
definition lookup. The implementation is one vertical paired-worker slice:
RED unit/golden coverage first, GREEN resolver + fixture vendoring +
changelog, `./gate.sh` green, and one final behavior commit with a
`Tasks:` trailer.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via the existing Nix shell  
**Primary Dependencies**: Existing `cardano-tx-tools` library, CIP-57
blueprint decoder, rewrite-redesign fixture harness  
**Storage**: Checked-in fixture files and golden outputs  
**Testing**: Hspec unit/golden specs through `just unit`; full gate through
`./gate.sh`  
**Target Platform**: Offline Conway transaction tooling  
**Project Type**: Haskell library + CLI test harness  
**Performance Goals**: No measurable runtime target; fixture verification
must remain deterministic and byte-stable  
**Constraints**: No new `cardano:*` vocab predicates, no
`leafTypeFromFieldName` work, no release-pipeline surfaces, no changes to
`amaru-treasury-tx`  
**Scale/Scope**: Three fixture directories plus one narrow blueprint
resolver change and changelog entry

## Constitution Check

- **One-Way Dependency**: Pass. The work stays inside this repository and
  consumes fixture inputs; it does not introduce reverse dependencies into
  `cardano-node-clients`.
- **Module Namespace**: Pass. The only production surface is an existing
  `Cardano.Tx.*` module.
- **Conway-Only**: Pass. All fixtures are Conway transactions and no
  pre-Conway support is introduced.
- **Hackage-Ready Quality**: Pass if `./gate.sh` succeeds, including
  `cabal check` and Haddock.
- **Strict Warnings**: Pass if `just build` and `just unit` succeed under
  the existing warning set.
- **Default-Offline Semantics**: Pass. Fixtures are local files; no live
  network lookup is required by the implementation slice.
- **TDD With Vertical Bisect-Safe Commits**: Pass. One worker-owned
  behavior slice folds RED+GREEN into one commit, and orchestration docs
  commits are separate non-behavior commits.

## Project Structure

### Documentation (this feature)

```text
specs/080-amaru-disburse-fixtures/
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
src/Cardano/Tx/Blueprint.hs
test/Cardano/Tx/BlueprintSpec.hs
test/Cardano/Tx/Graph/EmitGoldenSpec.hs
test/fixtures/rewrite-redesign/15-amaru-disburse-minimal/
test/fixtures/rewrite-redesign/16-amaru-disburse-multisig/
test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/
test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S15..S17*.hs
CHANGELOG.md
gate.sh
```

**Structure Decision**: Use the existing rewrite-redesign fixture layout
and existing blueprint resolver module. The pair must inspect established
fixture patterns before adding shims, but the orchestrator will not read or
edit worker-owned code.

## Owned File Set

Worker-owned implementation files:

- `src/Cardano/Tx/Blueprint.hs` — narrow extension to
  `resolveBlueprintSchema` only.
- `test/Cardano/Tx/BlueprintSpec.hs` — focused RFC 6901 `$ref`
  invariant.
- `test/fixtures/rewrite-redesign/15-amaru-disburse-minimal/{rules.yaml,expected.ttl,expected.entities.ttl,expected.txt,NOTES.md}`.
- `test/fixtures/rewrite-redesign/16-amaru-disburse-multisig/{rules.yaml,expected.ttl,expected.entities.ttl,expected.txt,NOTES.md}`.
- `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/{rules.yaml,expected.ttl,expected.entities.ttl,expected.txt,NOTES.md}`.
- `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S15..S17*.hs`
  if the existing harness requires per-fixture builder shims.
- `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` — enumerate fixtures 15..17.
- `CHANGELOG.md` — one Unreleased / Features bullet.
- `specs/080-amaru-disburse-fixtures/tasks.md` — checkbox updates only,
  amended into the worker commit during acceptance.

Orchestrator-owned files:

- `specs/080-amaru-disburse-fixtures/*`.
- `gate.sh` lifecycle commits and final PR metadata.

Forbidden without Q-file:

- Any new `cardano:*` vocabulary predicate.
- `leafTypeFromFieldName` lookup-table work.
- Changes to `amaru-treasury-tx`.
- `.github/`, `flake.nix`, `nix/`, or `docs/`.
- Sibling ticket worktrees.

## Vertical Slices

| Slice | Subject | Commit Subject | Tasks |
|---|---|---|---|
| S0 | Bootstrap committed `gate.sh` for this draft PR. | `chore: add gate.sh for issue 80` | T000 |
| S1 | Spec Kit requirement artifacts. | `docs(080): specify amaru disburse fixture requirements` | T001 |
| S2 | Plan, research, data model, quickstart. | `docs(080): plan amaru disburse fixture implementation` | T002 |
| S3 | Task list and analysis report. | `docs(080): task and analyze amaru disburse fixture plan` | T003, T004 |
| S4 | Worker implementation: RFC 6901 resolver invariant and fix, three fixtures, fixture enumeration, provenance notes, changelog, full gate. | `feat(080): amaru-disburse fixtures (3) + $ref RFC 6901 normalization` | T100-T110 |
| S5 | Drop gate and mark PR ready after final audit. | `chore(080): drop gate.sh (ready for review)` | T111 |

The resolver fix is folded into the fixture slice because the fixtures are
the end-to-end proof that escaped `$ref` values no longer degrade to opaque
decode errors. This keeps the accepted behavior surface in one bisect-safe
commit.

## Test Strategy

### RED/GREEN Contract For S4

The driver must create RED evidence before GREEN:

- `BlueprintSpec` fails on a `~1`-bearing `$ref` before
  `resolveBlueprintSchema` normalizes the JSON-Pointer token.
- The new fixture enumeration fails before fixture files and builder shims
  exist.
- The new fixture expectations fail or contain
  `BlueprintUnresolvedReference` before the resolver fix is applied.

The GREEN commit must then:

- normalize `~1` to `/` and `~0` to `~` before definition lookup;
- add all three fixture directories and provenance notes;
- enumerate fixtures 15..17;
- show typed treasury predicates in expected output;
- preserve all pre-existing fixture expectations;
- update `CHANGELOG.md`;
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

The load-bearing boundary is real Conway CBOR plus real CIP-57 blueprint
metadata crossing into the typed RDF emitter. Fixture outputs must prove
that valid escaped references produce treasury typed predicates rather than
`BlueprintUnresolvedReference` literals. If CBOR decoding or blueprint
resolution still fails after RFC 6901 normalization, the pair must Q-file.

## PR Lifecycle

The PR stays draft during implementation. The ticket owner verifies the
worker commit, amends task checkboxes into that commit, re-runs
`./gate.sh`, and records status before pushing accepted slices. Finalization
drops `gate.sh` only after all tasks are checked and the final gate is
green.

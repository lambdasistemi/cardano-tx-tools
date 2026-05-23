# Implementation Plan: Typed-emit walker per-entry triples

**Branch**: `95-walker-ext-openarray-openobject` | **Date**:
2026-05-23 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from
`specs/095-walker-ext-openarray-openobject/spec.md`

## Summary

Extend the typed emit walker so a decoded
`OpenArray [OpenObject {"key", "value"}, ...]` no longer becomes an
opaque blank node. The walker will keep the existing parent predicate,
link the array bnode to one positional entry bnode per element via
`:_0`, `:_1`, and so on, and put `:key` / `:value` triples on each entry
bnode. The change is structural and local to the OpenValue walker; it
does not introduce an `OpenMap` constructor or new vocabulary.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via the existing Nix shell  
**Primary Dependencies**: Existing `cardano-tx-tools` library,
`Cardano.Tx.Blueprint`, `Cardano.Tx.Graph.Emit`  
**Storage**: Checked-in Turtle golden files  
**Testing**: Hspec unit/golden specs through `just unit`; full gate
through `./gate.sh`  
**Target Platform**: Offline Conway transaction graph emission  
**Project Type**: Haskell library + CLI test harness  
**Performance Goals**: Linear in decoded map entries; no new graph pass  
**Constraints**: Preserve `OpenValue`, no new `cardano:*` vocab terms, no
new fixtures, no dependency or release-pipeline edits, fixtures 01-14
byte-stable  
**Scale/Scope**: One walker extension, one focused spec, two regenerated
goldens, traceability adjustment if needed, changelog

## Constitution Check

- **One-Way Dependency**: Pass. The change is internal to
  `cardano-tx-tools`.
- **Module Namespace**: Pass. No new public module is expected; any test
  module stays under `Cardano.Tx.*`.
- **Conway-Only**: Pass. The touched fixture behavior is Conway typed
  emit.
- **Hackage-Ready Quality**: Pass if `./gate.sh` succeeds, including
  `cabal check` and Haddock.
- **Strict Warnings**: Pass if `just build`, `just unit`, format, and
  hlint checks succeed.
- **Default-Offline Semantics**: Pass. Golden regeneration is local and
  does not require live chain resolution.
- **TDD With Vertical Bisect-Safe Commits**: Pass. RED+GREEN+goldens+
  changelog land in one worker-reviewed behavior commit.

## Design Decisions

### D-001 Triple Shape

Use positional entry links:

```turtle
_:redeemerData1_amount :_0 _:redeemerData1_amount_0 .
_:redeemerData1_amount_0 :key _:redeemerData1_amount_0_key ;
  :value _:redeemerData1_amount_0_value .
```

The exact bnode names may follow the existing `openValueAsObject` base
threading, but the predicates are fixed: parent array bnode uses
`:_<i>`, entry bnodes use `:key` and `:value`.

Rejected alternative: schema-driven naming via the SchemaMap outer
title. That requires more schema context in `openValueAsObject` than the
current walker carries and would widen the change beyond the issue's
OpenValue-stability target.

### D-002 Detection Method

Detect structurally inside the walker: an `OpenArray` matches when every
element is an `OpenObject` whose key set is exactly `key` and `value`.

Rejected alternative: add `OpenMap` to `OpenValue`. #80 deliberately
kept `OpenValue` stable; changing it would force downstream consumer and
test updates outside this ticket.

## Current Code Shape

- `emitDecodedOrOpaque` in `src/Cardano/Tx/Graph/Emit/Project.hs`
  handles decoded datum/redeemer values.
- `emitDecodedConstructor` walks top-level `OpenObject` fields and calls
  `openValueAsObject` for field values.
- `openValueAsObject` currently handles nested `OpenObject` recursively
  but returns an opaque `OBnode` for all `OpenArray` values.
- `src/Cardano/Tx/Graph/Emit/Witness.hs` uses
  `emitDecodedOrOpaque` for redeemers and datum witnesses, so a Project
  helper change covers the witness-side typed output too.
- `BlueprintPredicateTraceabilitySpec` currently documents maps as
  opaque and may need to whitelist `key` / `value` or include them in
  the declared set.

## Project Structure

### Documentation

```text
specs/095-walker-ext-openarray-openobject/
├── spec.md
├── checklists/requirements.md
├── plan.md
├── analysis.md
└── tasks.md
```

### Worker-Owned Implementation Files

```text
src/Cardano/Tx/Graph/Emit/Project.hs
src/Cardano/Tx/Graph/Emit/Witness.hs
test/Cardano/Tx/Graph/Emit/BlueprintSpec.hs
test/Cardano/Tx/BlueprintSpec.hs
test/Cardano/Tx/Graph/Emit/BlueprintPredicateTraceabilitySpec.hs
test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/expected.ttl
test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/expected.ttl
CHANGELOG.md
specs/095-walker-ext-openarray-openobject/tasks.md
```

`Witness.hs`, `BlueprintSpec.hs`, and `BlueprintPredicateTraceabilitySpec.hs`
are touched only if the worker pair finds they are needed for the
focused invariant or traceability.

### Orchestrator-Owned Files

```text
gate.sh
specs/095-walker-ext-openarray-openobject/*
```

## Forbidden Scope

- New fixtures or fixture directories.
- Any `cardano:*` predicate for `key` or `value`.
- Cabal dependency changes or release-pipeline edits.
- Any `expected.ttl` outside fixtures 15 and 17.
- Adding an `OpenMap` constructor to `OpenValue`.

## Vertical Slices

| Slice | Subject | Commit Subject | Tasks |
|---|---|---|---|
| S0 | Bootstrap `gate.sh` and spec artifacts. | `docs(095): plan OpenArray OpenObject walker extension` | T000-T004 |
| S1 | Worker implementation: RED invariant, walker case, traceability update if needed, regenerate fixtures 15/17, changelog, full gate. | `feat(095): typed-emit walker per-entry triples for OpenArray-of-OpenObject` | T100-T112 |
| S2 | Drop gate and mark PR ready after final audit. | `chore(095): drop gate.sh (ready for review)` | T200 |

The behavior change is intentionally one bisect-safe commit because the
walker code, invariant, and fixture goldens must agree at every commit.

## Test Strategy

### RED/GREEN Contract

The worker pair must first add a failing emit-side invariant for a
decoded map-entry array. The RED must fail because the current walker
returns the array bnode but emits no `:_0`, `:key`, or `:value` triples.

GREEN then implements the structural OpenArray case and proves:

- focused invariant passes;
- `EmitGoldenSpec` passes after regenerating only fixtures 15 and 17;
- `BlueprintPredicateTraceabilitySpec` passes deliberately;
- `./gate.sh` passes.

### Focused Commands For The Pair

Minimum focused commands:

```sh
nix develop --quiet -c just unit "Cardano.Tx.Graph.Emit.Blueprint"
nix develop --quiet -c just unit "Cardano.Tx.Graph.Emit joint Turtle goldens"
nix develop --quiet -c just unit "Cardano.Tx.Graph.Emit blueprint-predicate traceability"
./gate.sh
```

The pair may refine Hspec match strings after inspecting test names, but
acceptance requires `./gate.sh`.

### Fixture Stability Check

After regeneration, the branch diff must show `expected.ttl` changes for
fixtures 15 and 17 only. The worker pair must record this check in
`WIP.md`, and the orchestrator rechecks before accepting the commit.

## PR Lifecycle

The PR stays draft during implementation. The ticket owner dispatches
one driver/navigator pair for S1, reviews the returned commit, amends
the completed task checkboxes into that same commit, re-runs `./gate.sh`,
pushes, then finalizes by dropping `gate.sh` after the commit-message
audit passes.

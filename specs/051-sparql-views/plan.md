# Implementation Plan: SPARQL view library and tx-view executable

**Branch**: `51-sparql-views` | **Date**: 2026-05-25 |
**Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from
`specs/051-sparql-views/spec.md`

## Summary

Add four packaged view contracts under `views/` and a new `tx-view`
executable that runs a named view over a canonical Turtle graph file.
The implementation will not add a general SPARQL runtime dependency at
the start of the ticket. Instead, each `.rq` file is the portable
contract, and the executable uses a small in-repo canonical Turtle graph
reader plus typed view projections for the four packaged view names.

If a worker proves that a packaged view cannot satisfy acceptance
without a real SPARQL engine, the pair must stop and Q-file before
touching dependency manifests or flake inputs.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via the existing Nix shell  
**Primary Dependencies**: Existing `cardano-tx-tools` library,
`aeson`, `bytestring`, `containers`, `text`, `optparse-applicative`  
**Storage**: Checked-in `.rq` files and optional view goldens  
**Testing**: Hspec unit/exe specs through `just unit`; full gate through
`./gate.sh`  
**Target Platform**: Offline canonical Turtle graph views  
**Project Type**: Haskell library + CLI executable  
**Performance Goals**: Linear scan over fixture-size graphs; no network
or live-node dependency  
**Constraints**: No new `cardano:*` vocab terms, no emitter/rules-loader
changes, no `--view-file`, no tx-inspect deprecation work  
**Scale/Scope**: One executable, four packaged views, focused tests,
changelog

## Constitution Check

- **One-Way Dependency**: Pass. The feature is internal to
  `cardano-tx-tools` and consumes checked-in graph files.
- **Module Namespace**: Pass. Support modules belong under
  `Cardano.Tx.View`.
- **Conway-Only**: Pass. Fixture inputs are Conway transaction graphs.
- **Hackage-Ready Quality**: Pass if `./gate.sh` succeeds, including
  `cabal check` and Haddock.
- **Strict Warnings**: Pass if build, unit, format, hlint, and haddock
  pass.
- **Default-Offline Semantics**: Pass. `tx-view` reads a graph file and
  never contacts a node.
- **TDD With Vertical Bisect-Safe Commits**: Pass. Each view lands with
  its own tests and keeps prior views green.

## Design Decisions

### D-001 `cli-tree` before reasoner

Ship `cli-tree.rq` against the JOIN-based path available in the current
graph. The view may join entity labels and graph leaves directly. A
future `--reason` or reasoner pre-pass from #49 can materialise helper
triples later, but this PR must not depend on #49.

Rejected alternative: block `cli-tree` on inferred entity-label triples.
That would keep #51 blocked even though the graph already carries enough
surface to rebuild reviewer text.

### D-002 SPARQL runtime strategy

Start with no new SPARQL runtime dependency. `hsparql`, `rdf4h`, `arq`,
and `roqet` are not present in the current Cabal executable/test
surface. A previous epic decision for `views/no-stub-triples.rq`
accepted `.rq` as the vendor-neutral contract with Haskell as the CI
runner. For this ticket, the runner will parse the repository's
canonical Turtle subset and execute typed projections for the four
packaged view names.

Rejected alternatives:

- Add `hsparql` or `rdf4h`: likely dependency/CHaP/GHC 9.12.3 churn and
  contrary to the no-new-heavy-dep constraint unless proven necessary.
- Shell out to Jena/Redland: adds a non-Haskell runtime to the flake and
  gate, also requiring parent approval.

Escalation rule: any dependency or flake change for a SPARQL runtime
requires a Q-file first.

### D-003 Slice cadence

Use sequential bisect-safe slices:

1. `tx-view` skeleton plus `cli-tree`.
2. `asset-flow`.
3. `entity-occurrences`.
4. `json-ld`.

Each slice keeps the previous view tests green and extends `gate.sh`
only if the focused proof changes.

### D-004 Fixture corpus for cli-tree

Parent answer A-001 accepted view-side cli-tree goldens for #51 because
the current `expected.ttl` files cannot reproduce the legacy 044
`expected.txt` files: the body graph carries stub credential bytes while
the rules overlay carries real entity bytes. The cli-tree slice must
cover fixtures 01 through 10 with graph-derived goldens under
`test/fixtures/views/<slug>/cli-tree.txt`. Byte-equivalence to the
legacy 044 `expected.txt` corpus is deferred to follow-on issue #98.

## Current Code Shape

- `tx-graph` emits canonical Turtle and JSON-LD from transaction CBOR,
  rules, and optional UTxO resolution.
- `Cardano.Tx.Graph.Emit.Serialize.Turtle` owns the canonical Turtle
  byte layout used by fixture `expected.ttl` files.
- `Cardano.Tx.Graph.Emit.Serialize.JsonLd` can be reused as a model for
  JSON-LD object shape, but `tx-view --view json-ld` starts from a graph
  file rather than an `EmittedGraph`.
- `test/Cardano/Tx/Graph/Emit/NoStubViewSpec.hs` is precedent for
  shipping a `.rq` contract while using Haskell as the in-repo runner.
- `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs` currently has
  a pending #51 text byte-equivalence check.

## Project Structure

### Documentation

```text
specs/051-sparql-views/
+-- spec.md
+-- plan.md
+-- analysis.md
+-- tasks.md
```

### Worker-Owned Implementation Files

```text
app/tx-view/Main.hs
views/cli-tree.rq
views/asset-flow.rq
views/entity-occurrences.rq
views/json-ld.rq
src/Cardano/Tx/View/*.hs
test/Cardano/Tx/ViewSpec.hs
test/Cardano/Tx/View/CliTreeGoldenSpec.hs
test/fixtures/views/**
cardano-tx-tools.cabal
nix/apps.nix
flake.nix
test/unit-main.hs
CHANGELOG.md
specs/051-sparql-views/tasks.md
```

`flake.nix` is worker-owned only for exposing the new executable as a
flake app or wiring exe test environment variables. It must not add a
new non-Haskell runtime without a Q-file.

### Orchestrator-Owned Files

```text
gate.sh
specs/051-sparql-views/spec.md
specs/051-sparql-views/plan.md
specs/051-sparql-views/analysis.md
specs/051-sparql-views/tasks.md
```

## Forbidden Scope

- `views/tx-diff.rq`.
- Operator-authored `--view-file`.
- Emitter, blueprint loader, rules loader, or resolver behavior
  changes.
- New `cardano:*` vocabulary predicates.
- Deprecation or replacement work for `tx-inspect` or `tx-diff`.
- Any SPARQL runtime dependency or flake tool without a Q-file answer.

## Vertical Slices

| Slice | Subject | Commit Subject | Tasks |
|---|---|---|---|
| S0 | Bootstrap `gate.sh` and spec artifacts. | `docs(051): plan SPARQL view library` | T000-T004 |
| S1 | `tx-view` skeleton plus `cli-tree`. | `feat(051): add tx-view cli-tree view` | T100-T112 |
| S2 | `asset-flow` packaged view and projection. | `feat(051): add asset-flow view` | T200-T207 |
| S3 | `entity-occurrences` packaged view and projection. | `feat(051): add entity-occurrences view` | T300-T306 |
| S4 | `json-ld` packaged view and projection. | `feat(051): add json-ld view` | T400-T407 |
| S5 | Final audit and gate drop. | `chore(051): drop gate.sh (ready for review)` | T500 |

## Test Strategy

### Slice S1

RED must assert that no `tx-view` executable exists or that `cli-tree`
does not yet satisfy at least one fixture's view-side cli-tree golden.

Focused proof:

```sh
nix develop --quiet -c just unit "Cardano.Tx.View"
nix develop --quiet -c just unit "RewriteRedesignGoldens"
./gate.sh
```

The pair may refine Hspec match strings after inspecting test names.
The active golden contract is
`test/Cardano/Tx/View/CliTreeGoldenSpec.hs` comparing fixtures 01
through 10 against `test/fixtures/views/<slug>/cli-tree.txt`.

### Slice S2

RED must assert `asset-flow` over the Amaru swap fixture is absent or
empty. GREEN must assert non-empty, deterministic rows with asset class,
quantity, source entity, and destination entity fields.

### Slice S3

RED must assert `entity-occurrences` over the Amaru swap fixture is
absent or empty. GREEN must assert per-entity count rows and verify they
are not byte-identical to `asset-flow`.

### Slice S4

RED must assert `json-ld` view absence. GREEN must parse output as JSON
and compare supported triples between Turtle and JSON-LD for at least
one fixture graph.

### Gate

Every worker slice must run focused tests and then `./gate.sh`, record
the commands and outcomes in `WIP.md`, and stop after committing. The
ticket owner reruns `./gate.sh` before stamping tasks and pushing.

## PR Lifecycle

The PR stays draft during implementation. The ticket owner dispatches
one driver/navigator pair per implementation slice, reviews the returned
commit, amends the completed task checkboxes into that same commit,
reruns `./gate.sh`, pushes, and continues. Finalization drops `gate.sh`
only after every behavior task is checked and the commit-message audit
passes.

# Tasks: SPARQL view library and tx-view executable

**Feature**: SPARQL view library and tx-view executable  
**Branch**: `51-sparql-views`  
**Plan**: [plan.md](./plan.md)  
**Spec**: [spec.md](./spec.md)

Task numbering reserves T000-T099 for orchestration and T100+ for
worker-owned behavior slices. Behavior-changing work is delegated to
driver/navigator pairs; the ticket owner writes specs, gate, PR
metadata, and task checkbox amendments only.

## Phase 1: Bootstrap And Planning

- [X] T000 Add committed `gate.sh` bootstrap for issue #51 in
  `gate.sh`.
- [X] T001 Specify requirements in
  `specs/051-sparql-views/spec.md`.
- [X] T002 Plan design decisions and test strategy in
  `specs/051-sparql-views/plan.md`.
- [X] T003 Generate this task list in
  `specs/051-sparql-views/tasks.md`.
- [X] T004 Analyze cross-artifact consistency in
  `specs/051-sparql-views/analysis.md`.

## Phase 2: Worker Slice - tx-view Skeleton And cli-tree

**Goal**: `tx-view` exists, dispatches packaged view names, and
`cli-tree` reproduces the graph-derived view-side goldens accepted by
plan.md for fixtures 01 through 10.

**Independent Test**: A focused `Cardano.Tx.View` spec fails before the
view runner exists, then passes after `tx-view --view cli-tree` matches
view-side fixture goldens modulo whitespace canonicalisation.

- [x] T100 [US1] Record RED evidence in `WIP.md` before GREEN for the
  missing `tx-view` / missing `cli-tree` behavior.
- [x] T101 [US1] Add packaged `views/cli-tree.rq` with the SPARQL
  contract for the text-tree projection.
- [x] T102 [US1] Add `app/tx-view/Main.hs` with `--graph`, `--view`,
  and `--out` flags; default `--view` to `cli-tree` and default output
  to stdout.
- [x] T103 [US1] Add cabal and nix app wiring for `tx-view` without
  adding a new SPARQL runtime dependency.
- [x] T104 [US1] Add `Cardano.Tx.View` support code for loading the
  canonical Turtle subset needed by packaged views.
- [x] T105 [US1] Implement the `cli-tree` projection over the canonical
  graph reader.
- [x] T106 [US1] Replace or supplement the pending #51 text
  byte-equivalence check with active tests in
  `test/Cardano/Tx/View/CliTreeGoldenSpec.hs` against view-side goldens
  for fixtures 01 through 10.
- [x] T107 [US1] Add an empty-match graph test proving `cli-tree` exits
  0 with an empty result.
- [x] T108 [US1] Add CLI tests for unknown view, missing graph file,
  and `--out` behavior.
- [x] T109 [US1] Ensure prior graph and inspect test suites remain
  green; do not modify emitter, rules-loader, or vocabulary files.
- [x] T110 [US1] Run focused tests and then `./gate.sh`, recording
  command outcomes in `WIP.md`.
- [x] T111 [US1] Commit the approved slice with subject
  `feat(051): add tx-view cli-tree view` and trailer
  `Tasks: T100, T101, T102, T103, T104, T105, T106, T107, T108, T109, T110, T111`.

## Phase 3: Worker Slice - asset-flow

**Goal**: `asset-flow` is packaged and produces useful asset movement
rows for the Amaru swap fixture.

- [x] T200 [US2] Record RED evidence in `WIP.md` for absent or empty
  `asset-flow`.
- [x] T201 [US2] Add `views/asset-flow.rq` with the SPARQL contract.
- [x] T202 [US2] Implement `asset-flow` in the view projection layer.
- [x] T203 [US2] Add focused tests over the Amaru swap fixture proving
  deterministic asset, quantity, source entity, and destination entity
  output.
- [x] T204 [US2] Add an empty-match graph test proving exit 0.
- [x] T205 [US2] Run focused tests and then `./gate.sh`, recording
  command outcomes in `WIP.md`.
- [x] T206 [US2] Commit the approved slice with subject
  `feat(051): add asset-flow view` and trailer
  `Tasks: T200, T201, T202, T203, T204, T205, T206`.

## Phase 4: Worker Slice - entity-occurrences

**Goal**: `entity-occurrences` is packaged and counts entity leaf-site
references on the Amaru swap fixture.

- [x] T300 [US3] Record RED evidence in `WIP.md` for absent or empty
  `entity-occurrences`.
- [x] T301 [US3] Add `views/entity-occurrences.rq` with the SPARQL
  contract.
- [x] T302 [US3] Implement `entity-occurrences` in the view projection
  layer.
- [x] T303 [US3] Add focused tests proving per-entity count rows on the
  Amaru swap fixture.
- [x] T304 [US3] Add a structural-distinctness assertion against
  `asset-flow`.
- [x] T305 [US3] Run focused tests and then `./gate.sh`, recording
  command outcomes in `WIP.md`.
- [x] T306 [US3] Commit the approved slice with subject
  `feat(051): add entity-occurrences view` and trailer
  `Tasks: T300, T301, T302, T303, T304, T305, T306`.

## Phase 5: Worker Slice - json-ld

**Goal**: `json-ld` is packaged and converts canonical Turtle graph
files to parseable JSON-LD preserving supported triples.

- [x] T400 [US4] Record RED evidence in `WIP.md` for absent `json-ld`
  view behavior.
- [x] T401 [US4] Add `views/json-ld.rq` with the SPARQL/CONSTRUCT
  contract or documented projection contract.
- [x] T402 [US4] Implement `json-ld` projection from the canonical graph
  reader.
- [x] T403 [US4] Add tests proving parseable JSON output for at least
  one fixture graph.
- [x] T404 [US4] Add supported triple-content equivalence tests between
  Turtle input and JSON-LD output.
- [x] T405 [US4] Add an empty graph/result test proving exit 0.
- [x] T406 [US4] Run focused tests and then `./gate.sh`, recording
  command outcomes in `WIP.md`.
- [x] T407 [US4] Commit the approved slice with subject
  `feat(051): add json-ld view` and trailer
  `Tasks: T400, T401, T402, T403, T404, T405, T406, T407`.

## Phase 6: Worker Slice - Changelog And Final Polish

**Goal**: User-visible release notes are present and the full branch is
ready for final audit.

- [x] T450 Add one Unreleased / Features bullet in `CHANGELOG.md` for
  #51 and one Deferred / known limitations bullet referencing follow-on
  #98 for legacy 044 `expected.txt` byte-equivalence.
- [x] T451 Run `./gate.sh`, recording outcome in `WIP.md`.
- [x] T452 Commit the approved slice with subject
  `docs(051): document tx-view SPARQL views` and trailer
  `Tasks: T450, T451, T452`.

## Phase 7: Finalization

- [ ] T500 Drop `gate.sh` in the final ready-for-review commit after
  all behavior tasks are checked, final `./gate.sh` is green, and the
  commit-message audit passes.

## Dependencies

- T000-T004 complete before dispatch.
- T100-T111 complete before T200.
- T200-T206 complete before T300.
- T300-T306 complete before T400.
- T400-T407 complete before T450.
- T500 waits for accepted T100-T452 and final audit.

## Parallel Opportunities

- Navigator can review `.rq` contracts and test assertions while the
  driver works on projection code.
- Within a slice, CLI error-path tests can be reviewed independently of
  view-specific assertions, but they must land in the same slice commit
  when they exercise the new behavior.

## Worker Slice Contracts

### Slice: `cli-tree`

Worker commit subject:

```text
feat(051): add tx-view cli-tree view
```

Commit body trailer:

```text
Tasks: T100, T101, T102, T103, T104, T105, T106, T107, T108, T109, T110, T111
```

### Slice: `asset-flow`

Worker commit subject:

```text
feat(051): add asset-flow view
```

Commit body trailer:

```text
Tasks: T200, T201, T202, T203, T204, T205, T206
```

### Slice: `entity-occurrences`

Worker commit subject:

```text
feat(051): add entity-occurrences view
```

Commit body trailer:

```text
Tasks: T300, T301, T302, T303, T304, T305, T306
```

### Slice: `json-ld`

Worker commit subject:

```text
feat(051): add json-ld view
```

Commit body trailer:

```text
Tasks: T400, T401, T402, T403, T404, T405, T406, T407
```

### Slice: `changelog-polish`

Worker commit subject:

```text
docs(051): document tx-view SPARQL views
```

Commit body trailer:

```text
Tasks: T450, T451, T452
```

## Acceptance Requirements

- RED evidence recorded in `WIP.md` before GREEN for every behavior
  slice.
- Navigator approves RED and GREEN through protocol files.
- `./gate.sh` exits successfully before each commit handoff.
- No forbidden surface is touched.
- Any need for a SPARQL runtime, new vocabulary, `--view-file`, or
  emitter/rules-loader change stops the pair for a Q-file.
- For cli-tree, compare graph-derived output to view-side goldens under
  `test/fixtures/views/**`; legacy 044 `expected.txt` byte-equivalence
  is deferred to #98 per A-001.

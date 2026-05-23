# Tasks: Typed-emit walker per-entry triples

**Feature**: Typed-emit walker per-entry triples  
**Branch**: `95-walker-ext-openarray-openobject`  
**Plan**: [plan.md](./plan.md)  
**Spec**: [spec.md](./spec.md)

Task numbering reserves T000-T099 for orchestration and T100+ for the
single worker-owned behavior slice. Behavior-changing work is delegated
to a driver/navigator pair; the ticket owner writes specs, gate, PR
metadata, and task checkbox amendments only.

## Phase 1: Bootstrap And Planning

- [X] T000 Add committed `gate.sh` bootstrap for issue #95 in `gate.sh`.
- [X] T001 Specify requirements in
  `specs/095-walker-ext-openarray-openobject/spec.md`.
- [X] T002 Plan design decisions and test strategy in
  `specs/095-walker-ext-openarray-openobject/plan.md`.
- [X] T003 Generate this task list in
  `specs/095-walker-ext-openarray-openobject/tasks.md`.
- [X] T004 Analyze cross-artifact consistency in
  `specs/095-walker-ext-openarray-openobject/analysis.md`.

## Phase 2: Worker Slice - OpenArray OpenObject Walker Case

**Goal**: The typed emit walker materialises per-entry triples for
SchemaMap-decoded `OpenArray [OpenObject {"key", "value"}, ...]`
values, fixtures 15 and 17 are regenerated, and older fixtures remain
stable.

**Independent Test**: Focused emit-side invariant fails before GREEN,
then `./gate.sh` passes after the walker extension and golden
regeneration.

- [X] T100 [US1] Record RED evidence in `WIP.md` before GREEN: add a
  focused emit-side invariant for an `OpenArray [OpenObject {"key",
  "value"}]` value that currently lacks `:_0`, `:key`, and `:value`
  triples.
- [X] T101 [US1] Implement structural recognition for map-entry arrays
  in `src/Cardano/Tx/Graph/Emit/Project.hs` and/or
  `src/Cardano/Tx/Graph/Emit/Witness.hs`.
- [X] T102 [US1] Emit positional array-to-entry triples with `:_<i>`
  predicates using zero-based decoded array order.
- [X] T103 [US1] Emit `:key` and `:value` triples on each entry bnode,
  rendering key and value objects through the existing OpenValue object
  path.
- [X] T104 [US1] Preserve opaque behavior for all non-matching
  `OpenArray` values and for `OpenObject` values with extra or missing
  fields.
- [X] T105 [US1] Keep `OpenValue` stable; do not add an `OpenMap`
  constructor or downstream consumer changes.
- [X] T106 [US2] Regenerate
  `test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/expected.ttl`
  only after the walker case is green.
- [X] T107 [US2] Regenerate
  `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/expected.ttl`
  only after the walker case is green.
- [X] T108 [US3] Verify fixture `expected.ttl` files outside 15 and 17
  are byte-stable and record the check in `WIP.md`.
- [X] T109 [US3] Extend
  `test/Cardano/Tx/Graph/Emit/BlueprintPredicateTraceabilitySpec.hs` if
  `:key` / `:value` need deliberate traceability handling.
- [X] T110 [US1] Add one Unreleased / Features bullet in
  `CHANGELOG.md` for #95.
- [X] T111 [US1] Run focused commands and then `./gate.sh`, recording
  command outcomes in `WIP.md`.
- [X] T112 [US1] Commit the approved slice with subject
  `feat(095): typed-emit walker per-entry triples for OpenArray-of-OpenObject`
  and trailer `Tasks: T100, T101, T102, T103, T104, T105, T106, T107,
  T108, T109, T110, T111, T112`.

## Phase 3: Finalization

- [ ] T200 Drop `gate.sh` in the final ready-for-review commit after
  all behavior tasks are checked, final `./gate.sh` is green, and the
  commit-message audit passes.

## Dependencies

- T000-T004 complete before dispatch.
- T100 precedes T101-T104.
- T101-T105 precede T106-T107.
- T108-T111 precede T112.
- T200 waits for accepted T100-T112 and final audit.

## Parallel Opportunities

- Navigator can review the traceability spec and fixture stability
  invariant while the driver writes the RED.
- Fixture 15 and 17 regeneration is mechanically independent once the
  walker is green, but both ride in the same behavior commit to keep
  code and goldens bisect-safe.

## Worker Slice Contract

### Slice: `openarray-openobject-walker`

Worker commit subject:

```text
feat(095): typed-emit walker per-entry triples for OpenArray-of-OpenObject
```

Commit body trailer:

```text
Tasks: T100, T101, T102, T103, T104, T105, T106, T107, T108, T109, T110, T111, T112
```

### Acceptance Requirements

- RED evidence recorded in `WIP.md` before GREEN.
- Navigator approves RED and GREEN through protocol files.
- `./gate.sh` exits successfully before commit handoff.
- No forbidden surface is touched.
- Only fixtures 15 and 17 `expected.ttl` change.
- If new vocabulary, new fixtures, `OpenMap`, or dependency changes look
  necessary, the pair stops and writes a Q-file.

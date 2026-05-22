# Tasks: Real Conway amaru disburse fixtures

**Feature**: Real Conway amaru disburse fixtures  
**Branch**: `80-amaru-disburse-fixtures`  
**Plan**: [plan.md](./plan.md)  
**Spec**: [spec.md](./spec.md)

Task numbering reserves T000-T099 for orchestration and T100+ for the
worker-owned implementation slice. Behavior-changing work is one
driver/navigator commit; the ticket owner only writes specs, gates, PR
metadata, and task checkbox amendments during acceptance.

## Phase 1: Bootstrap

- [X] T000 Add committed `gate.sh` bootstrap for the issue #80 draft PR
  in `gate.sh`
- [X] T001 Specify requirements and checklist in
  `specs/080-amaru-disburse-fixtures/spec.md` and
  `specs/080-amaru-disburse-fixtures/checklists/requirements.md`
- [X] T002 Plan implementation, research, data model, and quickstart in
  `specs/080-amaru-disburse-fixtures/plan.md`,
  `specs/080-amaru-disburse-fixtures/research.md`,
  `specs/080-amaru-disburse-fixtures/data-model.md`, and
  `specs/080-amaru-disburse-fixtures/quickstart.md`
- [X] T003 Generate this task list in
  `specs/080-amaru-disburse-fixtures/tasks.md`
- [X] T004 Analyze cross-artifact consistency in
  `specs/080-amaru-disburse-fixtures/analysis.md`

## Phase 2: User Story 1 + 2 - Typed real disburse fixtures and RFC 6901 refs

**Goal**: Fixtures 15..17 verify real Conway treasury disburse shapes, and
valid escaped blueprint references resolve before definition lookup.

**Independent Test**: `nix develop --quiet -c just unit`, followed by
`./gate.sh`, verifies the focused unit invariant, fixture goldens, and
project-wide quality gates.

- [ ] T100 [US2] Add a RED BlueprintSpec invariant for a
  `#/definitions/types~1TreasurySpendRedeemer` `$ref` resolving to the
  `types/TreasurySpendRedeemer` definition in
  `test/Cardano/Tx/BlueprintSpec.hs`
- [ ] T101 [US2] Extend `resolveBlueprintSchema` to decode RFC 6901
  pointer escapes `~1` and `~0` before definition lookup in
  `src/Cardano/Tx/Blueprint.hs`
- [ ] T102 [US1] Source the minimal disburse transaction and matching
  blueprint chain from `amaru-treasury-tx/transactions/` into
  `test/fixtures/rewrite-redesign/15-amaru-disburse-minimal/`
- [ ] T103 [US1] Source the full four-of-four multisig disburse
  transaction and matching blueprint chain into
  `test/fixtures/rewrite-redesign/16-amaru-disburse-multisig/`
- [ ] T104 [US1] Source the contingency disburse transaction and matching
  blueprint chain into
  `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/`, or
  raise a Q-file before substitution if no representative tx exists
- [ ] T105 [US1] Add per-fixture builder shims for fixtures 15..17 under
  `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/` if required
  by the existing harness
- [ ] T106 [US1] Enumerate fixtures 15..17 in
  `test/Cardano/Tx/Graph/EmitGoldenSpec.hs`
- [ ] T107 [US1] Regenerate or verify `expected.ttl`,
  `expected.entities.ttl`, and `expected.txt` for fixtures 15..17 so they
  contain typed treasury predicates and no valid-schema
  `BlueprintUnresolvedReference` decode errors
- [ ] T108 [US3] Write fixture provenance notes with tx hash, source
  commit or PR, and blueprint chain in each fixture `NOTES.md`
- [ ] T109 [US4] Verify all pre-existing rewrite-redesign fixtures remain
  byte-stable and `BlueprintPredicateTraceabilitySpec` passes on fixtures
  15..17
- [ ] T110 [US1] Add one Unreleased / Features bullet summarizing the
  real Conway disburse fixtures and RFC 6901 normalization in
  `CHANGELOG.md`

## Phase 3: Finalization

- [ ] T111 Drop `gate.sh` in the final ready-for-review commit after the
  final gate and commit-message audit pass

## Dependencies

- T100 must precede T101 so RED evidence exists before GREEN.
- T101 must precede final golden verification because valid escaped refs
  must resolve before fixture expectations are accepted.
- T102, T103, and T104 can be investigated independently, but their
  fixture files land in the same worker commit for bisect-safety.
- T105 and T106 depend on the selected fixture slugs and harness pattern.
- T107, T108, T109, and T110 are acceptance work inside the same worker
  slice.
- T111 waits for T100-T110 to be checked and `./gate.sh` green.

## Parallel Opportunities

- The driver may inspect candidate minimal, multisig, and contingency
  transactions independently before editing the shared fixture harness.
- Provenance note drafting can proceed while golden regeneration runs.
- The navigator can review fixture provenance and typed predicate shape
  while the driver runs the full gate.

## Worker Slice Contract

Slice slug: `amaru-disburse-fixtures`

Worker commit subject:

```text
feat(080): amaru-disburse fixtures (3) + $ref RFC 6901 normalization
```

Commit body trailer:

```text
Tasks: T100, T101, T102, T103, T104, T105, T106, T107, T108, T109, T110
```

Acceptance requirements:

- RED evidence recorded in `WIP.md` before GREEN.
- Navigator approves RED and GREEN through protocol files.
- `./gate.sh` exits successfully before commit handoff.
- No forbidden surface is touched.
- If a new `cardano:*` term or missing contingency representative appears,
  the pair stops and writes a Q-file.

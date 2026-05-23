# Tasks: Amaru disburse DSL fixtures

**Feature**: Amaru disburse DSL fixtures  
**Branch**: `90-amaru-disburse-fixtures-dsl`  
**Plan**: [plan.md](./plan.md)  
**Spec**: [spec.md](./spec.md)

Task numbering reserves T000-T099 for orchestration and T200+ for
worker-owned implementation slices. Behavior-changing work is delegated
to driver/navigator pairs; the ticket owner only writes specs, gates, PR
metadata, and task checkbox amendments during acceptance.

## Phase 1: Bootstrap

- [X] T000 Add committed `gate.sh` bootstrap for the issue #90 draft PR
  in `gate.sh`
- [X] T001 Specify requirements and checklist in
  `specs/090-amaru-disburse-fixtures-dsl/spec.md` and
  `specs/090-amaru-disburse-fixtures-dsl/checklists/requirements.md`
- [X] T002 Plan implementation, research, data model, and quickstart in
  `specs/090-amaru-disburse-fixtures-dsl/plan.md`,
  `specs/090-amaru-disburse-fixtures-dsl/research.md`,
  `specs/090-amaru-disburse-fixtures-dsl/data-model.md`, and
  `specs/090-amaru-disburse-fixtures-dsl/quickstart.md`
- [X] T003 Generate this task list in
  `specs/090-amaru-disburse-fixtures-dsl/tasks.md`
- [X] T004 Analyze cross-artifact consistency in
  `specs/090-amaru-disburse-fixtures-dsl/analysis.md`

## Phase 2: User Story 1 - Network-compliance fixture

**Goal**: Fixture 15 mirrors the network-compliance disburse source
transaction at
`/code/amaru-treasury-tx-issue-237/transactions/2026/network_compliance/affe90d1fa9a93b3e2a48009ef80634e9de8428640f5d673e85b002a86399982/`
and pins current SchemaMap typed output.

**Independent Test**: `nix develop --quiet -c just unit`, followed by
`./gate.sh`, verifies the fixture golden, traceability, existing fixture
stability, and project-wide quality gates.

- [X] T200 [US1] Add RED evidence for fixture 15 enumeration/golden
  absence in `WIP.md` before creating the fixture files
- [X] T201 [US1] Create
  `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S15_AmaruDisburseNetworkCompliance.hs`
  as a DSL reconstruction of the A-002-approved source transaction shape
  (5 treasury inputs, 1 wallet input, 3 outputs, 5 spend redeemers,
  4 reference inputs, 1 collateral input, and 1 zero-lovelace
  stake-script withdrawal)
- [X] T202 [US1] Add
  `test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/rules.yaml`
  registering the Sundae treasury blueprint for script
  `32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d`
- [X] T203 [US1] Add or verify shared blueprint
  `test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json`
  from `/code/amaru-treasury/treasury-contracts/plutus.json` or a
  documented single-validator extraction
- [X] T204 [US1] Enumerate fixture 15 in
  `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` and register
  `Fixtures.RewriteRedesign.S15_AmaruDisburseNetworkCompliance` in the
  `test-suite unit-tests` `other-modules` stanza of
  `cardano-tx-tools.cabal` per A-003
- [X] T205 [US1] Generate fixture 15 `expected.ttl`,
  `expected.entities.ttl`, and `expected.txt` under
  `test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/`
  from the current emitter
- [X] T206 [US4] Write fixture 15 provenance in
  `test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/NOTES.md`
  with tx hash, the `affe90d1...` source path, source repo path
  `amaru-treasury-tx-issue-237`, and blueprint source
- [X] T207 [US3] Verify fixtures 01 through 14 remain byte-stable and
  `BlueprintPredicateTraceabilitySpec` passes with fixture 15 included
- [X] T208 [US1] Run `./gate.sh`, commit the approved fixture 15 slice,
  and include `Tasks: T200, T201, T202, T203, T204, T205, T206, T207,
  T208`

## Phase 3: User Story 2 - Contingency fixture

**Goal**: Fixture 17 mirrors the on-chain 4-of-4 multisig contingency
disburse source transaction and remains self-contained.

**Independent Test**: `nix develop --quiet -c just unit`, followed by
`./gate.sh`, verifies the fixture golden, traceability, existing fixture
stability, and project-wide quality gates.

- [ ] T300 [US2] Add RED evidence for fixture 17 enumeration/golden
  absence in `WIP.md` before creating the fixture files
- [ ] T301 [US2] Create
  `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S17_AmaruDisburseContingency.hs`
  as a self-contained DSL reconstruction of the source contingency
  transaction
- [ ] T302 [US2] Add
  `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/rules.yaml`
  registering the Sundae treasury blueprint for the treasury script
- [ ] T303 [US2] Enumerate fixture 17 in
  `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` and register
  `Fixtures.RewriteRedesign.S17_AmaruDisburseContingency` in the
  `test-suite unit-tests` `other-modules` stanza of
  `cardano-tx-tools.cabal` per A-003
- [ ] T304 [US2] Generate fixture 17 `expected.ttl`,
  `expected.entities.ttl`, and `expected.txt` under
  `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/` from
  the current emitter
- [ ] T305 [US4] Write fixture 17 provenance in
  `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/NOTES.md`
  with tx hash, source path, block/slot, and blueprint source
- [ ] T306 [US3] Verify fixtures 01 through 14 remain byte-stable and
  `BlueprintPredicateTraceabilitySpec` passes with fixture 17 included
- [ ] T307 [US2] Run `./gate.sh`, commit the approved fixture 17 slice,
  and include `Tasks: T300, T301, T302, T303, T304, T305, T306, T307`

## Phase 4: Polish And Finalization

- [ ] T400 [US1] Add one Unreleased / Features bullet summarizing the
  two amaru disburse fixtures in `CHANGELOG.md`, and coordinate the final
  behavior commit subject
  `feat(090): amaru-disburse fixtures (network_compliance + contingency)`
- [ ] T401 Drop `gate.sh` in the final ready-for-review commit after the
  final gate and commit-message audit pass

## Dependencies

- T001-T004 complete before any implementation pair is dispatched.
- T203 can be completed in the fixture 15 slice and then reused by
  fixture 17.
- T204 precedes T205 so regen/verification can target the new slug.
- T303 precedes T304 so regen/verification can target the new slug.
- T207 and T306 must include existing fixture byte-stability checks.
- T400 waits for fixture slices to pass and may be folded into the final
  behavior commit shape if the epic owner directs history shaping.
- T401 waits for all prior tasks checked and `./gate.sh` green.

## Parallel Opportunities

- The navigator can review source transaction provenance while the driver
  reconstructs the DSL module.
- Blueprint provenance review can proceed independently from golden
  regeneration once the file is copied or extracted.
- Fixture 15 and fixture 17 are conceptually independent, but this ticket
  runs them sequentially because both touch `EmitGoldenSpec.hs` and the
  shared blueprint path.

## Worker Slice Contracts

### Slice: `15-amaru-disburse-network-compliance`

Worker commit subject:

```text
feat(090): amaru-disburse network-compliance fixture
```

Commit body trailer:

```text
Tasks: T200, T201, T202, T203, T204, T205, T206, T207, T208
```

### Slice: `17-amaru-disburse-contingency`

Worker commit subject:

```text
feat(090): amaru-disburse contingency fixture
```

Commit body trailer:

```text
Tasks: T300, T301, T302, T303, T304, T305, T306, T307
```

### Acceptance Requirements For Both Worker Slices

- RED evidence recorded in `WIP.md` before GREEN.
- Navigator approves RED and GREEN through protocol files.
- `./gate.sh` exits successfully before commit handoff.
- No forbidden surface is touched.
- If a new `cardano:*` term, source-module change, or non-DSL fixture
  construction appears necessary, the pair stops and writes a Q-file.

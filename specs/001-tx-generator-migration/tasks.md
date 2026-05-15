---

description: "Tasks for migrating cardano-tx-generator to cardano-tx-tools"
---

# Tasks: Tx Generator Migration

**Input**: Design documents from `specs/001-tx-generator-migration/`
**Prerequisites**: spec.md, plan.md, research.md, data-model.md,
contracts/cabal.md, quickstart.md (all present and pushed)

**Tests**: Existing unit and e2e tests come over verbatim with the
daemon. No new tests are written in this PR; the migration is
behavior-preserving. Test parity is verified by running the migrated
suites against the same fixtures.

**Organization**: Tasks are grouped by user story so each can be
implemented and reviewed as an independent vertical slice. Slices
land as separate commits on this branch; the branch merges in one
PR.

## Path Conventions

- **Repository**: cardano-tx-tools (this repo)
- **Library sublib**: `lib-tx-generator/Cardano/Tx/Generator/`
- **Executable**: `app/cardano-tx-generator/`
- **Unit tests**: `test/Cardano/Tx/Generator/`
- **E2E tests**: `test/Cardano/Tx/Generator/E2E/`
- **Cabal**: `cardano-tx-tools.cabal`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the cabal stanzas before any source is moved so each
following slice can build incrementally.

- [X] T001 Add `library tx-generator-lib` stanza to
  `cardano-tx-tools.cabal` matching `specs/.../contracts/cabal.md`:
  `visibility: public`, `hs-source-dirs: lib-tx-generator`,
  empty `exposed-modules` for now, full `build-depends` list. The
  empty module list keeps the stanza buildable until Phase 2 lands
  the sources.
- [X] T002 [P] Add `executable cardano-tx-generator` stanza to
  `cardano-tx-tools.cabal` with `main-is: Main.hs`,
  `hs-source-dirs: app/cardano-tx-generator`,
  `build-depends: { base, cardano-tx-tools:tx-generator-lib }`. Do
  NOT create `Main.hs` yet (Phase 3 brings it in).
- [X] T003 [P] Add `test-suite tx-generator-tests` stanza to
  `cardano-tx-tools.cabal` with `main-is: tx-generator-main.hs`,
  empty `other-modules`, the test build-depends from
  `contracts/cabal.md`.
- [X] T004 [P] Add `test-suite e2e-tests` stanza to
  `cardano-tx-tools.cabal` with `main-is: e2e-main.hs`,
  empty `other-modules`, the e2e build-depends including
  `cardano-node-clients:devnet`.
- [X] T005 Run `cabal-fmt -i cardano-tx-tools.cabal` and stage the
  result. Commit (slice 1): `feat: cabal scaffolding for
  tx-generator-lib, exe, and two test-suites`.

**Checkpoint**: `nix flake check` still passes; no behavior change;
new stanzas are empty shells.

---

## Phase 2: Foundational — Sublib source migration (Blocking Prerequisites)

**Purpose**: Move and rename the nine daemon library modules; make
the `tx-generator-lib` sublib compile in isolation.

**⚠️ CRITICAL**: No user story work can begin until this phase is
complete.

- [X] T006 Create directory tree
  `lib-tx-generator/Cardano/Tx/Generator/`.
- [X] T007 Copy the nine source files from cardano-node-clients
  (`lib/Cardano/Node/Client/TxGenerator/*.hs`) into the new
  `lib-tx-generator/Cardano/Tx/Generator/` directory verbatim. Files:
  `Build.hs`, `Daemon.hs`, `Fanout.hs`, `Persist.hs`,
  `Population.hs`, `Selection.hs`, `Server.hs`, `Snapshot.hs`,
  `Types.hs`.
- [X] T008 In each copied file, rename the module declaration:
  `module Cardano.Node.Client.TxGenerator.<X>` →
  `module Cardano.Tx.Generator.<X>`. Update the Haddock `Module      :
  Cardano.Node.Client.TxGenerator.<X>` line to match.
- [X] T009 In each copied file, rewrite intra-namespace imports:
  `Cardano.Node.Client.TxGenerator.<X>` →
  `Cardano.Tx.Generator.<X>`. Rewrite tx-tools imports:
  `Cardano.Node.Client.{TxBuild,Balance,Ledger}` →
  `Cardano.Tx.{Build,Balance,Ledger}`. Leave
  `Cardano.Node.Client.{Provider, Submitter, N2C.*, UTxOIndexer.*,
  E2E.Setup}` alone — those stay imported from the
  cardano-node-clients pin.
- [X] T010 Update `cardano-tx-tools.cabal`'s
  `library tx-generator-lib` `exposed-modules` to list the nine
  migrated modules.
- [X] T011 Run `cabal-fmt -i cardano-tx-tools.cabal` and
  `nix develop --quiet -c just format` to format the new sources.
- [X] T012 Verify the sublib builds:
  `nix build .#checks.x86_64-linux.build --no-link`. If the build
  fails, the most likely cause is a missing build-depends in T001;
  add and rebuild.
- [X] T013 Commit (slice 2):
  `feat: migrate TxGenerator under Cardano.Tx.Generator.*`.

**Checkpoint**: `cardano-tx-tools:tx-generator-lib` builds standalone.
No exe / tests yet. `nix flake check` passes.

---

## Phase 3: User Story 1 — Cycle break readiness (Priority: P1) 🎯 MVP

**Goal**: Make `Cardano.Tx.Generator.*` and the
`cardano-tx-generator` executable available from cardano-tx-tools so
the companion deletion PR in cardano-node-clients can drop its copy.
This is the literal MVP: nothing else in the migration matters until
the binary is buildable here.

**Independent Test**: `nix build .#cardano-tx-generator` produces a
binary. `nix run .#cardano-tx-generator -- --help` prints usage text
matching the pre-migration cardano-node-clients build byte-for-byte.

- [X] T014 [US1] Copy
  `app/cardano-tx-generator/Main.hs` verbatim from
  cardano-node-clients into `app/cardano-tx-generator/Main.hs`.
- [X] T015 [US1] Update Main.hs imports: legacy
  `Cardano.Node.Client.TxGenerator.<X>` references →
  `Cardano.Tx.Generator.<X>`.
- [X] T016 [US1] In `flake.nix`, add the `cardano-tx-generator`
  executable to `packages.${system}` and to `apps.${system}` so
  `nix run .#cardano-tx-generator` works. Wrap as needed (the
  binary doesn't open TLS itself; no cacert wrapper required, but
  match the pattern used by tx-diff if the daemon uses HTTPS for
  Blockfrost — verify in Phase 2 source).
- [X] T017 [US1] Run `nix build .#cardano-tx-generator`. Capture
  `--help` output and diff it against the cardano-node-clients-built
  binary at the migration source SHA (`ca86f11`); they MUST be
  byte-identical.
- [X] T018 [US1] Commit (slice 3):
  `feat: cardano-tx-generator exe builds from cardano-tx-tools`.

**Checkpoint**: User Story 1 is met. The companion deletion PR is
technically unblocked. Subsequent slices polish but do not gate.

---

## Phase 4: User Story 3 — Behavior preservation via test parity (Priority: P1)

**Goal**: Prove the migrated unit tests still pass on the
cardano-tx-tools side. The daemon's behavior is byte-identical to
the pre-migration baseline.

**Independent Test**: `nix build .#checks.x86_64-linux.tx-generator-tests`
runs the six migrated `*Spec` modules to completion with zero
failures.

- [X] T019 [P] [US3] Copy
  `test/Cardano/Node/Client/TxGenerator/FanoutSpec.hs` →
  `test/Cardano/Tx/Generator/FanoutSpec.hs` with namespace rename.
- [X] T020 [P] [US3] Copy
  `test/Cardano/Node/Client/TxGenerator/PersistSpec.hs` →
  `test/Cardano/Tx/Generator/PersistSpec.hs` with namespace rename.
- [X] T021 [P] [US3] Copy
  `test/Cardano/Node/Client/TxGenerator/PopulationSpec.hs` →
  `test/Cardano/Tx/Generator/PopulationSpec.hs` with namespace
  rename.
- [X] T022 [P] [US3] Copy
  `test/Cardano/Node/Client/TxGenerator/SelectionSpec.hs` →
  `test/Cardano/Tx/Generator/SelectionSpec.hs` with namespace
  rename.
- [X] T023 [P] [US3] Copy
  `test/Cardano/Node/Client/TxGenerator/ServerSpec.hs` →
  `test/Cardano/Tx/Generator/ServerSpec.hs` with namespace rename.
- [X] T024 [P] [US3] Copy
  `test/Cardano/Node/Client/TxGenerator/SnapshotSpec.hs` →
  `test/Cardano/Tx/Generator/SnapshotSpec.hs` with namespace
  rename.
- [X] T025 [US3] Create `test/tx-generator-main.hs` listing the six
  `Cardano.Tx.Generator.*Spec` modules.
- [X] T026 [US3] Update `cardano-tx-tools.cabal`'s
  `test-suite tx-generator-tests` `other-modules` to the six
  migrated spec modules.
- [X] T027 [US3] Add a `unit` check entry to `nix/checks.nix` (a
  sibling of the existing `unit` check, e.g. `tx-generator-unit`),
  invoking `tx-generator-tests` via the sandbox app pattern.
- [X] T028 [US3] Run
  `nix build .#checks.x86_64-linux.tx-generator-unit --no-link` and
  confirm all six specs pass.
- [X] T029 [US3] Commit (slice 4):
  `feat: tx-generator unit tests under tx-generator-tests`.

**Checkpoint**: Test parity verified for unit specs. E2E parity
follows in Phase 5.

---

## Phase 5: User Story 2 — Separate test-suite isolation (Priority: P2)

**Goal**: Confirm the new `tx-generator-tests` test-suite is fully
isolated from `unit-tests` — running one does not rebuild the other
and the membership lists are disjoint.

**Independent Test**:
`cabal test cardano-tx-tools:tx-generator-tests` runs only the
TxGenerator specs; `cabal test cardano-tx-tools:unit-tests` runs
only the diff/blueprint/resolver specs. The two
`other-modules` lists in the `.cabal` file share zero entries.

- [ ] T030 [US2] Audit `cardano-tx-tools.cabal`: confirm the
  `unit-tests` stanza's `other-modules` contains no
  `Cardano.Tx.Generator.*Spec` modules. If any leaked there during
  Phase 4 work, move them to `tx-generator-tests`.
- [ ] T031 [US2] Add a `just unit-tx-generator` recipe to `justfile`
  for local iteration:
  `cabal test cardano-tx-tools:tx-generator-tests -O0
   --test-show-details=direct`.
- [ ] T032 [US2] Verify isolation:
  `nix build .#checks.x86_64-linux.tx-generator-unit
  --no-link --rebuild` then
  `nix build .#checks.x86_64-linux.unit --no-link`. The second build
  must not rebuild `tx-generator-tests` derivations.
- [ ] T033 [US2] Commit (slice 5):
  `chore: lock the boundary between unit-tests and
  tx-generator-tests`.

**Checkpoint**: User Story 2 met.

---

## Phase 6: E2E tests + Docker image (Polish & Cross-Cutting)

**Goal**: Bring across the e2e tests and the Docker image so the
companion deletion PR can drop them from cardano-node-clients
cleanly.

- [ ] T034 [P] Copy the nine E2E spec files from
  `cardano-node-clients/test/Cardano/Node/Client/E2E/TxGenerator*Spec.hs`
  into `test/Cardano/Tx/Generator/E2E/*Spec.hs` with namespace
  rename. Update intra-suite imports.
- [ ] T035 Create `test/e2e-main.hs` listing the nine
  `Cardano.Tx.Generator.E2E.*Spec` modules.
- [ ] T036 Update `cardano-tx-tools.cabal`'s `test-suite e2e-tests`
  `other-modules` accordingly.
- [ ] T037 Add an `e2e` gate to `nix/checks.nix` (mirrors
  cardano-node-clients's existing `e2e` gate) that runs
  `e2e-tests` with `cardanoNode` and the `devnet` sublib in
  `runtimeInputs`.
- [ ] T038 Smoke-run the e2e gate against the pinned
  `cardano-node 10.7.0`:
  `nix build .#checks.x86_64-linux.e2e --no-link`.
- [ ] T039 Commit (slice 6):
  `feat: tx-generator e2e tests run against devnet under
  cardano-tx-tools`.
- [ ] T040 [P] Copy `nix/docker-image.nix` from cardano-node-clients
  to `nix/docker-image.nix` here. Adjust the image name from
  `ghcr.io/lambdasistemi/cardano-node-clients/cardano-tx-generator`
  to
  `ghcr.io/lambdasistemi/cardano-tx-tools/cardano-tx-generator`.
- [ ] T041 [P] Add a `.github/workflows/publish-images.yaml`
  matching the upstream version, with the registry path adjusted.
- [ ] T042 [P] Update `docs/migration.md` to reflect Phase 2 of the
  cardano-node-clients#152 migration (TxGenerator moved; Docker
  image registry path changed).
- [ ] T043 Update `CHANGELOG.md` under `## Unreleased` to note the
  TxGenerator migration and the new exe + sublib.
- [ ] T044 Run the full local gate one more time:
  `nix develop --quiet -c just format` then
  `nix flake check --no-eval-cache`. Both must pass.
- [ ] T045 Commit (slice 7):
  `feat: tx-generator Docker image and publish workflow`.

**Checkpoint**: Migration is complete on the cardano-tx-tools side.

---

## Phase 7: Companion-PR Coordination

**Purpose**: Hand off cleanly to the cardano-node-clients deletion
PR. This phase has no source changes here; it documents what the
companion PR needs.

- [ ] T046 Update the PR description on
  https://github.com/lambdasistemi/cardano-tx-tools/pull/7 to
  reference the SHA that the companion PR will pin (the head of
  this branch at merge time) and the exact deletion checklist for
  cardano-node-clients (deletes
  `lib/Cardano/Node/Client/TxGenerator/*`,
  `app/cardano-tx-generator/`, the unit + e2e tests for the
  daemon, `nix/docker-image.nix`,
  `.github/workflows/publish-images.yaml`, drops the
  `cardano-tx-generator` exe stanza from `.cabal`, removes the
  `cardano-tx-generator-image` flake output, does NOT add a
  `source-repository-package` entry for cardano-tx-tools).
- [ ] T047 After PR #7 merges, in the companion worktree
  (`/code/cardano-node-clients-issue-152`): finish the deletions
  (already largely staged), update internal docs / changelog,
  build + test, push.

---

## Dependencies

```text
T001 (cabal sublib stanza)
  └→ T002, T003, T004 (parallel: other cabal stanzas)
       └→ T005 (cabal-fmt + commit slice 1)
            └→ T006 (dir tree)
                 └→ T007 (copy sources)
                      └→ T008 (module rename)
                           └→ T009 (import rewrite)
                                └→ T010 (cabal exposed-modules)
                                     └→ T011 (format)
                                          └→ T012 (build verify)
                                               └→ T013 (commit slice 2)
                                                    └→ T014 (Main.hs copy)
                                                         └→ T015 (Main rename)
                                                              └→ T016 (flake.nix exe wire)
                                                                   └→ T017 (--help diff)
                                                                        └→ T018 (commit slice 3)
                                                                             └→ T019..T024 (parallel unit-test copies)
                                                                                  └→ T025 (tx-generator-main.hs)
                                                                                       └→ T026 (cabal test-suite modules)
                                                                                            └→ T027 (nix check entry)
                                                                                                 └→ T028 (run tests)
                                                                                                      └→ T029 (commit slice 4)
                                                                                                           └→ T030..T033 (isolation audit, commit slice 5)
                                                                                                                └→ T034..T039 (e2e migration, commit slice 6)
                                                                                                                     └→ T040..T045 (Docker + workflow + docs, commit slice 7)
                                                                                                                          └→ T046..T047 (PR coordination, post-merge companion)
```

## Parallel execution opportunities

- **Phase 1**: T002, T003, T004 can be batched into the same edit
  pass on the cabal file (they all touch separate stanzas).
- **Phase 4**: T019..T024 are pure copy+rename of independent test
  files. Run sed across all six in one command.
- **Phase 6**: T040 (Docker image), T041 (publish workflow), T042
  (docs) touch different files and can be edited in parallel before
  the final commit.

## MVP scope

The MVP is **Phase 3 (User Story 1) complete + Phase 4 (User Story
3) complete**: the daemon's library, executable, and unit tests
build and pass under cardano-tx-tools. With slices 1-4 landed, the
companion deletion PR in cardano-node-clients is unblocked.

Phases 5 (test-suite isolation audit), 6 (e2e + Docker), and 7
(coordination) are operational polish; they do not gate the
companion PR but do gate the next cardano-tx-tools release that
ships `cardano-tx-generator` as a public binary.

## Implementation strategy

1. Land slices 1-4 on this branch in order. Each commit must pass
   `nix flake check --no-eval-cache` locally before pushing.
2. Mark PR #7 ready for review after slice 4 lands; CI must be green
   before merging.
3. Land slices 5-7 on the same branch (or a follow-up PR if review
   prefers smaller batches). Either way, all slices land before the
   companion deletion PR merges in cardano-node-clients.
4. After merge: open the companion PR in cardano-node-clients (the
   worktree is parked at `/code/cardano-node-clients-issue-152`
   with deletions already staged from the earlier abandoned
   attempt). Update its `cabal.project` to NOT add a
   `source-repository-package` to cardano-tx-tools; ship it.

## Format validation

Every task above:

- starts with `- [ ]`
- has a task ID (T001-T047) in execution order
- includes `[P]` if and only if parallelizable
- includes `[US1]`/`[US2]`/`[US3]` if and only if in a user story
  phase (Phases 3, 4, 5)
- references the exact file path under `cardano-tx-tools/` where
  the work happens.

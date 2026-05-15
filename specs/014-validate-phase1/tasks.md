---
description: "Task list for 014-validate-phase1"
---

# Tasks: Phase-1 pre-flight for unsigned transactions

**Input**: [spec.md](./spec.md), [plan.md](./plan.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[contracts/validate-phase1.md](./contracts/validate-phase1.md),
[quickstart.md](./quickstart.md)

**TDD discipline**: every task below is a vertical slice per constitution
VII — RED+GREEN folds into one commit. No "added tests" follow-up
commits. The test and the implementation in the same task land in
the same commit; the test is written first, watched to fail, then the
implementation makes it pass.

**Existing infrastructure** (do NOT recreate):

- `test/fixtures/pparams.json` — mainnet pparams snapshot, already used by `Cardano.Tx.BuildSpec`.
- `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex` — the post-fix unsigned body PR #9 emits.
- `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs/<txid>.cbor.hex` — two producer-tx CBORs (`59e10ca5…` produces inputs #0+#2, `f5f1bdfa…` produces reference input #0), fetched via Blockfrost and committed for offline replay. The companion `utxo.json` stays in the tree as human documentation but the tests no longer read it.
- `loadPParams`, `loadBody` helpers in `test/Cardano/Tx/BuildSpec.hs` — see [test/Cardano/Tx/BuildSpec.hs:120-135](https://github.com/lambdasistemi/cardano-tx-tools/blob/014-validate-phase1/test/Cardano/Tx/BuildSpec.hs#L120-L135). `loadUtxo` is the new helper this PR adds; reuse the existing two as-is.
- hspec `unit-tests` test-suite, already wired.

**Pre-fix and dual-failure bodies are NOT separate fixtures** — they are derived at test time by mutating the post-fix body's CBOR (one-line lens setter for the integrity hash; one-line setter for the fee). Per [plan.md Phase 0 R4](./research.md#r4-utxo-json-shape-from-cardano-cli-query-utxo-output-json) we don't invent a new fixture format.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Wire the new library dependencies. No behavior change.

- [ ] T001 Add `cardano-ledger-shelley` and `data-default` to the main library's `build-depends` in `cardano-tx-tools.cabal`. See [plan.md "Build-plan deltas"](./contracts/validate-phase1.md#build-plan-deltas) for the exact two-line addition. Verify `nix flake check` still passes (no warnings, no version-bound surprises). Commit message: `chore(014): add cardano-ledger-shelley + data-default to library deps`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Test-only helper that every story below uses to load
the existing UTxO fixture. Single vertical slice — test + impl
together.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T002 Implement `loadUtxo :: FilePath -> [TxIn] -> IO [(TxIn, TxOut ConwayEra)]` in `test/Cardano/Tx/Validate/LoadUtxo.hs`. The helper reads a directory of producer-tx CBOR-hex files (one per producer `TxId`), decodes each with the ledger's canonical decoder (`decodeFullAnnotator` over `ConwayTx`), and indexes into each producer tx's outputs by `TxIx` to resolve the requested inputs. See [research.md R4](./research.md#r4-utxo-evidence-shape-producer-tx-cbors-revised-mid-implementation). Producer-tx CBORs already on disk under `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs/`. Wire a single hspec sanity test at `test/Cardano/Tx/Validate/LoadUtxoSpec.hs` that resolves the three TxIns referenced by the issue-#8 body and asserts the returned list has three entries with the expected lovelace values. Register both modules in the `unit-tests` `other-modules` and `LoadUtxoSpec` in `unit-main.hs`. Commit: `feat(014): loadUtxo test helper resolves UTxO from producer-tx CBORs`.

**Checkpoint**: `loadUtxo` is callable from any subsequent test task.

---

## Phase 3: User Story 1 — Pre-flight catches a structural bug (Priority: P1) 🎯 MVP

**Goal**: ship `validatePhase1`. After this phase the unsigned-tx
pre-flight contract is live and exercised against the issue-#8
reproduction.

**Independent Test**: `nix develop -c just unit-tests` runs the
hspec `Cardano.Tx.Validate.validatePhase1` describe green; the
quickstart workflow in [quickstart.md](./quickstart.md) executes
end-to-end against the committed fixture.

### Implementation slice 1 — kernel + happy path (acceptance #1, #3)

- [ ] T003 [US1] Create `src/Cardano/Tx/Validate.hs` with the [module header from contracts/validate-phase1.md](./contracts/validate-phase1.md#module-header-haddock-normative) and a public `validatePhase1` function whose body synthesises `Globals` (per [research.md R3 table](./research.md#r3-globals-constants), network-parameterised on the `Network` argument; remaining fields hardcoded), seeds a fresh `NewEpochState` via `def :: NewEpochState ConwayEra` with lens setters for epoch/pparams/UTxO, builds `MempoolEnv` + `MempoolState`, and calls `Cardano.Ledger.Shelley.API.Mempool.applyTx`. Return `Right ()` on accept, `Left e` on reject; do NOT filter the failure list. Register the new module in `library`'s `exposed-modules`. Wire `test/Cardano/Tx/ValidateSpec.hs` with the first acceptance test (spec.md Story 1 scenario 3): load the post-fix body fixture + the existing utxo.json via `loadUtxo`, call `validatePhase1`, assert the result is `Left _` AND every constructor in the carried `NonEmpty ConwayLedgerPredFailure` is a witness-completeness one (use a local `isWitnessNoise` helper in the test; not yet exported). Register `ValidateSpec` in the test-suite. Commit: `feat(014): validatePhase1 kernel + post-fix happy-path test`.

### Implementation slice 2 — filter helper (FR-010)

- [ ] T004 [US1] Add `isWitnessCompletenessFailure :: ConwayLedgerPredFailure ConwayEra -> Bool` to `Cardano.Tx.Validate`'s public surface, with the Haddock locked in [contracts/validate-phase1.md `isWitnessCompletenessFailure`](./contracts/validate-phase1.md#iswitnesscompletenessfailure). Refactor the test's local `isWitnessNoise` from T003 to use the exported helper instead. Add a small unit test that pattern-matches on a manually-constructed `MissingVKeyWitnessesUTXOW` and asserts `isWitnessCompletenessFailure` returns `True`. Commit: `feat(014): isWitnessCompletenessFailure helper + locked noise list`.

### Implementation slice 3 — pre-fix integrity-hash mutation (acceptance #4 / SC-002)

- [ ] T005 [US1] Add a test in `ValidateSpec.hs` that derives a "pre-fix" body by mutating the post-fix body's `scriptIntegrityHashTxBodyL` to the *wrong* hash (the original mainnet-rejected one — `41a7cd5798b8b6f081bfaee0f5f88dc02eea894b7ed888b2a8658b3784dcdcf9`, already in `BuildSpec.hs` as `expectedIntegrityHash`; we mutate to a different bytes string so it diverges). Call `validatePhase1`, assert the carried `NonEmpty` contains a `ConwayUtxowFailure` with a `PPViewHashesDontMatch` (or equivalent integrity-hash-mismatch constructor name at the pinned ledger version). Commit: `feat(014): pre-fix integrity-hash mutation locks SC-002`.

### Implementation slice 4 — zero-fee mutation (acceptance #2)

- [ ] T006 [US1] Add a test in `ValidateSpec.hs` that derives a corrupted body by setting `feeTxBodyL .~ Coin 0`. Call `validatePhase1`, assert the carried `NonEmpty` contains a fee-related failure constructor (likely `ConwayUtxowFailure (UtxoFailure (FeeTooSmallUTxO _ _))` at the pinned ledger version — confirm the exact constructor name during implementation). Commit: `feat(014): zero-fee mutation locks acceptance scenario 2`.

**Checkpoint**: User Story 1 fully functional. Pre-flight catches structural bugs on the issue-#8 reproduction. MVP done.

---

## Phase 4: User Story 2 — Full failure list in one call (Priority: P2)

**Goal**: lock in the accumulating behaviour of `applyTx` (research finding recorded in spec.md). Useful for incident response.

**Independent Test**: one new hspec test asserts two distinct structural failure constructors appear in the same `applyTx` result.

- [ ] T007 [US2] Add a test in `ValidateSpec.hs` that derives a doubly-corrupted body (fee zeroed AND integrity hash mutated to wrong value, combining the mutations from T005 and T006). Call `validatePhase1`, assert the carried `NonEmpty` contains BOTH the fee-related constructor AND the integrity-hash-mismatch constructor in the same result (i.e. `applyTx` did NOT short-circuit on the first one). Commit: `feat(014): two-failure case locks SC-003 accumulating behaviour`.

**Checkpoint**: User Story 2 done; SC-003/SC-004 locked.

---

## Phase 5: Edge cases & defensive coverage

**Purpose**: lock the mempool-short-circuit edge case the spec explicitly calls out.

- [ ] T008 [P] Add a test in `ValidateSpec.hs` that calls `validatePhase1` with an empty UTxO list `[]`. Assert the result is `Left _` AND the carried `NonEmpty` contains the mempool duplicate-detection failure (likely `ConwayMempoolFailure _` at the pinned ledger version — confirm the exact constructor name during implementation) — i.e. the LEDGER subrule did NOT run because of the `whenFailureFreeDefault` gate documented in [spec.md "Research finding"](./spec.md#research-finding-recorded-for-posterity). The test name MUST reference the spec edge-case bullet so the link is greppable. Commit: `feat(014): empty-UTxO mempool short-circuit edge case`.

---

## Phase 6: Polish & cross-cutting concerns

- [ ] T009 [P] Update `CHANGELOG.md` with a `### Added` entry under the unreleased section: "Phase-1 pre-flight validator `Cardano.Tx.Validate.validatePhase1` for catching ledger structural bugs in unsigned Conway transactions before signing or submission." Reference [PR #16](https://github.com/lambdasistemi/cardano-tx-tools/pull/16). Commit: `docs(014): CHANGELOG entry for validatePhase1`.
- [ ] T010 [P] Re-run the `quickstart.md` workflow against the merged code: `nix develop -c just unit-tests` green, the `Cardano.Tx.Validate.validatePhase1` hspec describe runs all five tests (T003-T008), no skipped cases. Record the run in a comment on PR #16 with the timing. No commit (validation step).
- [ ] T011 Run the full local CI gate: `nix flake check`. All checks green including `cabal-check`, `fourmolu -m check`, `hlint`, build, test. No commit (validation step).
- [ ] T012 Update the PR description on [#16](https://github.com/lambdasistemi/cardano-tx-tools/pull/16) with the final commit list, the link to each spec/plan/tasks/research/contracts/quickstart doc on the branch, and a one-line summary of how to read the test names back to spec acceptance scenarios. Per memory rule "Update PR description". No commit.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (T001)**: no prerequisites. Independent commit.
- **Phase 2 (T002)**: needs T001 only because cabal compiles — `loadUtxo` doesn't itself use the new deps, but it sits in the same `unit-tests` suite that will use them in Phase 3.
- **Phase 3 (T003-T006)**: needs Phase 2 (uses `loadUtxo`). Within Phase 3, the slices are **sequential**:
  - T003 establishes the kernel and registers the module — every later slice imports from it.
  - T004 extends the public surface; later slices' tests use the exported helper.
  - T005, T006 each add an independent test case to the same `ValidateSpec.hs`. They could nominally be done in either order; we keep them sequential to keep each commit small and bisect-safe.
- **Phase 4 (T007)**: needs T005 and T006 (re-uses the mutation utilities).
- **Phase 5 (T008)**: needs Phase 3 (the validator surface). Independent of Phase 4. **Parallelisable** with T007 if a separate developer.
- **Phase 6 (T009-T012)**: needs Phase 3-5 done.

### Within each phase

- Each task is a single vertical commit per constitution VII.
- Tests written first, watched to fail, then implementation makes them pass — all in one commit (RED+GREEN).
- No fixup, no "added tests" follow-up.

### Parallel opportunities

- T008 (Phase 5) can run in parallel with T007 (Phase 4).
- T009 and T010 (Phase 6) are fully parallel.
- Everything else is sequential by design — small per-commit scope, tight feedback loop.

---

## Implementation Strategy

### MVP scope (User Story 1, T001-T006)

1. T001 cabal deps.
2. T002 `loadUtxo` helper.
3. T003-T006 — the full Story 1 surface. After T006 the pre-flight is live and locks the issue-#8 reproduction in both directions.
4. **Stop and validate**: `nix flake check` green; the four Story-1 hspec tests pass.
5. PR #16 could merge here if Story 2 is deferred.

### Incremental delivery

- T001-T002: foundation. No public surface change yet.
- T003-T006: User Story 1 MVP. `Cardano.Tx.Validate` ships on the library's public surface. Demo-able: `loadBody fixture >>= \tx -> print (validatePhase1 Mainnet pp utxo slot tx)`.
- T007: Story 2 increment. Confirms accumulating behaviour.
- T008: edge case lockdown.
- T009-T012: polish, CHANGELOG, PR.

### Bisect-safe contract

Every commit on the branch compiles AND has its test suite green.
No half-finished file states. No "skip" markers. If a commit
introduces a fixture, the test that uses it ships in the same
commit.

---

## Notes

- File path for every task is concrete; no `[location]` placeholders.
- `[Story]` labels appear only on Phase 3-4 tasks (Phases 1-2 and 5-6 are infrastructure / cross-cutting).
- `[P]` parallelism is conservative — within Phase 3 the slices share `ValidateSpec.hs` so they're not in-parallel even though they're conceptually independent.
- Memory rules applied: every artifact link in this file points at the branch on GitHub for browser review; commit messages follow the Conventional Commits convention; cabal deps are explicit per constitution IV; the duplication-not-dependency choice is recorded in spec.md "Implementation strategy" (referenced from T003's Haddock requirement, not restated here per `feedback_tasks_reference_contracts.md`).

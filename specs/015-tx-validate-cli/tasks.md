---
description: "Task list for 015-tx-validate-cli"
---

# Tasks: tx-validate CLI

**Input**: [spec.md](./spec.md), [plan.md](./plan.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[contracts/cli.md](./contracts/cli.md),
[contracts/json-output.md](./contracts/json-output.md),
[quickstart.md](./quickstart.md)

**TDD discipline (constitution VII)**: every task below is a vertical
slice — RED+GREEN folds into one commit. No fixup, no "added tests"
follow-up. Each commit on the branch compiles AND has the test suite
green.

**Reused infrastructure** (do NOT recreate):

- `Cardano.Tx.Validate.validatePhase1` + `isWitnessCompletenessFailure` from PR #16.
- `Cardano.Tx.Diff.Resolver` (`Resolver`, `resolveChain`) — unchanged.
- `Cardano.Tx.Diff.Resolver.N2C.n2cResolver` from `lib-n2c-resolver` — unchanged.
- `Cardano.Tx.Diff.Resolver.Web2.web2Resolver` + `httpFetchTx` — unchanged.
- `Cardano.Tx.BuildSpec.loadBody` + `loadPParams` test helpers — unchanged.
- `Cardano.Tx.Validate.LoadUtxo.loadUtxo` — reused for the offline fixture wiring.
- `flake.nix`'s existing `txDiff` / `mkTxDiffDarwinHomebrewBundle` / `linux-release.nix` / `docker-image.nix` patterns — copied verbatim, parameterised.

**No new fixtures** — the post-fix and pre-fix issue-#8 bodies + producer-tx CBORs from spec 014's PR #16 cover every scenario this PR's tests need.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: cabal wiring; no behaviour change yet.

- [ ] T001 In `cardano-tx-tools.cabal`, register the new module `Cardano.Tx.Validate.Cli` (and its child `Cardano.Tx.Validate.Cli.Blockfrost`) under the main library's `exposed-modules` list (per [plan.md "Source Code"](./plan.md#source-code-repository-root)). Add the new `executable tx-validate` stanza (`hs-source-dirs: app/tx-validate`, `main-is: Main.hs`, depends on the main library + `optparse-applicative`). Add the new `test-suite tx-validate-tests` stanza (`hs-source-dirs: test`, `main-is: tx-validate-main.hs`, `other-modules: Cardano.Tx.Validate.CliSpec, Cardano.Tx.Validate.Cli.BlockfrostSpec`, hspec + the main library + n2c-resolver). Commit message: `chore(015): cabal wiring for tx-validate executable + test-suite`.

---

## Phase 2: Foundational (Blockfrost client + session driver)

**Purpose**: the two pieces every user story below uses — typed Blockfrost HTTP record-of-functions and the `withSession` bracket. Both ship with their unit-level coverage in the same commit.

**⚠️ CRITICAL**: User-story work cannot begin until Phase 2 is complete.

- [ ] T002 Create `src/Cardano/Tx/Validate/Cli/Blockfrost.hs` with the `BlockfrostClient` record-of-functions + `BlockfrostError` ADT per [research.md R3-R4](./research.md#r3-blockfrost-blocks-latest-json) + [data-model.md](./data-model.md#new-typed-surface). Production wiring: `mkBlockfrostClient :: Manager -> Text -> Maybe Text -> BlockfrostClient IO` fetching `GET <base>/epochs/latest/parameters` (decoded into `PParams ConwayEra` via the upstream `FromJSON` instance) and `GET <base>/blocks/latest` (parse only the `slot` field). Sanity test in `test/Cardano/Tx/Validate/Cli/BlockfrostSpec.hs`: feed canned JSON to the decoders, assert the produced `PParams` parses and the `SlotNo` matches. Commit: `feat(015): BlockfrostClient record-of-functions for pparams + tip slot`.

- [ ] T003 Create `src/Cardano/Tx/Validate/Cli.hs` with the option ADT (`TxValidateCliOptions`, `InputSource`, `OutputFormat`, `PrimarySession`, `N2cConfig`, `Web2Config`) and the `withSession :: TxValidateCliOptions -> (Session -> IO a) -> IO a` bracket per [data-model.md `Session`](./data-model.md#session) + [research.md R5](./research.md#r5-primary-session-lifecycle). For N2C primary: open the cardano-node-clients backend, query `PParams` + tip slot, build the `n2cResolver`. For Blockfrost primary: build the HTTP `Manager`, call the `BlockfrostClient`, build the `web2Resolver`. The `[Resolver]` carried by the `Session` MUST be ordered N2C-first iff N2C is in the chain. Test in `test/Cardano/Tx/Validate/CliSpec.hs`: drive `withSession` with two stub configs (mock-N2C + stub-Blockfrost), assert each side populates `sessionPParams` + `sessionSlot` + `sessionPrimary` + `sessionUtxoResolvers` correctly. Commit: `feat(015): withSession bracket for the resolver session`.

**Checkpoint**: a caller can acquire a `Session` from either source.

---

## Phase 3: User Story 1 — Signing daemon catches a structural bug via N2C (Priority: P1) 🎯 MVP

**Goal**: ship the `tx-validate` executable. After this phase, the CLI is callable, produces a verdict on the issue-#8 fixture against an N2C mock, and exits with the right code.

**Independent Test**: from the test-suite, invoke the parser + session driver + `validatePhase1` + human-renderer end-to-end against the post-fix + pre-fix fixtures with a stubbed N2C provider; assert exit codes and stdout shapes match [contracts/cli.md](./contracts/cli.md).

### Slice 1 — option parser + happy-path verdict (human format)

- [ ] T004 [US1] Extend `Cardano.Tx.Validate.Cli` with `parseArgs :: [String] -> Either Text TxValidateCliOptions` (built on `optparse-applicative`) covering FR-002 + the positional-primary-session rule (FR-004). Wire `app/tx-validate/Main.hs` as a thin entry: parse args; run `withSession`; load the tx; resolve the UTxO; call `validatePhase1`; build a `Verdict`; render human; exit with the mapped exit code. Add `renderHuman :: Verdict -> Text` (verdict line + structural-failure lines per [contracts/cli.md "Standard output"](./contracts/cli.md#standard-output-human-format)). Test in `CliSpec.hs`: call `parseArgs` with the happy-path argv (`["--input", "test/fixtures/.../body.cbor.hex", "--n2c-socket", "/tmp/sock"]`), assert the options are well-formed; call the end-to-end driver with a stubbed N2C provider serving the issue-#8 producer-tx CBORs and the committed `pparams.json`, assert the verdict status is `StructurallyClean` and `renderHuman` matches the locked shape. Commit: `feat(015): option parser + human verdict renderer (US1 happy path)`.

### Slice 2 — structural failure case (pre-fix body)

- [ ] T005 [US1] Add a test in `CliSpec.hs` that drives the end-to-end pipeline on the **pre-fix** issue-#8 body (the committed fixture, unmodified — same path PR #16's `Cardano.Tx.ValidateSpec` uses for SC-002). Assert `verdictStatus = StructuralFailure`, `verdictStructuralFailures` contains the integrity-hash-mismatch constructor (recognised by `isIntegrityHashMismatch` from `ValidateSpec`, re-exported as needed), exit code maps to `1`, and `renderHuman` emits exactly one structural-failure line. Commit: `feat(015): pre-fix body surfaces the structural failure (SC-003)`.

### Slice 3 — JSON renderer + envelope test

- [ ] T006 [US1] Add `renderJson :: Verdict -> Aeson.Value` to `Cardano.Tx.Validate.Cli`, producing the envelope locked in [contracts/json-output.md](./contracts/json-output.md). Extend `parseArgs` so `--output json` flips the format. Test in `CliSpec.hs`: drive the end-to-end pipeline with `--output json` against the post-fix and pre-fix fixtures; assert the JSON shapes match the two worked examples in `contracts/json-output.md` (`structurally_clean` + `structural_failure` cases). Commit: `feat(015): JSON envelope renderer (FR-007)`.

**Checkpoint**: User Story 1 is fully functional. The executable handles the happy path, the structural-failure path, and both output formats. MVP done.

---

## Phase 4: User Story 2 — Blockfrost CI gate (Priority: P1)

**Goal**: a tx-validate invocation against a Blockfrost endpoint produces the same verdict as the N2C path, with the source labelled `blockfrost`.

**Independent Test**: from the test-suite, drive the end-to-end pipeline with a stubbed `BlockfrostClient` returning the committed `pparams.json` (re-encoded as Blockfrost JSON) and stub the Web2 fetcher to serve the producer-tx CBORs. Assert verdict matches Story 1 with `pparams_source = "blockfrost"`.

### Slice 1 — Blockfrost happy path end-to-end

- [ ] T007 [US2] Add a test in `CliSpec.hs` that drives the end-to-end pipeline with `--blockfrost-base https://stub --blockfrost-key fake`, injecting a stub `BlockfrostClient` (returning the committed `pparams.json` + a fixed `SlotNo`) and a stub `Web2FetchTx` that serves the producer-tx CBORs from the committed fixtures. Assert verdict is `StructurallyClean` and the JSON envelope's `pparams_source` / `slot_source` / `utxo_sources` all carry `"blockfrost"`. Commit: `feat(015): Blockfrost end-to-end (US2 happy path, SC-002 part c)`.

### Slice 2 — missing API key configuration error

- [ ] T008 [US2] Add a test in `CliSpec.hs` that calls `parseArgs` with `--blockfrost-base URL` but no `--blockfrost-key` AND no `BLOCKFROST_PROJECT_ID` env var; assert `parseArgs` returns `Left` whose `Text` payload identifies the missing key. Confirm via a second test that `--blockfrost-key …` and `BLOCKFROST_PROJECT_ID=…` are interchangeable. Commit: `feat(015): blockfrost API key required + env-var fallback`.

### Slice 3 — unresolved UTxO error (404 from Blockfrost)

- [ ] T009 [US2] Add a test that injects a `Web2FetchTx` stub returning `Left BlockfrostHttp404` for one of the three issue-#8 producer TxIds. Assert the end-to-end pipeline exits with the resolver-error code (`4`), the stdout verdict is NOT printed, and stderr names the unresolved `<txid>#<ix>`. Commit: `feat(015): unresolved UTxO surfaces resolver error (exit 4)`.

**Checkpoint**: User Story 2 done. The Blockfrost path covers happy + missing-key + 404-from-endpoint cases.

---

## Phase 5: User Story 3 — Chained N2C-first / Blockfrost-fallback (Priority: P2)

**Goal**: lock the resolver-chain semantics with both flags present. `PParams` + slot come from the primary source (first on the command line); UTxO is union with N2C-first ordering.

**Independent Test**: drive the end-to-end pipeline with both flags. Stub N2C to resolve 2 of 3 inputs; stub Blockfrost to resolve the 3rd. Assert verdict reflects the full UTxO and `utxo_sources` carries the per-input decisions.

- [ ] T010 [US3] Add a test in `CliSpec.hs` that supplies both `--n2c-socket` and `--blockfrost-base` (N2C first). Stub the N2C provider to resolve `59e10ca5…#0` and `#2` but NOT `f5f1bdfa…#0`. Stub the `Web2FetchTx` to resolve `f5f1bdfa…#0`. Assert verdict is `StructurallyClean` (the union covers all three inputs), `pparams_source = "n2c"` (positional primary), and `utxo_sources` maps `59e10ca5…#0/#2` to `n2c` and `f5f1bdfa…#0` to `blockfrost`. Commit: `feat(015): chained resolver fallback locks Story-3 contract`.

**Checkpoint**: all three stories done; spec acceptance scenarios for each are covered in tests.

---

## Phase 6: Release plumbing (parallelisable)

**Purpose**: ship `tx-validate` artefacts on the next tag. Each slice is an additive `flake.nix` block + its dependency in the existing pipeline; they're independent and can run in any order, but all are required for FR-009 / SC-006.

- [ ] T011 [P] Extend `flake.nix` with a `txValidate = pkgs.symlinkJoin { name = "tx-validate"; … }` wrapper that injects `SSL_CERT_FILE` via `pkgs.cacert` (mirror of `txDiff` lines 131-140). Add `packages.tx-validate = txValidate` and `apps.tx-validate` so `nix run .#tx-validate` works. Commit: `feat(015): nix wrapper + apps.tx-validate`.

- [ ] T012 [P] Extend `flake.nix` with `mkTxValidateDarwinHomebrewBundle` (mirror of `mkTxDiffDarwinHomebrewBundle` lines 162-187). Wire it into `darwinReleasePackages` as `tx-validate-darwin-release-artifacts` + `tx-validate-darwin-dev-homebrew-artifacts`. Commit: `feat(015): Darwin / Homebrew bundle for tx-validate`.

- [ ] T013 [P] Extend `flake.nix` with `tx-validate-linux-release-artifacts` + `tx-validate-linux-dev-release-artifacts` blocks (mirror of `cardano-tx-generator-linux-{release,dev-release}-artifacts` lines 220-234). Commit: `feat(015): Linux release artefacts (AppImage / DEB / RPM) for tx-validate`.

- [ ] T014 [P] Add a `tx-validate-image` Docker image to `flake.nix` (mirror of `cardanoTxGeneratorImage` lines 240-243 + line 263). Commit: `feat(015): Docker image for tx-validate`.

- [ ] T015 Extend `nix/linux-artifact-smoke.nix` to smoke-test the `tx-validate` AppImage too — invoke `--help` and assert exit code + that `Usage:` appears in stdout. Mirror the existing tx-diff smoke. Commit: `feat(015): linux-artifact-smoke covers tx-validate`.

**Checkpoint**: `nix flake check` evaluates all the new packages; the release pipeline produces artefacts on the next tag.

---

## Phase 7: Polish & cross-cutting concerns

- [ ] T016 [P] Update `CHANGELOG.md` with an `### Added` entry under the unreleased section: "Cardano Conway transaction Phase-1 validator CLI `tx-validate`, with N2C + Blockfrost resolver session support and human / JSON output." Reference [PR #20](https://github.com/lambdasistemi/cardano-tx-tools/pull/20). Commit: `docs(015): CHANGELOG entry for tx-validate`.

- [ ] T017 [P] Update `docs/index.md`'s "What lives here" list to mention `tx-validate` alongside `tx-diff` and `cardano-tx-generator`. Commit: `docs(015): docs/index.md lists tx-validate`.

- [ ] T018 [P] Update `README.md` similarly — add `tx-validate` to the "What's here" list. Commit: `docs(015): README lists tx-validate`.

- [ ] T019 Run the full local CI gate: `nix flake check --no-eval-cache`. All checks must be green including the new release-artefact derivations. No commit (validation step).

- [ ] T020 Update PR #20 description with the final commit list, links to each spec/plan/tasks/research/contracts/quickstart doc on the branch, and a one-line summary of how to read the test names back to spec acceptance scenarios. Per memory rule "Update PR description". No commit.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (T001)**: cabal wiring. No prerequisites.
- **Phase 2 (T002, T003)**: needs T001 (so the cabal stanzas exist). T002 and T003 are *sequential* within Phase 2 — T003 imports `BlockfrostClient` from T002 in the `withSession` Blockfrost branch.
- **Phase 3 (T004-T006)**: needs Phase 2. Within Phase 3, the slices are **sequential**:
  - T004 introduces the parser + driver + human renderer; subsequent slices build on it.
  - T005 reuses T004's harness.
  - T006 adds the JSON path alongside.
- **Phase 4 (T007-T009)**: needs Phase 3. Within Phase 4, slices are **sequential** — T007 introduces the Blockfrost stub harness; T008 / T009 extend it.
- **Phase 5 (T010)**: needs Phases 3 + 4 (both N2C and Web2 stub harnesses).
- **Phase 6 (T011-T015)**: needs Phase 1 only (the executable exists once T001 lands + Main is present). **Parallelisable** with Phases 3-5 if a separate developer.
- **Phase 7 (T016-T020)**: needs Phases 3-6.

### Parallel opportunities

- **T011, T012, T013, T014** are independent flake-nix blocks; can be developed in parallel by separate developers.
- **T016, T017, T018** are independent docs edits.
- All of Phase 6 can run alongside Phase 3 / 4 / 5 if staffed in parallel.

### Within each user story

- Each task is a single vertical commit per constitution VII.
- The test is written first, watched to fail, then the implementation makes it pass — all in one commit.
- No fixup, no "added tests" follow-ups.

---

## Implementation Strategy

### MVP scope (User Story 1, T001-T006)

1. T001 cabal wiring.
2. T002 `BlockfrostClient` record (needed even for the N2C-only path, because `withSession` is wired for both paths; the Blockfrost branch just won't run in the US1 tests).
3. T003 `withSession`.
4. T004-T006 the executable + the three US1 cases (human happy, human structural, JSON envelope).
5. **Stop and validate**: `nix flake check` green; PR #20 could merge here if Stories 2-3 are deferred.

### Incremental delivery

- T001-T003: foundation. No CLI surface yet.
- T004-T006: User Story 1 MVP. The executable is callable end-to-end against N2C.
- T007-T009: User Story 2 increment. Blockfrost path lit up; the executable becomes useful without a local node.
- T010: User Story 3 increment. Chained resolver semantics locked.
- T011-T015: release plumbing. Tag fires; binaries publish.
- T016-T020: polish.

### Bisect-safe contract

Every commit on the branch compiles AND has its test suite green. If a commit introduces a fixture-shaped harness (e.g. T007's Blockfrost stub), the test that uses it ships in the same commit.

---

## Notes

- File paths in every task are concrete; no placeholders.
- `[Story]` labels appear only on Phase 3-5 tasks (Phases 1-2 and 6-7 are infrastructure / cross-cutting).
- `[P]` parallelism is honest — flagged only on tasks that touch independent files (Phase 6 release blocks, Phase 7 doc edits).
- Memory rules applied: every artefact link in this file points at the branch on GitHub for browser review; commit messages follow Conventional Commits; the duplication-not-rename choice (`Diff.Resolver.*` reused as-is) is recorded in spec.md "Assumptions" + plan.md, not restated here per `feedback_tasks_reference_contracts.md`.

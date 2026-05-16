---
description: "Task list for 015-tx-validate-cli"
---

# Tasks: tx-validate CLI

**Input**: [spec.md](./spec.md), [plan.md](./plan.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[contracts/cli.md](./contracts/cli.md),
[contracts/json-output.md](./contracts/json-output.md),
[quickstart.md](./quickstart.md)

**Scope note** (2026-05-16): Blockfrost path deferred to
[#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).
v1 is N2C-only.

**TDD discipline (constitution VII)**: every task below is a vertical
slice — RED+GREEN folds into one commit. No fixup, no "added tests"
follow-up. Each commit on the branch compiles AND has the test suite
green.

**Reused infrastructure** (do NOT recreate):

- `Cardano.Tx.Validate.validatePhase1` + `isWitnessCompletenessFailure` from PR #16.
- `Cardano.Tx.Diff.Resolver` (`Resolver`, `resolveChain`) — unchanged.
- `Cardano.Tx.Diff.Resolver.N2C.n2cResolver` from `lib-n2c-resolver` — unchanged.
- `Cardano.Tx.BuildSpec.loadBody` + `loadPParams` test helpers — unchanged.
- `Cardano.Tx.Validate.LoadUtxo.loadUtxo` — reused for the offline fixture wiring.
- `flake.nix`'s existing `txDiff` / `mkTxDiffDarwinHomebrewBundle` / `linux-release.nix` / `docker-image.nix` patterns — copied verbatim, parameterised.

**No new fixtures** — the post-fix and pre-fix issue-#8 bodies + producer-tx CBORs from spec 014's PR #16 cover every scenario this PR's tests need.

---

## Phase 1: Setup + N2C session driver

**Purpose**: cabal wiring AND the typed session driver, in one slice — there's no useful intermediate state.

- [ ] T001 In `cardano-tx-tools.cabal`, register `Cardano.Tx.Validate.Cli` under the main library's `exposed-modules`. Add the new `executable tx-validate` stanza (`hs-source-dirs: app/tx-validate`, `main-is: Main.hs`, depends on main library + n2c-resolver + `optparse-applicative`). Add the new `test-suite tx-validate-tests` stanza (`hs-source-dirs: test`, `main-is: tx-validate-main.hs`, `other-modules: Cardano.Tx.Validate.CliSpec`, hspec + main library + n2c-resolver). Implement `src/Cardano/Tx/Validate/Cli.hs` with the option ADT (`TxValidateCliOptions`, `InputSource`, `OutputFormat`, `N2cConfig`) and the `withSession :: TxValidateCliOptions -> (Session -> IO a) -> IO a` bracket per [data-model.md `Session`](./data-model.md#session) + [research.md R5](./research.md#r5-n2c-session-lifecycle): open the cardano-node-clients backend via `withLocalNodeBackend`, query `PParams` + tip slot, build the `n2cResolver`, wrap into `Session`, run the action, tear down. Implement `app/tx-validate/Main.hs` as a stub that calls `withSession` with mock options and prints the populated `Session` (placeholder; the parser + verdict logic lands in T002). Wire `test/tx-validate-main.hs` to drive a stubbed mock provider and assert the produced `Session` has the right shape (a "fixture provider" returning the committed `pparams.json` + a hardcoded slot + the producer-tx UTxOs via the existing `loadUtxo` helper). Commit: `feat(015): cabal wiring + withSession N2C bracket`.

---

## Phase 2: User Story 1 — Signing daemon catches a structural tx bug (Priority: P1) 🎯 MVP

**Goal**: ship the executable. After this phase, the CLI is callable end-to-end against a mocked N2C session and validates the issue-#8 fixture, exiting with the right code.

**Independent Test**: from the test-suite, invoke the parser + session driver + `validatePhase1` + renderer end-to-end against the post-fix + pre-fix fixtures with a stubbed `Provider`; assert exit codes and stdout shapes match [contracts/cli.md](./contracts/cli.md) + [contracts/json-output.md](./contracts/json-output.md).

### Slice 1 — parser + happy-path verdict (human format)

- [ ] T002 [US1] Extend `Cardano.Tx.Validate.Cli` with `parseArgs :: [String] -> Either Text TxValidateCliOptions` built on `optparse-applicative`, covering [contracts/cli.md "Flags"](./contracts/cli.md#flags). Wire `app/tx-validate/Main.hs` as a thin entry: parse args; run `withSession`; load the tx; resolve the UTxO via the session's resolver chain; call `validatePhase1`; build a `Verdict`; render human; exit with the mapped exit code. Add `renderHuman :: Verdict -> Text` per [contracts/cli.md "Standard output"](./contracts/cli.md#standard-output-human-format). Test in `CliSpec.hs`: assert `parseArgs` accepts the happy-path argv; assert the end-to-end driver with a stubbed `Provider` serving the issue-#8 producer-tx UTxOs + committed `pparams.json` produces `verdictStatus = StructurallyClean`, `renderHuman` matches the locked shape, and `exitCodeOf = 0`. Commit: `feat(015): option parser + human verdict renderer (US1 happy path)`.

### Slice 2 — structural failure case (pre-fix body)

- [ ] T003 [US1] Add a test in `CliSpec.hs` that drives the end-to-end pipeline on the pre-fix issue-#8 body (committed fixture, unmodified). Assert `verdictStatus = StructuralFailure`, `verdictStructuralFailures` contains the integrity-hash-mismatch constructor, exit code maps to `1`, and `renderHuman` emits exactly one structural-failure line per [contracts/cli.md "Structural-failure line shape"](./contracts/cli.md#standard-output-human-format). Commit: `feat(015): pre-fix body surfaces the structural failure (SC-003)`.

### Slice 3 — JSON renderer + envelope test

- [ ] T004 [US1] Add `renderJson :: Verdict -> Aeson.Value` to `Cardano.Tx.Validate.Cli`, producing the envelope locked in [contracts/json-output.md](./contracts/json-output.md). Extend `parseArgs` so `--output json` flips the format. Test in `CliSpec.hs`: drive the end-to-end pipeline with `--output json` against the post-fix and pre-fix fixtures; assert the JSON shapes match the two worked examples in `contracts/json-output.md`. Commit: `feat(015): JSON envelope renderer (FR-007)`.

**Checkpoint**: User Story 1 is fully functional. The executable handles the happy path, the structural-failure path, and both output formats. MVP done.

---

## Phase 3: Release plumbing (parallelisable)

**Purpose**: ship `tx-validate` artefacts on the next tag. Each slice is an additive `flake.nix` block + its dependency in the existing pipeline; they're independent and can run in any order, but all are required for FR-009 / SC-006.

- [ ] T005 [P] Extend `flake.nix` with a `txValidate = pkgs.symlinkJoin { name = "tx-validate"; … }` wrapper that injects `SSL_CERT_FILE` via `pkgs.cacert` (mirror of `txDiff` lines 131-140; the wrapper is forward-compat for the future Blockfrost path). Add `packages.tx-validate = txValidate` and `apps.tx-validate` so `nix run .#tx-validate` works. Commit: `feat(015): nix wrapper + apps.tx-validate`.

- [ ] T006 [P] Extend `flake.nix` with `mkTxValidateDarwinHomebrewBundle` (mirror of `mkTxDiffDarwinHomebrewBundle`). Wire it into `darwinReleasePackages` as `tx-validate-darwin-release-artifacts` + `tx-validate-darwin-dev-homebrew-artifacts`. Commit: `feat(015): Darwin / Homebrew bundle for tx-validate`.

- [ ] T007 [P] Extend `flake.nix` with `tx-validate-linux-release-artifacts` + `tx-validate-linux-dev-release-artifacts` blocks (mirror of `cardano-tx-generator-linux-{release,dev-release}-artifacts`). Commit: `feat(015): Linux release artefacts (AppImage / DEB / RPM) for tx-validate`.

- [ ] T008 [P] Add a `tx-validate-image` Docker image to `flake.nix` (mirror of `cardanoTxGeneratorImage`). Commit: `feat(015): Docker image for tx-validate`.

- [ ] T009 Extend `nix/linux-artifact-smoke.nix` to smoke-test the `tx-validate` AppImage — invoke `--help` and assert exit code + that `Usage:` appears in stdout. Mirror the existing tx-diff smoke. Commit: `feat(015): linux-artifact-smoke covers tx-validate`.

**Checkpoint**: `nix flake check` evaluates all the new packages; the release pipeline produces artefacts on the next tag.

---

## Phase 4: Polish & cross-cutting concerns

- [ ] T010 [P] Update `CHANGELOG.md` with an `### Added` entry under the unreleased section: "Cardano Conway transaction Phase-1 validator CLI `tx-validate`, with N2C resolver session support and human / JSON output. Blockfrost path tracked in #21." Reference [PR #20](https://github.com/lambdasistemi/cardano-tx-tools/pull/20). Commit: `docs(015): CHANGELOG entry for tx-validate`.

- [ ] T011 [P] Update `docs/index.md`'s "What lives here" list to mention `tx-validate` alongside `tx-diff` and `cardano-tx-generator`. Commit: `docs(015): docs/index.md lists tx-validate`.

- [ ] T012 [P] Update `README.md` similarly — add `tx-validate` to the "What's here" list. Commit: `docs(015): README lists tx-validate`.

- [ ] T013 Run the full local CI gate: `nix flake check --no-eval-cache`. All checks must be green including the new release-artefact derivations. No commit (validation step).

- [ ] T014 Update PR #20 description with the final commit list, the scope-reduction note pointing at #21, and links to each spec / plan / tasks / research / contracts / quickstart doc on the branch. Per memory rule "Update PR description". No commit.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (T001)**: cabal wiring + withSession bracket. No prerequisites.
- **Phase 2 (T002-T004)**: needs T001 (so the test harness + Session exist). Within Phase 2, slices are **sequential** — T002 introduces the parser + driver + human renderer; T003 / T004 extend the same test file with new cases.
- **Phase 3 (T005-T009)**: needs T001 (the executable exists once T001 lands). **Parallelisable** with Phase 2 if a separate developer.
- **Phase 4 (T010-T014)**: needs Phases 1-3.

### Parallel opportunities

- **T005, T006, T007, T008** are independent `flake.nix` blocks; can be developed in parallel.
- **T010, T011, T012** are independent docs edits.
- All of Phase 3 can run alongside Phase 2 if staffed in parallel.

### Within each user story

- Each task is a single vertical commit per constitution VII.
- Test written first, watched to fail, then implementation makes it pass — all in one commit.
- No fixup, no "added tests" follow-ups.

---

## Implementation Strategy

### MVP scope (User Story 1, T001-T004)

1. T001 cabal wiring + `withSession`.
2. T002-T004 the executable + the three US1 cases (human happy, human structural, JSON envelope).
3. **Stop and validate**: `nix flake check` green; PR #20 could merge here if release plumbing is deferred (unlikely — Phase 3 is small).

### Incremental delivery

- T001: foundation. Cabal stanzas + `Session` bracket.
- T002-T004: User Story 1 MVP. The executable is callable end-to-end against N2C.
- T005-T009: release plumbing. Tag fires; binaries publish.
- T010-T014: polish.

### Bisect-safe contract

Every commit on the branch compiles AND has its test suite green. If a commit introduces a fixture-shaped harness (e.g. T001's mock `Provider`), the test that uses it ships in the same commit.

---

## Notes

- File paths in every task are concrete; no placeholders.
- `[Story]` labels appear only on Phase 2 tasks (Phase 1 is foundational; Phases 3-4 are infrastructure / cross-cutting).
- `[P]` parallelism is honest — flagged only on tasks that touch independent files.
- Memory rules applied: every artefact link in this file points at the branch on GitHub for browser review; commit messages follow Conventional Commits; the duplication-not-rename choice (`Diff.Resolver.*` reused as-is) is recorded in spec.md "Assumptions" + plan.md, not restated here per `feedback_tasks_reference_contracts.md`.

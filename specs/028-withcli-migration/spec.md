# Feature Specification: Migrate four executables to `withCli` + `versionOption`

**Feature Branch**: `28-withcli-migration`
**Created**: 2026-05-17
**Status**: Draft
**Input**: User description: "Migrate all four shipped executables (tx-validate, tx-diff, cardano-tx-generator, tx-sign) to the new `github-release-check` public API (`withCli` + the `github-release-check:optparse` sublibrary's `versionOption`). Supersedes #27."

## Clarifications

### Session 2026-05-17

- Q: `cardano-tx-generator` uses hand-rolled `takeFlag`/`requireFlag` arg parsing — not `optparse-applicative`. How should it expose `--version`? → A: Pre-parse `--version` inline at the top of `main` (print `cardano-tx-generator <semver>` and `exitSuccess`) before falling through to the existing `parseConfig`. Keep the rest of its parsing untouched. The acceptance criterion is the externally-observable `--version` behaviour, not "must adopt the sublibrary's `versionOption` helper". The sublibrary's `versionOption` is only adopted by the three exes that already use `optparse-applicative`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Every shipped CLI prints the upgrade banner uniformly (Priority: P1)

A user has installed any one of this repo's four executables (`tx-validate`, `tx-diff`, `cardano-tx-generator`, `tx-sign`) and is running an outdated version. When they invoke the executable, the action runs to completion and an upgrade banner appears on stderr afterwards, identically across the four CLIs. The banner rate-limit, cache file, and silent-on-network-failure semantics are preserved verbatim from what `tx-validate` already has today.

**Why this priority**: This is the load-bearing motivation. The repo's identity is "four cardano-tx-tools executables ship as a family"; the family should look uniform to a user who runs more than one.

**Independent Test**: Run each of the four executables with a contrived stale-version cache and observe the banner-on-exit. Run each with `<UPPER_SNAKE_EXE>_NO_UPDATE_CHECK=1` and observe no banner.

**Acceptance Scenarios**:

1. **Given** a fresh install of any of the four executables, **When** the user runs the executable with otherwise-valid args and the cache reports a newer release is available, **Then** the action runs to completion and the upgrade banner prints to stderr after the action returns (matching the existing tx-validate behaviour).
2. **Given** the same four executables, **When** the user sets `<UPPER_SNAKE_EXE>_NO_UPDATE_CHECK=1`, **Then** the action runs and the upgrade-check codepath is a no-op (no GitHub network hit, no banner).
3. **Given** a downstream consumer of `cardano-tx-tools`'s library (any external Haskell package), **When** they upgrade to the post-feature version, **Then** their code compiles unchanged — the migration is additive to the library's public surface.

---

### User Story 2 — `--version` works uniformly across the four executables (Priority: P2)

A user invokes `<exe> --version` for any of the four CLIs and gets `<exe> <semver>` on a single line, exit code `0`, with the version pulled from the same `Paths_cardano_tx_tools.version` that the upgrade-banner check uses.

**Why this priority**: Independent of P1 (a CLI can adopt `withCli` without `--version`). It is P2 because the family-level uniformity story matters: users currently get different `--version` behaviour per executable (some have hand-rolled versionOption, some don't expose `--version` at all).

**Independent Test**: `<exe> --version` for each exe; assert exit 0 + first stdout line equals `<exe> <semver>`.

**Acceptance Scenarios**:

1. **Given** `tx-validate`, `tx-diff`, `tx-sign` (the three exes that use `optparse-applicative`), **When** the user invokes `<exe> --version`, **Then** the executable prints `<exe> <semver>` and exits 0 via the sublibrary's `versionOption banner` plumbed into their parser via `<**>`.
2. **Given** `cardano-tx-generator` (which uses hand-rolled arg parsing), **When** the user invokes `cardano-tx-generator --version`, **Then** the executable prints `cardano-tx-generator <semver>` and exits 0 via an inline `case argv of` short-circuit at the top of `main`.
3. **Given** any of the four executables, **When** `--version` is invoked, **Then** the upgrade-banner check does **not** run (short-circuit before `withCli` enters the wrapped action) — matches the documented edge case in `github-release-check`'s spec.

### Edge Cases

- **Opt-out env var set to empty string**: treated as "disabled" by `withCli` (matches the `isJust <$> lookupEnv` semantics inherited from `github-release-check`). Only unsetting the variable re-enables the check.
- **GitHub network failure / rate limit**: the wrapped action's exit code is unchanged; `github-release-check` is silent on fetch failure.
- **`cardano-tx-generator` user invokes `--version` mixed with other flags** (e.g. `cardano-tx-generator --relay-socket /tmp/foo --version`): the inline short-circuit at the top of `main` only triggers on `["--version"]` (single-element argv). Mixed argv falls through to the existing `parseConfig` (which currently rejects unknown flags). This deliberately mirrors common Unix CLI behaviour where `--version` is a stand-alone invocation.
- **A future executable is added to the repo**: it follows the same `CliBanner` + `withCli banner id` pattern. Documented in the per-exe spec only (no library change needed).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `cabal.project`'s `github-release-check` `source-repository-package` MUST be repinned to a `main` commit of `github-release-check` at or after `d901311` (the merge of `github-release-check#6`). Earlier pins fail dependency resolution because the `optparse` sublibrary was private before that commit.
- **FR-002**: The `cardano-tx-tools` library section in `cardano-tx-tools.cabal` MUST add `github-release-check:optparse` to its `build-depends`. (The per-exe `Cli` modules live under `src/` and import `versionOption` from the sublibrary; the library section is what bundles them.)
- **FR-003**: `app/tx-validate/Main.hs` MUST replace its `updateCheckConfig` + `withUpdateCheck` stanza with `withCli banner id <action>`, where `banner :: CliBanner` is a single record bundling `cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"`, `cliExe = "tx-validate"`, `cliVersion = version`, `cliOptOutEnvVar = "TX_VALIDATE_NO_UPDATE_CHECK"`.
- **FR-004**: `src/Cardano/Tx/Validate/Cli.hs::parseArgs` MUST take `CliBanner` instead of `Version`. Its hand-rolled `versionOption :: Version -> O.Parser (a -> a)` MUST be deleted and replaced by `import GitHub.Release.Check.OptParse (versionOption)`.
- **FR-005**: `app/tx-diff/Main.hs` MUST be wrapped in `withCli banner id <action>`, with `cliOptOutEnvVar = "TX_DIFF_NO_UPDATE_CHECK"`. `src/Cardano/Tx/Diff/Cli.hs`'s parser MUST adopt the sublibrary's `versionOption` (the same way tx-validate does).
- **FR-006**: `app/cardano-tx-generator/Main.hs` MUST be wrapped in `withCli banner id <action>`, with `cliOptOutEnvVar = "CARDANO_TX_GENERATOR_NO_UPDATE_CHECK"`. Because this executable has no `optparse-applicative` parser, `--version` is handled by an inline `case argv of ["--version"] -> putStrLn (cardano-tx-generator <semver>) >> exitSuccess; _ -> normal` short-circuit at the top of `main`, BEFORE `withCli` runs.
- **FR-007**: `app/tx-sign/Main.hs` MUST be wrapped in `withCli banner id <action>` (the executable's body is `runTxSign` from `src/Cardano/Tx/Sign/Cli.hs`, so the wrap happens at the `main` call site). `cliOptOutEnvVar = "TX_SIGN_NO_UPDATE_CHECK"`. `src/Cardano/Tx/Sign/Cli.hs`'s parser MUST adopt the sublibrary's `versionOption`.
- **FR-008**: For each of the four executables, `<exe> --version` MUST print exactly `<exe> <semver>` on a single line (no trailing whitespace, no extra lines) and exit with status `0`.
- **FR-009**: For each of the four executables, setting the documented opt-out env var MUST disable the update-check codepath (no `defaultConfig` cache write beyond what already exists from prior runs, no GitHub HTTP request, no banner on stderr).
- **FR-010**: The migration MUST NOT touch the runtime behaviour of any executable beyond the upgrade-banner + `--version` wiring. No new flags, no removed flags, no exit-code changes, no help-text rephrasing of pre-existing options.

### Key Entities

- **Per-exe `CliBanner` record**: a single value defined in each executable's `Main.hs` (working name `banner`), bundling the four fields `withCli` and `versionOption` both consume. The four values for the four exes differ in `cliExe` and `cliOptOutEnvVar`; `cliRepo` is identical (`RepoSlug "lambdasistemi" "cardano-tx-tools"`); `cliVersion` is identical (`Paths_cardano_tx_tools.version`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All four executables expose `--version` per FR-008 and the documented opt-out env var per FR-009. Measured by per-exe smoke checks in `./gate.sh`.
- **SC-002**: The migration is strictly additive at the public surface of the `cardano-tx-tools` library — every previously-exported identifier remains reachable. Measured by `nix flake check` passing.
- **SC-003**: A consumer rebuilding against the post-feature `cardano-tx-tools` does not pull in `github-release-check`'s sublibrary unless they themselves opt in (the `cardano-tx-tools` library transparently depends on it for its own per-exe `Cli` modules but does not re-export anything from it).
- **SC-004**: The merged PR contains exactly four behaviour-changing slices (one per executable), each a single bisect-safe commit; each closed task in `tasks.md` carries `[X] T### (commit: <sha>)`.

## Assumptions

- The upstream `github-release-check` post-merge `main` HEAD is `d901311` (the `chore: drop gate.sh` commit landing PR #6) or later — the `visibility: public` fix on the `optparse` sublibrary is required.
- The four executables share `Paths_cardano_tx_tools.version` (they're all in the same package). Verified.
- The user expressly authorised solo end-to-end resolve-ticket execution — no per-slice user gates within this PR (the orchestrator still reviews each subagent's commit before accepting).
- Downstream migration of consumers of `cardano-tx-tools`'s library API is OUT OF SCOPE — strictly additive guarantees that they need not change.
- This PR closes #28; #27 is already closed and superseded by #28.

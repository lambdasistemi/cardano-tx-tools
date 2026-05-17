---

description: "Tasks for feature 028-withcli-migration (issue #28)"
---

# Tasks: withCli + versionOption migration across four executables

**Input**: Design documents in `specs/028-withcli-migration/`
**Prerequisites**: [`spec.md`](./spec.md), [`plan.md`](./plan.md)
**Tests**: Not required (each slice's RED+GREEN is observable via the `./gate.sh` per-exe `--version` smoke; the parser modules' existing test suites cover the `CliBanner`-argument signature change at compile-and-unit-test time).

**Organization**: Tasks are grouped by [vertical commit slice](./plan.md#vertical-commit-slices) (S1–S5). Each slice corresponds to **one subagent run** producing **one bisect-safe commit**. RED + GREEN within a slice **fold into the same commit**.

After a slice ships, the orchestrator marks every task in the slice `[X] T### (commit: <short-sha>)` and amends the slice commit so the `tasks.md` change rides with the code (per resolve-ticket two-sided link rule). The recorded SHA is the slice's pre-amend SHA — the durable commit ↔ task identifier is the `Tasks:` trailer in the commit body.

---

## Phase 1: Setup

No setup tasks. The worktree, `gate.sh`, and draft PR #29 are already bootstrapped.

## Phase 2: Foundational

No foundational tasks separate from S1. The cabal/library-side wiring lands inside S1 (so the slice stays one commit).

---

## Phase 3: Slice S1 — tx-validate + pin bump + library wiring

**Goal**: Migrate `tx-validate` to `withCli` + sublibrary `versionOption`. Bundle the upstream-pin bump (so the sublibrary is available) and the `cardano-tx-tools` library's new dep on `github-release-check:optparse` (so per-exe `Cli` modules under `src/` can import the sublibrary).

**Subject**: `feat(tx-validate): adopt withCli + versionOption from github-release-check sublibrary`

### Tasks

- [ ] T001 [US1] [US2] BUMP — `cabal.project`: repin `source-repository-package` for `github-release-check` from the previous tag (`fd6e0a08...`) to `d90131112a4d6c048d1809adaffdefed92e8e841` (post-merge main HEAD of grc, including the `visibility: public` fix). Update `--sha256:` to `0ad6yi431w8h5i3x9x661b99frcgvd39gm4164y8cx1ihpsjixn3`.
- [ ] T002 [US1] [US2] LIBRARY WIRE — `cardano-tx-tools.cabal`: add `, github-release-check:optparse` to the main `library` section's `build-depends` (alphabetical position — after `github-release-check`).
- [ ] T003 [US1] [US2] RED — Extend `gate.sh` with the tx-validate `--version` smoke. Observe `./gate.sh` build the tx-validate executable; the tx-validate compile-step should FAIL because `parseArgs` is about to change signature (or, if you reorder T004 before T003, the build is clean but the gate fails differently). Capture the RED output.
- [ ] T004 [US1] [US2] GREEN — Rewrite `app/tx-validate/Main.hs`: define `banner :: CliBanner` (with `cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"`, `cliExe = "tx-validate"`, `cliVersion = version`, `cliOptOutEnvVar = "TX_VALIDATE_NO_UPDATE_CHECK"`); replace the `updateCheckConfig` + `withUpdateCheck` stanza with `withCli banner id <body>`; pass `banner` to `parseArgs` instead of `version`; drop the `Data.Maybe.isJust` and `System.Environment.lookupEnv` imports that become unused; drop the `updateCheckConfig` helper. Rewrite `src/Cardano/Tx/Validate/Cli.hs::parseArgs` to take `CliBanner` instead of `Version`; delete the hand-rolled `versionOption :: Version -> O.Parser (a -> a)`; `import GitHub.Release.Check.OptParse (versionOption)` and `import GitHub.Release.Check (CliBanner)`. Run `./gate.sh` end-to-end; it must exit 0.
- [ ] T005 [US1] [US2] FOLD — T001–T004 MUST land as ONE bisect-safe commit (one subagent run = one commit).

### Subagent brief — S1

```text
Task: T001, T002, T003, T004, T005 (slice S1)

Context:
- You are not alone in the codebase. Do not revert edits made by others.
  Slices S2, S3, S4 will be done by separate agents.
- Make exactly ONE commit. Do not push.
- Bisect-safe and vertical: at HEAD, ./gate.sh must exit 0; no WIP /
  draft / tmp / fixup / squash commits.
- Commit subject must match Conventional Commits exactly:
  `feat(tx-validate): adopt withCli + versionOption from github-release-check sublibrary`
- The commit body MUST end with the trailer:
  `Tasks: T001, T002, T003, T004, T005`
- Sign the commit with GPG (`git commit -S`). Do NOT use `--no-gpg-sign`.
- Maintain ./WIP.md in the worktree root (gitignored) as an append-only
  run log. Add a timestamped `## <ISO timestamp> — <milestone>` entry
  every time you achieve something:
    * brief received (task ids, owned files)
    * pin bump + library-wire applied + first build attempted
    * RED observed (gate.sh failing or compile failing — paste tail)
    * GREEN: Main rewritten / Cli rewritten / build & unit green
    * ./gate.sh run end-to-end (pass/fail + tail)
    * commit created (SHA + subject)
    * any blocking failure or scope question
  Do not delete earlier entries.

Owned files:
- cabal.project (pin + sha256 of the github-release-check source-repository-package only)
- cardano-tx-tools.cabal (main `library` section build-depends only — add the sublibrary; do NOT touch the per-exe `executable` sections in this slice)
- app/tx-validate/Main.hs (rewrite)
- src/Cardano/Tx/Validate/Cli.hs (rewrite — parseArgs signature change + versionOption swap)
- gate.sh (EXPLICITLY AUTHORIZED for this slice — append the tx-validate `--version` smoke at the bottom; do not modify existing lines)

Forbidden scope (do NOT touch):
- specs/ or .specify/
- README.md, CHANGELOG.md
- Any other gate.sh edit beyond appending the tx-validate smoke block
- app/{tx-diff,cardano-tx-generator,tx-sign}/Main.hs (later slices)
- src/Cardano/Tx/Diff/Cli.hs, src/Cardano/Tx/Sign/Cli.hs (later slices)
- cardano-tx-tools.cabal sections OTHER than the main `library`
- Any other source-repository-package in cabal.project
- Any .hs-boot file
- {-# LANGUAGE PackageImports #-} (not needed)

Required orchestrator analysis (do NOT re-derive):

1. Pin bump:
   - cabal.project currently has:
       source-repository-package
         type: git
         location: https://github.com/lambdasistemi/github-release-check
         tag: fd6e0a083756596d30396efa98e7c88dad151871
         --sha256: 1swmmwfg0q0kl1a74yzd4ibf5hn6k63s1rfggzqma6yn0llq4cgz
   - Replace with:
       tag: d90131112a4d6c048d1809adaffdefed92e8e841
       --sha256: 0ad6yi431w8h5i3x9x661b99frcgvd39gm4164y8cx1ihpsjixn3
   - Leave the surrounding comment block; only the tag and --sha256 lines change.

2. Library wire:
   - In cardano-tx-tools.cabal, in the main `library` section's `build-depends:`, add `, github-release-check:optparse` immediately after `, github-release-check` (alphabetical order). Do NOT add it to any executable section in this slice — slices S2/S3/S4 own those.

3. tx-validate Main.hs rewrite shape:
   ```haskell
   import GitHub.Release.Check
       ( CliBanner (..)
       , RepoSlug (..)
       , withCli
       )
   -- (Config, defaultConfig, withUpdateCheck imports GO AWAY)
   -- (Data.Maybe.isJust import GO AWAY)
   -- (System.Environment.lookupEnv import GO AWAY)
   -- (keep System.Environment.getArgs)

   main :: IO ()
   main = withCli banner id $ do
       argv <- getArgs
       options <- parseArgs banner argv   -- pass banner, not version
       txBytes <- readInput (txValidateCliInput options)
       tx <- decodeOrDie txBytes
       withSession options $ \session ->
           runValidation session tx options

   banner :: CliBanner
   banner =
       CliBanner
           { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
           , cliExe = "tx-validate"
           , cliVersion = version
           , cliOptOutEnvVar = "TX_VALIDATE_NO_UPDATE_CHECK"
           }
   ```
   The existing `updateCheckConfig` helper gets deleted entirely.

4. src/Cardano/Tx/Validate/Cli.hs rewrite shape (only the parser-module bits change):
   - Replace `import Data.Version (Version, showVersion)` with `import Data.Version ()` if no other Version uses remain, OR keep the unqualified `Version` if other identifiers still reference it (verify by grep — the hand-rolled `versionOption`'s deletion may make `showVersion` and `Version` unused inside this file). Add `import GitHub.Release.Check (CliBanner)` and `import GitHub.Release.Check.OptParse (versionOption)`. (Remove the import line entirely if all uses go away.)
   - Change the parseArgs signature:
     ```haskell
     parseArgs :: CliBanner -> [String] -> IO TxValidateCliOptions
     parseArgs banner argv =
         O.handleParseResult $
             O.execParserPure
                 O.defaultPrefs
                 ( O.info
                     (optionsParser O.<**> O.helper O.<**> versionOption banner)
                     (O.fullDesc <> O.progDesc usage)
                 )
                 argv
     ```
   - Delete the hand-rolled `versionOption :: Version -> O.Parser (a -> a)` helper entirely.
   - Update the haddock comment on parseArgs to describe the new signature (the executable supplies a CliBanner; --version is rendered by the sublibrary's versionOption).
   - Existing unit tests for Cardano.Tx.Validate.Cli.parseArgs WILL need their call sites updated from `parseArgs version argv` to `parseArgs banner argv`. Search test/ for parseArgs usages and fix them up; you may add a small `banner` helper at module scope for the test, mirroring the Main.hs banner but with arbitrary RepoSlug/exe name (test values are fine).

5. gate.sh smoke append (verbatim shape — adapt only if the existing gate.sh style demands minor tweaks):
   ```bash
   # tx-validate live-boundary smoke (slice S1)
   tx_validate_version="$(nix develop --quiet -c cabal run -v0 -O0 tx-validate -- --version)"
   tx_validate_first_line="$(printf '%s\n' "$tx_validate_version" | head -1)"
   printf '%s\n' "$tx_validate_first_line" \
       | grep -qE '^tx-validate [0-9]+(\.[0-9]+)*$' \
       || { echo "tx-validate --version smoke: first line mismatch: $tx_validate_first_line"; exit 1; }
   ```

6. Project conventions:
   - fourmolu 70-char line limit, leading commas/arrows (run `nix develop --quiet -c just format` and `just format-check`).
   - Haddock on all changed exports; module headers stay.
   - GHC2021 default-extensions inherited via the existing common stanza.
   - Use just recipes (`just build`, `just unit`); ./gate.sh is the canonical pre-push gate.

Suggested order of edits:

A. T001 + T002 first (pin bump + library wire), then `nix develop --quiet -c just build` to confirm the new pin resolves and the sublibrary is reachable from the library section. The build should pass at this point (tx-validate Main.hs is unchanged and still uses the OLD API, which is still exported by grc).

B. T003 RED: append the tx-validate smoke to gate.sh. Run `./gate.sh`. The smoke will fail at the `--version` step because the pre-rewrite tx-validate uses the hand-rolled versionOption (which DOES print "tx-validate <semver>" correctly, so this might actually pass…). If the smoke is green at this point, your RED is the test-suite compile failure you'll trigger in T004 step 1 — observe that and capture as RED.

   Better approach for clean RED: in step T004 stage the Cli.hs signature change FIRST (parseArgs takes CliBanner). Without the corresponding Main.hs rewrite, the compile fails. Capture that failure as RED, then complete Main.hs rewrite for GREEN.

C. T004 GREEN: rewrite Cli.hs + Main.hs in order. Run `./gate.sh` end-to-end; must exit 0.

D. T005 FOLD: stage every change, GPG-sign one commit.

Sanity checks before committing:

```
# 1. Pin SHA matches:
grep -A 3 'lambdasistemi/github-release-check' cabal.project | grep 'd90131112a4d6c048d1809adaffdefed92e8e841' && echo "OK: pin" || echo "BAD: pin"

# 2. Sublibrary in library section:
awk '/^library$/,/^[a-z]/ { print }' cardano-tx-tools.cabal | grep -E 'github-release-check:optparse' && echo "OK: lib dep" || echo "BAD: missing lib dep"

# 3. Old hand-rolled versionOption is gone:
grep -n 'versionOption :: Version' src/Cardano/Tx/Validate/Cli.hs && echo "BAD: hand-rolled versionOption survives" || echo "OK: hand-rolled deleted"

# 4. Main.hs uses withCli:
grep -n 'withCli banner id' app/tx-validate/Main.hs && echo "OK: withCli wired" || echo "BAD: withCli missing"

# 5. No PackageImports:
grep -RIn PackageImports app/tx-validate/ src/Cardano/Tx/Validate/ 2>&1 | grep -v 'Binary file' && echo "BAD: PackageImports" || echo "OK: no PackageImports"
```

All 5 must report OK.

Commit subject (use this EXACT title):
```
feat(tx-validate): adopt withCli + versionOption from github-release-check sublibrary
```

Suggested commit body shape:
```
Migrates tx-validate to the new github-release-check public API:

  - app/tx-validate/Main.hs: replaces the updateCheckConfig +
    withUpdateCheck stanza with `withCli banner id <action>`; introduces
    a CliBanner record bundling repo, exe, version, opt-out env-var.
  - src/Cardano/Tx/Validate/Cli.hs: parseArgs now takes CliBanner
    instead of Version; the hand-rolled versionOption is deleted and
    replaced by github-release-check:optparse's versionOption.

Also lands the cabal/library wiring needed by every per-exe slice in
this PR:

  - cabal.project: github-release-check pin bumped to d901311 (the
    post-merge main HEAD of github-release-check#6, including the
    `visibility: public` fix on the optparse sublibrary).
  - cardano-tx-tools.cabal: main library section gains
    `github-release-check:optparse` so the per-exe Cli modules in
    src/ can import versionOption.

gate.sh gains a tx-validate `--version` live-boundary smoke. The other
three executables' smokes follow in slices S2/S3/S4.

Tasks: T001, T002, T003, T004, T005
```

Report back (verbatim, each field):

1. Changed files (paths only). Confirm in writing: NO .hs-boot file added; NO PackageImports.
2. RED evidence: paste the failing build or gate.sh tail BEFORE the Main/Cli rewrite was complete.
3. GREEN evidence: tail of `just unit` after the rewrite; full tail of `./gate.sh` including the tx-validate smoke; exit code = 0.
4. Sanity-check output (all 5 of the OK / BAD checks above).
5. Commit short-sha + the literal `Tasks:` trailer line.
6. Residual risks or follow-ups.
7. Pointer to ./WIP.md (the orchestrator will tail and re-read it).

Do not run `git push`. Do not run `gh pr ready`. Do not edit anything outside the owned-files list.
```

**Checkpoint**: After S1 ships, the sublibrary is reachable from `src/`, tx-validate uses the new API, gate.sh has its first per-exe smoke. S2 can consume the sublibrary directly without re-wiring cabal.

---

## Phase 4: Slice S2 — tx-diff

**Goal**: Migrate `tx-diff` to `withCli` + sublibrary `versionOption`.

**Subject**: `feat(tx-diff): adopt withCli + versionOption from github-release-check sublibrary`

### Tasks

- [ ] T006 [US1] [US2] RED — Extend `gate.sh` with the tx-diff `--version` smoke (same shape as S1's tx-validate smoke). Run `./gate.sh`; the smoke FAILS because the pre-rewrite tx-diff has no `--version` flag. Capture the RED output.
- [ ] T007 [US1] [US2] GREEN — Add `, github-release-check` and `, github-release-check:optparse` to the tx-diff executable section's `build-depends` in `cardano-tx-tools.cabal` (only if not already present — check first). Rewrite `app/tx-diff/Main.hs` to define `banner :: CliBanner` (`cliExe = "tx-diff"`, `cliOptOutEnvVar = "TX_DIFF_NO_UPDATE_CHECK"`, other fields shared) and wrap `main`'s body in `withCli banner id`. Pass `banner` to whatever tx-diff's `parseArgs` (in `src/Cardano/Tx/Diff/Cli.hs`) is called as. Rewrite `src/Cardano/Tx/Diff/Cli.hs`'s `parseArgs` to take `CliBanner` instead of `Version` (mirroring tx-validate's S1 shape), import `versionOption` from the sublibrary, plumb it into the parser via `<**>`. Run `./gate.sh`; must exit 0.
- [ ] T008 [US1] [US2] FOLD — T006 + T007 MUST land as ONE bisect-safe commit.

### Subagent brief — S2

```text
Task: T006, T007, T008 (slice S2)

Context:
- Slice S1 is ALREADY MERGED. CliBanner is in GitHub.Release.Check; versionOption is in GitHub.Release.Check.OptParse (sublibrary github-release-check:optparse). The pin is already at github-release-check d901311. The cardano-tx-tools library section already depends on the sublibrary.
- Make exactly ONE commit. Do not push.
- Bisect-safe and vertical.
- Commit subject EXACTLY:
  `feat(tx-diff): adopt withCli + versionOption from github-release-check sublibrary`
- Commit body MUST end with trailer: `Tasks: T006, T007, T008`
- GPG-signed (`git commit -S`).
- Maintain ./WIP.md per the same protocol as S1.

Owned files:
- app/tx-diff/Main.hs (rewrite)
- src/Cardano/Tx/Diff/Cli.hs (rewrite — parseArgs signature change + versionOption import)
- cardano-tx-tools.cabal (tx-diff executable section build-depends only; add github-release-check + github-release-check:optparse if missing)
- gate.sh (EXPLICITLY AUTHORIZED — append the tx-diff `--version` smoke; do not modify other lines)

Forbidden scope:
- Anything under specs/, .specify/
- README.md, CHANGELOG.md
- Other gate.sh lines beyond the tx-diff append
- app/{tx-validate,cardano-tx-generator,tx-sign}/Main.hs
- src/Cardano/Tx/{Validate,Sign}/Cli.hs
- cabal.project (pin already bumped in S1; don't touch)
- The main `library` section of cardano-tx-tools.cabal (already wired in S1)
- .hs-boot, PackageImports

Required orchestrator analysis:

1. tx-diff Main.hs rewrite — read the existing app/tx-diff/Main.hs first to see its current parseArgs invocation. The shape after rewrite is:
   ```haskell
   import GitHub.Release.Check (CliBanner (..), RepoSlug (..), withCli)
   ...
   main :: IO ()
   main = withCli banner id $ do
       <existing body verbatim, except `parseArgs version` becomes `parseArgs banner`>

   banner :: CliBanner
   banner = CliBanner
       { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
       , cliExe = "tx-diff"
       , cliVersion = version
       , cliOptOutEnvVar = "TX_DIFF_NO_UPDATE_CHECK"
       }
   ```
   If tx-diff currently does NOT take a Version into its parseArgs (it might not — verify by reading src/Cardano/Tx/Diff/Cli.hs first), you still pass `banner` and update parseArgs to accept it. The sublibrary's versionOption is the rationale for needing the banner inside parseArgs at all.

2. src/Cardano/Tx/Diff/Cli.hs rewrite — same pattern as tx-validate's S1:
   ```haskell
   import GitHub.Release.Check (CliBanner)
   import GitHub.Release.Check.OptParse (versionOption)
   ...
   parseArgs :: CliBanner -> [String] -> IO TxDiffCliOptions   -- or whatever tx-diff's option-record type is
   parseArgs banner argv =
       O.handleParseResult $
           O.execParserPure
               O.defaultPrefs
               ( O.info
                   (optionsParser O.<**> O.helper O.<**> versionOption banner)
                   (O.fullDesc <> O.progDesc usage)
               )
               argv
   ```
   If tx-diff does NOT currently have a `versionOption` of its own, just add `versionOption banner` into the parser chain (plumb via `<**>`). If it has one, delete it.

3. Cabal — read the existing `executable tx-diff` section of cardano-tx-tools.cabal. If `, github-release-check` and `, github-release-check:optparse` are not already in its build-depends, add them in alphabetical position.

4. gate.sh append (mirror S1's tx-validate smoke, with tx-diff names):
   ```bash
   # tx-diff live-boundary smoke (slice S2)
   tx_diff_version="$(nix develop --quiet -c cabal run -v0 -O0 tx-diff -- --version)"
   tx_diff_first_line="$(printf '%s\n' "$tx_diff_version" | head -1)"
   printf '%s\n' "$tx_diff_first_line" \
       | grep -qE '^tx-diff [0-9]+(\.[0-9]+)*$' \
       || { echo "tx-diff --version smoke: first line mismatch: $tx_diff_first_line"; exit 1; }
   ```

5. Conventions: same as S1 — fourmolu 70-char, leading commas, haddock, GPG-sign, use just recipes, ./gate.sh end-to-end before commit.

Sanity checks before committing:

```
# 1. Build deps for tx-diff:
awk '/^executable tx-diff$/,/^[a-z]/' cardano-tx-tools.cabal | grep -E 'github-release-check:optparse' && echo "OK: tx-diff dep" || echo "BAD: missing"
# 2. Main wired:
grep -n 'withCli banner id' app/tx-diff/Main.hs && echo "OK: withCli" || echo "BAD"
# 3. gate.sh smoke present:
grep -c 'tx-diff --version smoke' gate.sh
# 4. No hs-boot / PackageImports:
find . -name '*.hs-boot' -not -path './dist-newstyle/*' | grep -v '^$' && echo "BAD: hs-boot" || echo "OK"
grep -RIn PackageImports app/tx-diff/ src/Cardano/Tx/Diff/ 2>/dev/null | grep -v dist-newstyle && echo "BAD" || echo "OK"
```

Commit subject (EXACT):
```
feat(tx-diff): adopt withCli + versionOption from github-release-check sublibrary
```

Suggested body:
```
Migrates tx-diff to the new github-release-check public API. Adds the
upgrade-banner-on-exit behaviour the family of tx-* CLIs share, plus a
--version flag printing `tx-diff <semver>` via the sublibrary's
versionOption helper.

  - app/tx-diff/Main.hs: wraps main in withCli banner id; banner uses
    cliOptOutEnvVar = "TX_DIFF_NO_UPDATE_CHECK".
  - src/Cardano/Tx/Diff/Cli.hs: parseArgs takes CliBanner, plumbs
    versionOption from github-release-check:optparse.
  - cardano-tx-tools.cabal: tx-diff executable build-depends gains
    github-release-check and github-release-check:optparse.
  - gate.sh: appends a tx-diff `--version` live-boundary smoke
    mirroring slice S1's tx-validate smoke.

Tasks: T006, T007, T008
```

Report back: same six fields as S1 (changed files, RED evidence, GREEN evidence, sanity checks, commit SHA + trailer, residual risks, ./WIP.md pointer).

Do NOT push, do NOT mark PR ready, do NOT touch out-of-scope files.
```

**Checkpoint**: After S2, two of four executables uniformly expose `--version` and wrap `main` in `withCli`.

---

## Phase 5: Slice S3 — cardano-tx-generator

**Goal**: Migrate `cardano-tx-generator` to `withCli`; handle `--version` via an inline argv short-circuit (this exe has no `optparse-applicative` parser).

**Subject**: `feat(cardano-tx-generator): adopt withCli; inline --version short-circuit`

### Tasks

- [ ] T009 [US1] [US2] RED — Extend `gate.sh` with the cardano-tx-generator `--version` smoke. Run `./gate.sh`; the smoke FAILS because pre-rewrite cardano-tx-generator does not handle `--version` (its hand-rolled `parseConfig` rejects unknown flags).
- [ ] T010 [US1] [US2] GREEN — Add `, github-release-check` to the cardano-tx-generator executable section's `build-depends` in `cardano-tx-tools.cabal` (no sublibrary — this exe doesn't use the sublibrary's versionOption). Rewrite `app/cardano-tx-generator/Main.hs`: add a short-circuit `case argv of ["--version"] -> putStrLn (showVersion banner) >> exitSuccess; _ -> normal` at the very top of `main` (BEFORE the existing `parseConfig` call); wrap the rest of main's body in `withCli banner id`; define `banner :: CliBanner` (`cliExe = "cardano-tx-generator"`, `cliOptOutEnvVar = "CARDANO_TX_GENERATOR_NO_UPDATE_CHECK"`). The existing `parseConfig`, `runDaemon`, and ancillary helpers stay untouched. Run `./gate.sh`; must exit 0.
- [ ] T011 [US1] [US2] FOLD — T009 + T010 MUST land as ONE bisect-safe commit.

### Subagent brief — S3

```text
Task: T009, T010, T011 (slice S3)

Context:
- Slices S1 and S2 are ALREADY MERGED. CliBanner is reachable from GitHub.Release.Check.
- Make exactly ONE commit. Do not push. Bisect-safe and vertical.
- Commit subject EXACTLY:
  `feat(cardano-tx-generator): adopt withCli; inline --version short-circuit`
- Commit body MUST end with trailer: `Tasks: T009, T010, T011`
- GPG-signed.
- Maintain ./WIP.md per the same protocol.

Owned files:
- app/cardano-tx-generator/Main.hs (rewrite)
- cardano-tx-tools.cabal (cardano-tx-generator executable section build-depends only — add github-release-check; do NOT add the sublibrary, cardano-tx-generator doesn't use it)
- gate.sh (EXPLICITLY AUTHORIZED — append cardano-tx-generator `--version` smoke)

Forbidden scope:
- specs/, .specify/, README, CHANGELOG
- Other gate.sh lines beyond the append
- app/{tx-validate,tx-diff,tx-sign}/Main.hs
- src/Cardano/Tx/{Validate,Diff,Sign}/Cli.hs
- src/Cardano/Tx/Generator/* (the daemon module — do NOT touch its parsing or runDaemon)
- The main `library` section of cardano-tx-tools.cabal
- cabal.project
- .hs-boot, PackageImports
- Migrating cardano-tx-generator to optparse-applicative (out of scope; the inline short-circuit is the agreed approach per spec.md Clarifications session)

Required orchestrator analysis:

1. cardano-tx-generator Main.hs rewrite shape:
   ```haskell
   module Main (main) where

   import Data.Version (showVersion)
   import System.Environment (getArgs)
   import System.Exit (exitSuccess)
   ... <existing imports preserved> ...

   import GitHub.Release.Check (CliBanner (..), RepoSlug (..), withCli)
   import Paths_cardano_tx_tools (version)

   banner :: CliBanner
   banner = CliBanner
       { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
       , cliExe = "cardano-tx-generator"
       , cliVersion = version
       , cliOptOutEnvVar = "CARDANO_TX_GENERATOR_NO_UPDATE_CHECK"
       }

   main :: IO ()
   main = do
       args <- getArgs
       case args of
           ["--version"] -> do
               putStrLn $ "cardano-tx-generator " <> showVersion version
               exitSuccess
           _ -> withCli banner id $ do
               cfg <- parseConfig args
               hPutStrLn stderr $ "cardano-tx-generator: " <> show cfg
               runDaemon cfg
   ```
   Notes:
   - The existing `main` body (lines from `args <- getArgs` through `runDaemon cfg`) is preserved verbatim inside the `withCli banner id` block of the `_ ->` arm.
   - The pre-existing `Paths_cardano_tx_tools (version)` import likely already exists; if not, add it. (Read the cabal section's `autogen-modules` / `other-modules` — they should already declare `Paths_cardano_tx_tools`; if they don't, add it as you would for any executable that needs the Paths module.)
   - DO NOT touch parseConfig, takeFlag, requireFlag, dieUsage, or any of the hand-rolled parsing helpers.

2. Cabal: in `executable cardano-tx-generator`'s `build-depends`, add `, github-release-check` (alphabetical position). Do NOT add `github-release-check:optparse` — cardano-tx-generator does not use the sublibrary. Also add `Paths_cardano_tx_tools` to the section's `autogen-modules` and `other-modules` if not already present.

3. gate.sh append:
   ```bash
   # cardano-tx-generator live-boundary smoke (slice S3)
   ctxg_version="$(nix develop --quiet -c cabal run -v0 -O0 cardano-tx-generator -- --version)"
   ctxg_first_line="$(printf '%s\n' "$ctxg_version" | head -1)"
   printf '%s\n' "$ctxg_first_line" \
       | grep -qE '^cardano-tx-generator [0-9]+(\.[0-9]+)*$' \
       || { echo "cardano-tx-generator --version smoke: first line mismatch: $ctxg_first_line"; exit 1; }
   ```

4. Conventions: same as prior slices.

Sanity checks:

```
# 1. Dep added:
awk '/^executable cardano-tx-generator$/,/^[a-z]/' cardano-tx-tools.cabal | grep -E ', github-release-check$' && echo "OK: dep" || echo "BAD"
awk '/^executable cardano-tx-generator$/,/^[a-z]/' cardano-tx-tools.cabal | grep -E 'github-release-check:optparse' && echo "BAD: sublibrary should NOT be here" || echo "OK: no sublibrary"
# 2. Inline version handler present:
grep -n 'cardano-tx-generator " <> showVersion' app/cardano-tx-generator/Main.hs && echo "OK: inline version" || echo "BAD"
# 3. withCli present:
grep -n 'withCli banner id' app/cardano-tx-generator/Main.hs && echo "OK: withCli" || echo "BAD"
# 4. gate.sh smoke:
grep -c 'cardano-tx-generator --version smoke' gate.sh
# 5. parseConfig untouched:
git diff src/Cardano/Tx/Generator/Daemon.hs 2>/dev/null | head -1 && echo "BAD: daemon touched" || echo "OK: daemon untouched"
```

Commit subject (EXACT):
```
feat(cardano-tx-generator): adopt withCli; inline --version short-circuit
```

Suggested body:
```
Migrates cardano-tx-generator to the new github-release-check
withCli wrapper. Because this executable uses hand-rolled
arg parsing (no optparse-applicative parser), --version is
handled by an inline `case argv of ["--version"] -> ...`
short-circuit at the top of main, BEFORE withCli runs.

  - app/cardano-tx-generator/Main.hs: pre-parses --version inline;
    wraps the rest of main in withCli banner id; banner uses
    cliOptOutEnvVar = "CARDANO_TX_GENERATOR_NO_UPDATE_CHECK".
  - cardano-tx-tools.cabal: cardano-tx-generator executable
    build-depends gains github-release-check (no sublibrary —
    this exe doesn't use github-release-check:optparse).
  - gate.sh: cardano-tx-generator --version live-boundary smoke.

The existing parseConfig / takeFlag / requireFlag / dieUsage helpers
and the runDaemon entry point are untouched. Migrating
cardano-tx-generator to optparse-applicative is out of scope
(rationale in specs/028-withcli-migration/spec.md Clarifications).

Tasks: T009, T010, T011
```

Report back: same six fields as prior slices.
```

**Checkpoint**: After S3, three of four executables are migrated. Only `tx-sign` remains.

---

## Phase 6: Slice S4 — tx-sign

**Goal**: Migrate `tx-sign` to `withCli` + sublibrary `versionOption`. tx-sign's `Main.hs` is a single-line wrapper (`main = runTxSign`); the migration happens in `src/Cardano/Tx/Sign/Cli.hs::runTxSign` plus the Main banner wiring.

**Subject**: `feat(tx-sign): adopt withCli + versionOption from github-release-check sublibrary`

### Tasks

- [ ] T012 [US1] [US2] RED — Extend `gate.sh` with the tx-sign `--version` smoke. Run `./gate.sh`; the smoke FAILS because pre-rewrite tx-sign has no `--version` flag.
- [ ] T013 [US1] [US2] GREEN — Add `, github-release-check` and `, github-release-check:optparse` to the tx-sign executable section's `build-depends` in `cardano-tx-tools.cabal` (only if not already present). Rewrite `app/tx-sign/Main.hs` to define `banner :: CliBanner` (`cliExe = "tx-sign"`, `cliOptOutEnvVar = "TX_SIGN_NO_UPDATE_CHECK"`), import `withCli`, and call `withCli banner id (runTxSign banner)` (or, if `runTxSign` doesn't currently take a banner, change its signature to do so). Rewrite `src/Cardano/Tx/Sign/Cli.hs::runTxSign` to take a `CliBanner` argument and pass it to its `parseArgs` invocation; change `parseArgs` (or whatever the local function is called) to take `CliBanner`, import the sublibrary's `versionOption`, plumb it via `<**>`, delete any hand-rolled versionOption. Run `./gate.sh`; must exit 0.
- [ ] T014 [US1] [US2] FOLD — T012 + T013 MUST land as ONE bisect-safe commit.

### Subagent brief — S4

```text
Task: T012, T013, T014 (slice S4)

Context:
- Slices S1, S2, S3 are ALREADY MERGED. CliBanner reachable from
  GitHub.Release.Check; versionOption from
  GitHub.Release.Check.OptParse; cardano-tx-tools library section
  already depends on the sublibrary.
- Make exactly ONE commit. Do not push. Bisect-safe and vertical.
- Commit subject EXACTLY:
  `feat(tx-sign): adopt withCli + versionOption from github-release-check sublibrary`
- Commit body MUST end with trailer: `Tasks: T012, T013, T014`
- GPG-signed. ./WIP.md per the protocol.

Owned files:
- app/tx-sign/Main.hs (rewrite — currently a one-line `main = runTxSign` wrapper; will add banner definition and `withCli`)
- src/Cardano/Tx/Sign/Cli.hs (rewrite — runTxSign / parseArgs take CliBanner, versionOption swapped)
- cardano-tx-tools.cabal (tx-sign executable section build-depends only)
- gate.sh (EXPLICITLY AUTHORIZED — append tx-sign `--version` smoke)

Forbidden scope:
- specs/, .specify/, README, CHANGELOG
- Other gate.sh lines
- app/{tx-validate,tx-diff,cardano-tx-generator}/Main.hs
- src/Cardano/Tx/{Validate,Diff}/Cli.hs
- The main `library` section of cardano-tx-tools.cabal
- cabal.project
- src/Cardano/Tx/Sign/ files OTHER than Cli.hs (don't touch Witness, Vault, etc.)
- .hs-boot, PackageImports

Required orchestrator analysis:

1. Read src/Cardano/Tx/Sign/Cli.hs first to understand the current shape of `runTxSign`. It currently has signature `runTxSign :: IO ()` (or similar). After the rewrite, take `CliBanner` and propagate it to whatever internal parseArgs uses Version today.

2. tx-sign Main.hs after rewrite:
   ```haskell
   module Main (main) where

   import GitHub.Release.Check (CliBanner (..), RepoSlug (..), withCli)
   import Paths_cardano_tx_tools (version)

   import Cardano.Tx.Sign.Cli (runTxSign)

   banner :: CliBanner
   banner = CliBanner
       { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
       , cliExe = "tx-sign"
       , cliVersion = version
       , cliOptOutEnvVar = "TX_SIGN_NO_UPDATE_CHECK"
       }

   main :: IO ()
   main = withCli banner id (runTxSign banner)
   ```

3. src/Cardano/Tx/Sign/Cli.hs:
   - Add `import GitHub.Release.Check (CliBanner)` and `import GitHub.Release.Check.OptParse (versionOption)`.
   - Change `runTxSign :: IO ()` to `runTxSign :: CliBanner -> IO ()` (or whatever propagation chain is needed to reach the parseArgs call). Update any tests that called the old signature.
   - In the parser builder, plumb `versionOption banner` via `<**>`. If there's a pre-existing hand-rolled versionOption, delete it.

4. Cabal: add `, github-release-check` and `, github-release-check:optparse` to the tx-sign executable section's build-depends if not present.

5. gate.sh append:
   ```bash
   # tx-sign live-boundary smoke (slice S4)
   tx_sign_version="$(nix develop --quiet -c cabal run -v0 -O0 tx-sign -- --version)"
   tx_sign_first_line="$(printf '%s\n' "$tx_sign_version" | head -1)"
   printf '%s\n' "$tx_sign_first_line" \
       | grep -qE '^tx-sign [0-9]+(\.[0-9]+)*$' \
       || { echo "tx-sign --version smoke: first line mismatch: $tx_sign_first_line"; exit 1; }
   ```

6. Conventions: same as prior slices.

Sanity checks:

```
# 1. tx-sign exe deps:
awk '/^executable tx-sign$/,/^[a-z]/' cardano-tx-tools.cabal | grep -E 'github-release-check:optparse' && echo "OK" || echo "BAD"
# 2. Main has withCli:
grep -n 'withCli banner id' app/tx-sign/Main.hs && echo "OK" || echo "BAD"
# 3. runTxSign takes CliBanner:
grep -n 'runTxSign :: CliBanner' src/Cardano/Tx/Sign/Cli.hs && echo "OK" || echo "BAD"
# 4. gate.sh smoke:
grep -c 'tx-sign --version smoke' gate.sh
# 5. no PackageImports / hs-boot:
find . -name '*.hs-boot' -not -path './dist-newstyle/*' | head -1 && echo "BAD" || echo "OK"
```

Commit subject (EXACT):
```
feat(tx-sign): adopt withCli + versionOption from github-release-check sublibrary
```

Body:
```
Migrates tx-sign to the new github-release-check public API. tx-sign's
Main.hs is now a banner+withCli wrapper around runTxSign, which takes
the CliBanner so the sublibrary's versionOption can be plumbed into
its optparse-applicative parser.

  - app/tx-sign/Main.hs: defines banner and calls withCli banner id
    (runTxSign banner). cliOptOutEnvVar = "TX_SIGN_NO_UPDATE_CHECK".
  - src/Cardano/Tx/Sign/Cli.hs: runTxSign takes CliBanner; its parser
    chain plumbs github-release-check:optparse's versionOption via
    <**>; any hand-rolled versionOption is removed.
  - cardano-tx-tools.cabal: tx-sign executable build-depends gains
    github-release-check and github-release-check:optparse.
  - gate.sh: tx-sign --version live-boundary smoke.

Tasks: T012, T013, T014
```

Report back: same six fields.
```

**Checkpoint**: After S4, all four executables are migrated. `tasks.md` should be fully `[X]`'d except for the S5 self-reference tasks.

---

## Phase 7: Slice S5 — Polish & Finalization (orchestrator)

**Goal**: Finalization audit passes; `gate.sh` is dropped in the final commit so the PR can move to ready.

**Owner**: orchestrator (chore only).

### Tasks

- [ ] T015 ORCHESTRATOR-OWNED, finalization audit — Run the `finalization_audit 29` helper from the `gate-script` skill. Verify every prior commit passes `commit_gate`; every behaviour-changing commit carries `Tasks:`; every closed task in `tasks.md` carries `[X] T### (commit: <sha>)`; `./gate.sh` green at HEAD; README/repo metadata aligned with delivered behaviour; PR body current.
- [ ] T016 ORCHESTRATOR-OWNED, chore only — `git rm gate.sh && git commit -S -m "chore: drop gate.sh (ready for review)"`. Push. Wait for CI green. `gh pr ready 29`.

**Checkpoint**: After S5, PR #29 is ready for external review (the user). On merge, run post-merge cleanup per the `worktrees` skill ("Post-Merge Cleanup"): remove worktree `/code/cardano-tx-tools-28`, delete local + remote `28-withcli-migration` branch, prune.

---

## Dependencies

```text
S1 ──▶ S2 ──▶ S3 ──▶ S4 ──▶ S5
```

S2/S3/S4 strictly depend on S1 (pin bump + library wire). S2/S3/S4 are conceptually parallelisable but resolve-ticket runs one subagent at a time, so we proceed serially.

## Parallel Execution

None within a slice (intra-slice tasks fold into one commit). No parallel cross-slice agents.

## Implementation Strategy

**MVP scope**: S1 alone is the MVP. After S1, the family-level uniformity story for tx-validate is realised AND the cabal wiring is set up so subsequent slices are minimal. S2/S3/S4 each add one more executable to the uniform family. S5 closes the PR.

**One subagent at a time**: dispatch one slice's subagent, tail `./WIP.md` live during the run, review the returned commit (run `./gate.sh` locally + `commit_gate <sha>`), mark `tasks.md`, amend the slice commit so the marks ride with the code, push, then dispatch the next slice.

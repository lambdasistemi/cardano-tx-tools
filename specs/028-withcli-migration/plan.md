# Implementation Plan: withCli + versionOption migration across four executables

**Branch**: `28-withcli-migration` | **Date**: 2026-05-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/028-withcli-migration/spec.md`

## Summary

Migrate the four shipped CLIs (`tx-validate`, `tx-diff`, `cardano-tx-generator`, `tx-sign`) to the new `github-release-check` public API. Each executable ends up calling `withCli banner id <action>` instead of any `defaultConfig` + `withUpdateCheck` stanza, with a single `CliBanner` record (`cliRepo`, `cliExe`, `cliVersion`, `cliOptOutEnvVar`) bundling the four values. Three of the four (`tx-validate`, `tx-diff`, `tx-sign`) also adopt the new `github-release-check:optparse` sublibrary's `versionOption` in their `Cli` modules. `cardano-tx-generator` does not — it uses hand-rolled arg parsing, so `--version` is handled inline at the top of `main` before `withCli` runs.

The first slice (tx-validate) also bumps `cabal.project`'s `github-release-check` pin to the post-merge `main` tip (`d901311` or later — required for the sublibrary's `visibility: public` fix) and adds `github-release-check:optparse` to the `cardano-tx-tools` library's `build-depends` (the per-exe `Cli` modules live under `src/` and import from the sublibrary).

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (existing pin)
**Primary Dependencies**: `optparse-applicative` (already direct dep), `github-release-check` (already direct dep — pin bumped), `github-release-check:optparse` (new direct dep, in the main library section)
**Storage**: caller-supplied on-disk cache via `defaultConfig` (untouched)
**Testing**: existing `unit-tests` test-suite (no new tests in this PR — existing parser-module tests cover the `CliBanner` argument change; the live-boundary smoke per executable is in `gate.sh`)
**Target Platform**: Linux/Darwin via `haskell.nix`
**Project Type**: Haskell library + four shipped executables
**Performance Goals**: N/A (sugar over an existing wrapper)
**Constraints**: strictly additive at the public surface; the four executables' user-facing behaviour is unchanged beyond `--version` and the upgrade-banner wiring
**Scale/Scope**: ~4 executables × ~5–15 LOC each, plus ~5 LOC in cabal/cabal.project. Net diff probably <100 LOC.

## Constitution Check

The project's `.specify/memory/constitution.md` carries operational constraints (already noted in `CLAUDE.md`: Haskell 9.12.3 via haskell.nix). The migration honours those — no language/version change, no new direct dep beyond the already-merged `github-release-check:optparse` sublibrary, no flake.nix edits. Standing project rules from `/code/llm-settings/claude/rules/haskell.md` (70-char fourmolu, leading commas, haddock on exports, just-recipes, GPG-signed commits) apply.

No exceptions tracked.

## Project Structure

### Documentation (this feature)

```text
specs/028-withcli-migration/
|-- plan.md           # this file
|-- spec.md           # P1/P2 user stories, FR-001..FR-010 (already authored)
`-- tasks.md          # per-slice subagent briefs (next)
```

(No `research.md` / `data-model.md` / `contracts/` for this PR — the entities and API contracts come from `github-release-check`'s contracts/public-api.md; we are only consuming them.)

### Source Code (repository root)

```text
cabal.project                                # ← bump github-release-check pin (slice 1)
cardano-tx-tools.cabal                       # ← library build-depends gains
                                             #   `github-release-check:optparse` (slice 1)
app/
  tx-validate/Main.hs                        # ← slice 1 rewrite
  tx-diff/Main.hs                            # ← slice 2 rewrite
  cardano-tx-generator/Main.hs               # ← slice 3 rewrite
  tx-sign/Main.hs                            # ← slice 4 wrap
src/
  Cardano/
    Tx/
      Validate/Cli.hs                        # ← slice 1: parseArgs takes CliBanner
      Diff/Cli.hs                            # ← slice 2: parseArgs takes CliBanner
      Sign/Cli.hs                            # ← slice 4: parseArgs takes CliBanner
gate.sh                                      # extended per slice; dropped in final commit
```

**Structure Decision**: stay with the existing single-library-plus-four-executables layout. Each executable's `Main.hs` is rewritten in-place. Three of the four have a corresponding `Cli.hs` parser module under `src/` that is also rewritten (`parseArgs` takes `CliBanner` instead of `Version`; hand-rolled `versionOption` deleted and replaced by `import GitHub.Release.Check.OptParse (versionOption)`). `cardano-tx-generator` has no parser module — its arg parsing is inline in `Main.hs` and stays that way.

## Orchestrator vs Subagent Ownership

| Asset | Owner |
|---|---|
| `spec.md`, `plan.md`, `tasks.md` (this feature dir) | **Orchestrator** |
| `gate.sh` (initial commit; per-slice extension via subagent in their owned slice; final drop) | **Orchestrator** initial + final; **subagent per-slice extension** (explicit authorisation in each brief, mirroring grc#6 slice S3) |
| `cabal.project` pin bump | **Subagent (slice 1)** — atomic with the first per-exe migration |
| `cardano-tx-tools.cabal` library-section `build-depends` edit | **Subagent (slice 1)** — same reason |
| `cardano-tx-tools.cabal` per-exe `build-depends` edits | **Subagent** of the owning slice |
| `app/<exe>/Main.hs` per executable | **Subagent** of the owning slice |
| `src/Cardano/Tx/<Exe>/Cli.hs` per executable | **Subagent** of the owning slice |
| PR body, issue closing, post-merge cleanup | **Orchestrator** |

## Vertical Commit Slices

Four slices, in dependency order. Each = one subagent run = one bisect-safe commit. The first slice bundles the cabal/library-side wiring with tx-validate's migration so all subsequent slices can just consume the sublibrary directly.

### S1 — tx-validate + pin bump + library wiring

**Subject**: `feat(tx-validate): adopt withCli + versionOption from github-release-check sublibrary`
**Files**: `cabal.project`, `cardano-tx-tools.cabal` (library section build-depends), `app/tx-validate/Main.hs`, `src/Cardano/Tx/Validate/Cli.hs`, `gate.sh` (extend with tx-validate `--version` smoke).
**Smoke added**: `cabal run -v0 -O0 tx-validate -- --version` (assert exit 0, first stdout line equals `tx-validate <semver>`).
**Live-boundary diagnostic**: yes — the executable's `--version` and `withCli`-wrapped path can only be proved by running the built binary. Unit tests over `Cardano.Tx.Validate.Cli` will exercise the `CliBanner`-argument change at the parser level but cannot confirm the executable's argv handling. **gate.sh smoke covers this.**

### S2 — tx-diff

**Subject**: `feat(tx-diff): adopt withCli + versionOption from github-release-check sublibrary`
**Files**: `cardano-tx-tools.cabal` (tx-diff exe build-depends), `app/tx-diff/Main.hs`, `src/Cardano/Tx/Diff/Cli.hs`, `gate.sh` (extend with tx-diff `--version` smoke).
**Smoke added**: `cabal run -v0 -O0 tx-diff -- --version` (same shape as S1's).
**Live-boundary diagnostic**: yes — same reason as S1. **Per-exe gate.sh smoke covers it.**

### S3 — cardano-tx-generator

**Subject**: `feat(cardano-tx-generator): adopt withCli; inline --version short-circuit`
**Files**: `cardano-tx-tools.cabal` (cardano-tx-generator exe build-depends), `app/cardano-tx-generator/Main.hs`, `gate.sh` (extend with cardano-tx-generator `--version` smoke).
**Smoke added**: `cabal run -v0 -O0 cardano-tx-generator -- --version` (same shape).
**Live-boundary diagnostic**: yes — same reason. **Per-exe gate.sh smoke covers it.**
**Note**: this slice does NOT touch any `Cli.hs` parser module (cardano-tx-generator has none). The inline `--version` short-circuit (FR-006) is the entire shape of this slice's parser change.

### S4 — tx-sign

**Subject**: `feat(tx-sign): adopt withCli + versionOption from github-release-check sublibrary`
**Files**: `cardano-tx-tools.cabal` (tx-sign exe build-depends), `app/tx-sign/Main.hs`, `src/Cardano/Tx/Sign/Cli.hs`, `gate.sh` (extend with tx-sign `--version` smoke).
**Smoke added**: `cabal run -v0 -O0 tx-sign -- --version` (same shape).
**Live-boundary diagnostic**: yes — same reason. **Per-exe gate.sh smoke covers it.**

### S5 — drop gate.sh (orchestrator chore)

**Subject**: `chore: drop gate.sh (ready for review)`
**Owner**: orchestrator.

## Proof Strategy

| Slice | RED (failing before impl) | GREEN (passing after) |
|---|---|---|
| S1 | gate.sh tx-validate `--version` smoke added before the rewrite; fails on the pre-rewrite tx-validate (hand-rolled versionOption inside parseArgs already prints the right line, BUT the parseArgs signature change from `Version` to `CliBanner` will cause compile-fail on `Main.hs` until the rewrite). RED = build failure. | Rewrite tx-validate Main + Cli, gate green end-to-end including the smoke. |
| S2 | gate.sh tx-diff `--version` smoke added; tx-diff currently has no `--version` flag at all, so the smoke FAILS with the pre-rewrite tx-diff. | Rewrite tx-diff Main + Cli, gate green including the new tx-diff smoke. |
| S3 | gate.sh cardano-tx-generator `--version` smoke added; pre-rewrite cardano-tx-generator does not handle `--version` (falls through to parseConfig which rejects unknown flags), so the smoke FAILS. | Rewrite cardano-tx-generator Main with inline `--version` short-circuit + `withCli banner id <existing-body>`, gate green. |
| S4 | gate.sh tx-sign `--version` smoke added; pre-rewrite tx-sign has no `--version` flag, smoke FAILS. | Rewrite tx-sign Main + Cli (via `runTxSign`), gate green. |
| S5 | N/A | gate.sh removed; PR moves to ready. |

## Live-boundary Diagnostic Summary

For every slice the answer to *"What system boundary does this exercise that the unit suite cannot?"* is: the built executable's actual argv → exit-code → stdout pipeline plus the `withCli` wrapper's runtime composition (env-var lookup + `withUpdateCheck` finally hook). Unit tests over `Cardano.Tx.*.Cli` cover the parser-level `CliBanner` argument change at compile-and-test-time but cannot run the binary. **Each slice adds its own `gate.sh` smoke** so the live-boundary stays covered as soon as the slice ships.

## `gate.sh` Evolution

| After | gate.sh state |
|---|---|
| bootstrap (5c661cf) | initial: `git diff --check`, `just build`, `just unit` |
| S1 | + `cabal run -v0 -O0 tx-validate -- --version` smoke |
| S2 | + `cabal run -v0 -O0 tx-diff -- --version` smoke |
| S3 | + `cabal run -v0 -O0 cardano-tx-generator -- --version` smoke |
| S4 | + `cabal run -v0 -O0 tx-sign -- --version` smoke |
| S5 | **removed** (`chore: drop gate.sh (ready for review)`) |

## Open Risks / Trade-offs

- **`cardano-tx-generator` does not adopt the sublibrary's `versionOption`.** Captured in spec.md Clarifications and FR-006. The acceptance is externally-observable `--version` behaviour; the inline short-circuit satisfies it without taking on an optparse-applicative rewrite of cardano-tx-generator's hand-rolled parser (which would be a separate, much larger PR).
- **`gate.sh` is per-exe smoke-heavy**: by S4 there are four `cabal run` invocations on top of the build + unit + cabal-check baseline. This roughly doubles the gate's wall-clock. Acceptable for the per-PR gate (runs locally and on each subagent dispatch); `gate.sh` is dropped before merge so it doesn't affect `nix flake check` runtime.
- **Sublibrary pin floats forward**: the pin bump in S1 is to a specific main commit (`d901311`+). If `github-release-check` main moves between S1 and finalization, we do NOT chase it — the pin we land on is the pin that gets reviewed.

## Phase 0 → Phase 1 Gate

Constitution gate: pass. Spec gate: pass (no `[NEEDS CLARIFICATION]` markers). Plan ready for `tasks.md` authoring.

## Stop

User authorised solo end-to-end. Proceeding to `tasks.md`.

# 155 — PR CI compiles every shipped executable and runs the smoke scripts

Issue: lambdasistemi/cardano-tx-tools#155

## User story

As a maintainer merging a PR, I want PR CI to compile every executable
the project ships and to run the CLI smoke scripts against the Nix-built
binaries, so that a compile error or CLI-surface regression in any tool
turns a required check red instead of merging green.

## Requirements

- **R1** The `build` flake check realizes the executables `tx-inspect`,
  `tx-sign`, `tx-validate`, `tx-view` in addition to the ones it already
  realizes, and names the `tx-build` sub-library explicitly (today it is
  realized only transitively through `library`).
- **R2** A flake check runs `scripts/smoke/tx-sign`,
  `scripts/smoke/tx-inspect` and `scripts/smoke/tx-diff`, each against
  the Nix-built executable of its tool (`TX_SIGN_EXE`, `TX_INSPECT_EXE`,
  `TX_DIFF_EXE`), never against a cabal build.
- **R3** The `Build Gate` CI job builds the R2 check, so it is covered by
  a required status context today. A downstream CI job runs the same
  check as an app (`nix run --quiet .#<name>`), following the existing
  per-check job pattern.
- **R4** `just ci` invokes the local equivalent of every CI step this
  ticket adds.
- **R5** `nix develop --quiet -c just ci` is green locally and every
  required GitHub check is green on the PR head.

## Invariants

| ID | Fails when | Holds when |
|---|---|---|
| INV-1 | a compile error in any of the four newly covered executables leaves `nix build .#checks.x86_64-linux.build` green | that build is red for each such break |
| INV-2 | a smoke-golden mismatch or CLI-surface change asserted by a smoke script leaves the R2 check green | the R2 check is red |
| INV-3 | the R2 check passes without executing the smoke scripts (skip, empty loop, cabal fallback, missing exe path) | the check fails if a script or its exe is absent |
| INV-4 | a CI step added here has no `just ci` counterpart | `just ci` runs the same Nix app CI runs |

## Rejection behaviour

A smoke script failure exits non-zero inside the Nix sandbox and the
check derivation fails; no output is produced.

## Out of scope

aarch64 evaluation (#138), Darwin release smoke (#67), new smoke scripts
for `tx-validate`, `tx-view`, `tx-graph`, `tx-fetch`, branch-protection
changes (adding the new job as a required context is an operator action).

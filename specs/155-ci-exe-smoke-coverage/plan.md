# Plan — 155

## Strategy

Extend the existing `nix/checks.nix` gate table: add the four executables
and the `tx-build` sub-library to `gateSpecs.build`; add one new gate whose
script exports the three `TX_*_EXE` variables to Nix store paths and runs
the three smoke scripts from the source root. Wire the new check into
`Build Gate`'s build list, add a downstream job that runs its app, and
make `just ci` run that app.

## Constraints

- The check runs in the `runCommand` sandbox: read-only source, no
  network, CWD set by `mkCheck`, strict PATH from `runtimeInputs`.
- No smoke script may fall back to `cabal` inside the check.
- Smoke scripts are not rewritten beyond what the sandbox requires; a
  script that cannot run in the sandbox is reported, not reshaped.
- Required checks on `main` are unchanged by this PR.

## Slices

1. **S1** (single, bisect-safe): R1–R5 together.

# Spec — aarch64-linux artifacts via dev-assets shared lib

Issue: lambdasistemi/cardano-tx-tools#119 · Epic: paolino/dev-assets#29 · Depends on #27.

## P1 user story

As a Linux `aarch64` user, I download a `cardano-tx-tools` AppImage and a musl
tarball for arm64 from the release page and run any of the executables
(tx-diff, tx-validate, tx-fetch, tx-inspect, tx-sign, tx-graph, tx-view,
cardano-tx-generator).

## Problem

`flake.nix` declares `systems = [ "x86_64-linux" "aarch64-darwin" ]` (no
aarch64-linux), the Linux release artifacts are gated to x86_64-linux, and the
plumbing is the per-repo `nix/linux-release.nix` + `nix/linux-artifact-smoke.nix`.
There is no aarch64-linux build and no musl tarball.

## Functional requirements

- FR1: `flake.nix` declares `aarch64-linux`; haskell.nix evaluates there with
  Linux-only overrides gated at the modules-list level (no `blockio-uring` /
  `liburing` evaluation error on aarch64).
- FR2: dev-assets is pinned to the #27 commit; per-exe
  `<exe>-linux-release-artifacts` use `dev-assets.lib.mkLinuxArtifacts`, and the
  smoke uses `dev-assets.lib.mkLinuxArtifactSmoke`. `nix/linux-release.nix` and
  `nix/linux-artifact-smoke.nix` are deleted.
- FR3: a musl static tarball is produced per exe from a
  `aarch64-multiplatform-musl` (and x86_64 musl) haskell.nix cross.
- FR4: `release.yml` builds the aarch64 matrix (AppImage + musl) on
  `ubuntu-24.04-arm`, pinning the dev-assets actions to the #27 sha and adopting
  `setup-nix@<#26 sha>` for the hardened cachix.
- FR5: every aarch64 artifact smoke-passes from its extracted form for all
  executables.
- FR6 (evidence gate): the aarch64 GHC is warmed into `paolino` (cachix-warmup
  arm leg) and `assert-no-source-ghc` passes on a real aarch64 build — no GHC
  recompile.

## Success criteria

- `nix build .#<exe>-linux-release-artifacts` on aarch64 yields AppImage + musl
  tarball; smoke passes from extracted form.
- x86_64 AppImage/DEB/RPM + the aarch64-darwin Homebrew flow are unchanged.
- The two per-repo nix files are gone; the shared lib is the single source.

## Non-goals

- Darwin Homebrew changes.
- Executable behavior changes.
- Pinning dev-assets to a tagged release (owned by the harmonize child #28).
- DEB/RPM for aarch64 (matrix omits them by design).

**Command-recovery:** yes
Operator commands: tx-diff, tx-validate, tx-fetch, tx-inspect, tx-sign,
tx-graph, tx-view, cardano-tx-generator.

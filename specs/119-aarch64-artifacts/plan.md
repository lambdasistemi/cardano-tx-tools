# Plan — aarch64-linux artifacts (#119)

## Tech stack

haskell.nix flake (GHC 9.12.3) + `dev-assets.lib` (pinned to #27 `3921441`) +
`NixOS/bundlers` + haskell.nix musl cross. Pins: setup-nix `83607c2` (#26),
dev-assets actions/lib `3921441` (#27).

## Risk callout

**Slice 3 (musl cross) is the real risk.** haskell.nix
`aarch64-multiplatform-musl` cross of tx-tools' cardano deps (ledger, crypto)
is heavier than moog's (which proved the pattern). Expect iteration on
pkgconfig / static-lib overrides. Slices are ordered so the glibc aarch64
AppImage path (lower risk) lands before musl, and musl is isolated so a stall
there doesn't block the rest.

## Slices (bisect-safe)

1. **aarch64-linux evaluation** — add `aarch64-linux` to `systems`; split the
   Linux-only haskell.nix overrides (liburing/blockio-uring) into a module
   gated at the modules-list level via the outer `pkgs.stdenv.isLinux`. Proof:
   `nix eval .#packages.aarch64-linux.<exe>.outPath` succeeds (no module error).
2. **adopt shared lib (glibc, x86_64 regression-safe)** — pin dev-assets to
   #27; replace `mkExeLinuxRelease` (local `nix/linux-release.nix`) with
   `dev-assets.lib.mkLinuxArtifacts` and the smoke with
   `dev-assets.lib.mkLinuxArtifactSmoke`; delete the two local files. musl
   wired as a follow (this slice keeps x86_64 AppImage/DEB/RPM green).
   Proof: x86_64 `<exe>-linux-release-artifacts` build + smoke unchanged.
3. **musl cross** — expose `*-multiplatform-musl` exes; feed `muslPackage` into
   `mkLinuxArtifacts` for x86_64 + aarch64. Proof: musl tarball builds + runs
   (statically linked) for one exe, then all.
4. **aarch64 release workflow** — `release.yml` aarch64 leg on
   `ubuntu-24.04-arm`; adopt `setup-nix@83607c2`; pin actions to #27. Proof: CI
   builds aarch64 AppImage + musl + smoke for every exe.
5. **GHC-cache evidence** — warm aarch64 GHC (cachix-warmup arm leg) and prove
   `assert-no-source-ghc` passes on a real aarch64 build (narinfo 200). Closes
   the epic's aarch64 cachix evidence gate.

## Verification

- Local: `./gate.sh` (build x86_64 artifacts + smoke; eval aarch64).
- CI: existing + the aarch64 release leg.

## Open item (revisit at slice 4)

The aarch64 artifact set currently excludes DEB/RPM — a design choice mirroring
moog, NOT a confirmed upstream limitation (`NixOS/bundlers` declares
aarch64-linux support for toDEB/toRPM). Verify they build on aarch64 at slice 4
and include them if so. Parameterized via `glibcArtifacts` + the smoke
`artifacts` list, so flipping it on is a one-liner.

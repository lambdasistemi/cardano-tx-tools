# Tasks — aarch64-linux artifacts (#119)

## Slice 1 — aarch64-linux evaluation
- [X] T119-S1 GREEN: add `aarch64-linux` to `systems`; gate Linux-only
      haskell.nix overrides (liburing/blockio-uring) at the modules-list level.
- [X] T119-S1 proof: `nix eval .#packages.aarch64-linux.tx-diff.outPath` succeeds.

## Slice 2 — adopt shared lib (glibc, x86_64 regression-safe)
- [X] T119-S2 GREEN: pin dev-assets to #27 (3921441); use
      `dev-assets.lib.mkLinuxArtifacts` + `mkLinuxArtifactSmoke`; delete
      `nix/linux-release.nix` + `nix/linux-artifact-smoke.nix`.
- [X] T119-S2 proof: x86_64 `<exe>-linux-release-artifacts` build + smoke
      unchanged for all exes.

## Slice 3 — musl cross (RISK)
- [ ] T119-S3 GREEN: expose `*-multiplatform-musl` exes; feed `muslPackage`
      into `mkLinuxArtifacts` for x86_64 + aarch64.
- [ ] T119-S3 proof: musl tarball builds + runs statically for one exe, then all.

## Slice 4 — aarch64 release workflow
- [ ] T119-S4 GREEN: `release.yml` aarch64 leg on `ubuntu-24.04-arm`; adopt
      `setup-nix@83607c2`; pin dev-assets actions to #27.
- [ ] T119-S4 proof: CI builds aarch64 AppImage + musl + smoke for every exe.

## Slice 5 — GHC-cache evidence
- [ ] T119-S5: warm aarch64 GHC (cachix-warmup arm leg); `assert-no-source-ghc`
      passes on a real aarch64 build (narinfo 200) — no GHC recompile.

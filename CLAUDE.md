# CLAUDE.md

This project's agent guidance lives in [AGENTS.md](AGENTS.md) — what the repo
is, the build/test/run commands that work, and the `skills/` directory
(load `skills/cardano-tx-tools-guide/` for the repository map and verified CLI
usage). Start there.

Toolchain: Haskell, GHC 9.12.3 via `haskell.nix`
(`compiler-nix-name = "ghc9123"`). Per-feature design notes are under `specs/`.

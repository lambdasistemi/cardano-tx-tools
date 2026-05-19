#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR backing issue #48
# (rules loader: Turtle + YAML sugar + owl:imports composition; epic #46 Wave 2 self-contained, post-#47 deferral).
# Subagents MUST run ./gate.sh and observe success before returning a commit.
# Removed in the final `chore: drop gate.sh (ready for review)` commit before
# the PR is marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit

nix develop --quiet -c cabal-fmt -c cardano-tx-tools.cabal
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +"
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +"

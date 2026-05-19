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

# Hackage-ready quality (constitution Principle IV) — anchors SC-007 (cabal
# check clean). Also runs cabal haddock so haddock syntax errors and broken
# link targets cannot regress. Strict missing-docstring enforcement (every
# export carries a Haddock comment) is partial — the gate verifies the
# haddock build succeeds, not that every export is documented. Strict
# coverage enforcement is tracked as a follow-up issue (see specs/048-
# rules-loader/spec.md FR-016 / SC-006 wording).
nix develop --quiet -c cabal check
nix develop --quiet -c cabal -O0 haddock lib:cardano-tx-tools

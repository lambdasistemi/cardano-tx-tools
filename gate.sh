#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR backing issue #40
# (collapse engine: nested rules + raw-omit mode for usable tx review).
# Subagents MUST run ./gate.sh and observe success before returning a commit.
# Removed in the final `chore: drop gate.sh (ready for review)` commit before
# the PR is marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit
# The InspectSpec goldens are the load-bearing regression surface for the
# collapse engine. #40 changes engine semantics (nested recursion + a new
# raw-view mode), so the existing collapse-only and Amaru both-stages
# goldens must keep passing for inputs that do NOT use the new features
# (backwards compatibility, FR-NESTED-COMPAT below).
nix develop --quiet -c just smoke-inspect

nix develop --quiet -c cabal-fmt -c cardano-tx-tools.cabal
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +"
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +"

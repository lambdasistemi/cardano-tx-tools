#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR backing issue #43
# (collapse silently disables rename for payment-address leaves in required:).
# Subagents MUST run ./gate.sh and observe success before returning a commit.
# Removed in the final `chore: drop gate.sh (ready for review)` commit before
# the PR is marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit
# The InspectSpec goldens are the load-bearing regression surface for the
# rewriting-rules pipeline. #43 changes the engine pre-extraction so that
# rename also fires on collapse-`required:`-pinned leaves; the existing
# goldens MUST keep passing for inputs where no rename rule matches a
# `required:`-pinned leaf (backwards compatibility).
nix develop --quiet -c just smoke-inspect

nix develop --quiet -c cabal-fmt -c cardano-tx-tools.cabal
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +"
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +"

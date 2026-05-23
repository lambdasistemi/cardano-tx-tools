#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR backing issue #88
# (tx-inspect: library API for mapping inspect-tree leaves to
# Cardanoscan URLs, with opt-in CLI flag).
#
# Every behavior-changing commit MUST observe this script green
# before being accepted by the orchestrator. Removed in the final
# `chore: drop gate.sh (ready for review)` commit before the PR is
# marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit
# tx-inspect is the shipped CLI surface this ticket extends; the
# smoke proves the operator command path end-to-end (the
# library-level mapper is unit-tested in the suite above).
nix develop --quiet -c just smoke-inspect

nix develop --quiet -c cabal-fmt -c cardano-tx-tools.cabal
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +"
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +"

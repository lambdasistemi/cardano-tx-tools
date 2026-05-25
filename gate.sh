#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR backing issue #51
# (SPARQL view library plus tx-view executable).
# Worker pairs MUST run ./gate.sh and observe success before returning a
# commit. Removed in the final `chore(051): drop gate.sh (ready for review)`
# commit before the PR is marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit

nix develop --quiet -c cabal-fmt -c cardano-tx-tools.cabal
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +"
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +"

# Hackage-ready quality.
nix develop --quiet -c cabal check
nix develop --quiet -c cabal -O0 haddock lib:cardano-tx-tools

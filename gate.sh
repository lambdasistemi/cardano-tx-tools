#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR backing issue #32
# (tx-inspect — shared-substrate transaction renderer with two-stage rewriting).
# Subagents MUST run ./gate.sh and observe success before returning a commit.
# Removed in the final `chore: drop gate.sh (ready for review)` commit before
# the PR is marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit
# S1: tx-inspect baseline live-boundary smoke.
nix develop --quiet -c just smoke-inspect
# S4: tx-diff shared-substrate live-boundary smoke (proves T034a
# wiring — tx-diff consumes the unified rewriting-rules YAML).
nix develop --quiet -c just smoke-diff

nix develop --quiet -c cabal-fmt -c cardano-tx-tools.cabal
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +"
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +"

# S6 (T044): the Linux release workflow ships AppImage / DEB / RPM
# artifacts via a per-CLI matrix. Every CLI shipped on Linux MUST be
# in that matrix. tx-inspect is the fifth shipped CLI (issue #32 / FR-017)
# and must be in parity with tx-diff. Darwin Homebrew and the Docker
# publish workflow follow a different (single-CLI / daemon-only)
# convention and are intentionally not asserted here — see specs/032
# WIP.md T043 enumeration.
if grep -q 'name: tx-diff' .github/workflows/release.yml \
    && ! grep -q 'name: tx-inspect' .github/workflows/release.yml; then
    echo "release.yml ships tx-diff but not tx-inspect" >&2
    exit 1
fi

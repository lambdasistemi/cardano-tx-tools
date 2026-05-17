#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR #29 (issue #28 — withCli + versionOption migration).
# Subagents MUST run ./gate.sh and observe success before returning a commit.
# Removed in the final `chore: drop gate.sh (ready for review)` commit before
# the PR is marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit
# Per-exe smoke (added by each slice): assert `--version` works on the
# rewritten executable. The smoke block is appended by each slice's commit;
# see specs/28-withcli-migration/plan.md § gate.sh evolution.

# tx-validate live-boundary smoke (slice S1)
tx_validate_version="$(nix develop --quiet -c cabal run -v0 -O0 tx-validate -- --version)"
tx_validate_first_line="$(printf '%s\n' "$tx_validate_version" | head -1)"
printf '%s\n' "$tx_validate_first_line" \
    | grep -qE '^tx-validate [0-9]+(\.[0-9]+)*$' \
    || { echo "tx-validate --version smoke: first line mismatch: $tx_validate_first_line"; exit 1; }

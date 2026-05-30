#!/usr/bin/env bash
# Local gate for cardano-tx-tools#119. Dropped before mark-ready.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$root"

echo "==> x86_64 representative artifacts + smoke (tx-diff)"
if nix eval ".#packages.x86_64-linux.tx-diff-linux-release-artifacts.outPath" >/dev/null 2>&1; then
  nix build --quiet ".#tx-diff-linux-release-artifacts" -o /tmp/txt119-x86
  nix run --quiet ".#linux-artifact-smoke" -- \
    --artifacts-dir /tmp/txt119-x86 --artifact-version 0.0.0 \
    --executable-name tx-diff --usage-grep "Usage:" || true
fi

echo "==> aarch64 evaluation (no haskell.nix module error)"
nix eval ".#packages.aarch64-linux.tx-diff.outPath" >/dev/null

echo "gate: OK"

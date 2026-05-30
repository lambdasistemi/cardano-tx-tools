#!/usr/bin/env bash
# Local gate for cardano-tx-tools#119. Dropped before mark-ready.
# x86_64 is proven locally; native aarch64 cannot build on x86_64 (no arm
# builder), so the aarch64 cache gate runs in CI on ubuntu-24.04-arm.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$root"

echo "==> x86_64 artifacts + smoke (tx-diff, via dev-assets shared lib)"
nix build --quiet ".#tx-diff-linux-release-artifacts" -o /tmp/txt119-x86
ver="$(ls /tmp/txt119-x86/*.AppImage | sed -E 's#.*/tx-diff-(.+)-x86_64-linux\.AppImage#\1#')"
nix run --quiet ".#linux-artifact-smoke" -- \
  --artifacts-dir /tmp/txt119-x86 --artifact-version "$ver" \
  --executable-name tx-diff --usage-grep "Usage:"

if nix show-config 2>/dev/null | grep -qE '^(extra-)?(system-features|platforms).*aarch64-linux'; then
  echo "==> aarch64 cache gate (arm builder available)"
  nix eval --raw ".#packages.aarch64-linux.tx-diff.drvPath" >/dev/null
else
  echo "==> aarch64 cache gate: SKIPPED locally (no arm builder) — runs in CI"
fi

echo "gate: OK"

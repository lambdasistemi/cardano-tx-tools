#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix flake check --no-eval-cache

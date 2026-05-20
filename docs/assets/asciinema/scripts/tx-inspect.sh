#!/usr/bin/env bash
# Demo: tx-inspect (structured Conway tx render + rules-driven rename/collapse).
# Record with:
#   nix develop /code/dev-assets/asciinema -c \
#     asciinema rec -c ./tx-inspect.sh ../tx-inspect.cast
set -euo pipefail

export PATH="/tmp/ticket-066/cast-bin:$PATH"
FIXTURES=/code/cardano-tx-tools-issue-66/test/fixtures
RULES=/code/cardano-tx-tools-issue-66/rules/amaru-treasury.yaml
TX="$FIXTURES/amaru-treasury-swap/swap-1.cbor.hex"

say() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.6; }

clear
say 'tx-inspect --help'
tx-inspect --help
sleep 2

say '# Verbatim render of a checked-in Conway tx fixture.'
say 'tx-inspect .../swap-1.cbor.hex | head -20'
tx-inspect "$TX" | head -20
sleep 2

say '# Same tx + rules.yaml — collapse repeated shapes and rename hashes.'
say 'tx-inspect --rules rules/amaru-treasury.yaml .../swap-1.cbor.hex | head -30'
tx-inspect --rules "$RULES" "$TX" | head -30
sleep 2

#!/usr/bin/env bash
# Demo: tx-graph (operator-entity overlay + body emitter).
# Record with:
#   nix develop /code/dev-assets/asciinema -c \
#     asciinema rec -c ./tx-graph.sh ../tx-graph.cast
set -euo pipefail

export PATH="/tmp/ticket-066/cast-bin:$PATH"
FIXTURES=/code/cardano-tx-tools-issue-66/test/fixtures
RULES="$FIXTURES/rewrite-redesign/02-alice-bob-ada/rules.yaml"
TX="$FIXTURES/amaru-treasury-swap/swap-1.producer-txs/25ba96f5deb14bb5c56e7542d6a9ba8450f52cc698ebd74574e1a0525d861095.cbor.hex"

say() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.6; }

clear
say 'tx-graph --help'
tx-graph --help
sleep 2

say '# Overlay only — emit operator-declared entities from a rules.yaml.'
say 'tx-graph --rules .../02-alice-bob-ada/rules.yaml | head -20'
tx-graph --rules "$RULES" | head -20
sleep 2

say '# Body only via stdin — Conway tx CBOR piped in, no rules.'
say 'cat .../25ba96...cbor.hex | tx-graph --tx - | head -15'
cat "$TX" | tx-graph --tx - | head -15
sleep 2

say '# Joint graph — rules overlay + body emitted together.'
say 'cat .../25ba96...cbor.hex | tx-graph --rules .../rules.yaml --tx - | head -25'
cat "$TX" | tx-graph --rules "$RULES" --tx - | head -25
sleep 2

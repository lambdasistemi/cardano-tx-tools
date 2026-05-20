#!/usr/bin/env bash
# Demo: tx-graph (operator-entity overlay).
# Record with:
#   nix develop /code/dev-assets/asciinema -c \
#     asciinema rec -c ./tx-graph.sh ../tx-graph.cast
#
# Body-emitter and joint-graph demos are deferred to the
# transaction-to-RDF epic (lambdasistemi/cardano-tx-tools#46) —
# reference inputs unsupported, output amounts / datums / scriptRefs
# not yet emitted; this cast focuses on the polished overlay-only
# surface.
set -euo pipefail

export PATH="/tmp/ticket-066/cast-bin:$PATH"
FIXTURES=/code/cardano-tx-tools-issue-66/test/fixtures
RULES="$FIXTURES/rewrite-redesign/11-amaru-treasury-swap-real/rules.yaml"

say() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.6; }

clear
say 'tx-graph --help'
tx-graph --help
sleep 3

say '# Overlay-only — emit operator-declared entities from a rules.yaml.'
say 'tx-graph --rules .../11-amaru-treasury-swap-real/rules.yaml'
tx-graph --rules "$RULES"
sleep 6

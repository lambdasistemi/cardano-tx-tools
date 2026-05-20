#!/usr/bin/env bash
# Demo: tx-validate (Conway Phase-1 pre-flight + structural-failure exit path).
# Record with:
#   nix develop /code/dev-assets/asciinema -c \
#     asciinema rec -c ./tx-validate.sh ../tx-validate.cast
#
# The happy-path verdict cast is tracked separately (lambdasistemi/cardano-tx-tools#69)
# — record it once the cardano-node-clients LTxS pin aligns with cardano-node 10.7.x.
set -euo pipefail

export PATH="/tmp/ticket-066/cast-bin:$PATH"
FIXTURES=/code/cardano-tx-tools-issue-66/test/fixtures

say() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.6; }

clear
say 'tx-validate --help'
tx-validate --help
sleep 2

say '# Assumes $CARDANO_NODE_SOCKET_PATH points at a Conway-era cardano-node.'
say '# Structural-failure path: input rejected before the N2C session opens.'
say 'tx-validate --input .../treasury-withdrawal.cbor.hex \'
say '            --n2c-socket-path "$CARDANO_NODE_SOCKET_PATH" \'
say '            --network-magic 764824073'
sleep 0.3
tx-validate \
  --input "$FIXTURES/mainnet-txbuild/conway-042/treasury-withdrawal.cbor.hex" \
  --n2c-socket-path "${CARDANO_NODE_SOCKET_PATH:-/code/cardano-mainnet/ipc/node.socket}" \
  --network-magic 764824073 \
  || echo "exit: $?"
sleep 2

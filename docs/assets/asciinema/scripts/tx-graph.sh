#!/usr/bin/env bash
# Demo: tx-graph — fixture 11 rich RDF body emission plus CIP-57 typed datum output.
#
# Record from the repository root with:
#   nix develop --quiet -c bash -lc '
#     cabal build exe:tx-graph -O0 >/dev/null
#     export TX_GRAPH_EXE="$(cabal list-bin exe:tx-graph -O0)"
#     cd docs/assets/asciinema/scripts
#     nix develop /code/dev-assets/asciinema -c \
#       asciinema rec -c ./tx-graph.sh --overwrite ../tx-graph.cast
#   '
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
FIXTURES="$ROOT/test/fixtures/rewrite-redesign"
RULES="$FIXTURES/11-amaru-treasury-swap-real/rules.yaml"
TX="$ROOT/test/fixtures/amaru-treasury-swap/swap-2.producer-txs/5fc04113da630ec676a5a7a66d82f53c0e64527ee592c3e6c5e1dccad67732ea.cbor.hex"
TYPED="$FIXTURES/12-blueprint-typed/expected.ttl"
DECODE_FAIL="$FIXTURES/14-blueprint-decode-fail/expected.ttl"
TX_GRAPH=${TX_GRAPH_EXE:-tx-graph}
GRAPH=$(mktemp)
trap 'rm -f "$GRAPH"' EXIT

say() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.4; }

printf '\033[H\033[J\033[3J'
say 'tx-graph --help'
"$TX_GRAPH" --help
sleep 3

say '# Section 1 — fixture 11 rules: operator-declared entities.'
say 'tx-graph --rules .../11-amaru-treasury-swap-real/rules.yaml | head -24'
"$TX_GRAPH" --rules "$RULES" | head -24
sleep 4

say '# Section 2 — fixture 11 real tx: rules + CBOR produce one joint RDF graph.'
say 'tx-graph --rules .../11-amaru-treasury-swap-real/rules.yaml --tx .../5fc04113....cbor.hex'
"$TX_GRAPH" --rules "$RULES" --tx "$TX" > "$GRAPH"
say 'sed -n "55,82p" graph.ttl'
sed -n '55,82p' "$GRAPH"
sleep 5

say '# Section 3 — real outputs: lovelace amounts plus inline datum blocks.'
say 'sed -n "184,215p" graph.ttl'
sed -n '184,215p' "$GRAPH"
sleep 5

say '# Section 4 — address decomposition preserves entity-named credentials.'
say 'grep -A4 "a cardano:Address" graph.ttl | head -24'
grep -A4 'a cardano:Address' "$GRAPH" | head -24
sleep 5

say '# Section 5 — withdrawals, collateral return, redeemers, and execution units.'
say 'grep -B1 -A8 "Withdrawal\\|hasCollateralReturn\\|hasExUnits\\|ExUnits" graph.ttl | head -38'
grep -B1 -A8 'cardano:Withdrawal\|cardano:hasCollateralReturn\|cardano:hasExUnits\|cardano:ExUnits' "$GRAPH" | head -38
sleep 5

say '# Section 6 — CIP-57 blueprint decode: datum fields become typed predicates.'
say 'sed -n "47,65p" .../12-blueprint-typed/expected.ttl'
sed -n '47,65p' "$TYPED"
sleep 5

say '# Section 7 — decode failures remain non-fatal and keep raw bytes + decodeError.'
say 'sed -n "50,56p" .../14-blueprint-decode-fail/expected.ttl'
sed -n '50,56p' "$DECODE_FAIL"
sleep 5

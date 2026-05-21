#!/usr/bin/env bash
# Demo: tx-graph — body emitter Conway semantic completeness (#70).
#
# Record with:
#   nix develop /code/dev-assets/asciinema -c \
#     asciinema rec -c ./tx-graph.sh --overwrite ../tx-graph.cast
#
# Cast demonstrates the rich body output that #70 closed: per-input
# cardano:fromTxOutRef, per-output cardano:lovelace,
# cardano:hasAssetValue multi-asset RDF list, cardano:hasDatum
# sub-block, cardano:hasReferenceScript, body-root predicates
# (cardano:hasValidityInterval, cardano:networkId, …), certificate /
# withdrawal / mint / proposal clusters with canonical predicate
# names.
#
# The Sections-2/3/4 fixture excerpts are the EXACT byte-equal output
# of `tx-graph --tx` on each rewrite-redesign harness-built tx (the
# harness builds the tx programmatically — no on-disk CBOR — so the
# regenerated expected.ttl IS what tx-graph emits).
set -euo pipefail

export PATH="/tmp/cast-bin-070:$PATH"
WORKTREE=/code/cardano-tx-tools-070-body-emit
FIXTURES="$WORKTREE/test/fixtures/rewrite-redesign"

say() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.4; }

clear
say 'tx-graph --help'
tx-graph --help
sleep 3

say '# Section 1 — overlay mode: operator-declared entities from rules.yaml.'
say 'tx-graph --rules .../11-amaru-treasury-swap-real/rules.yaml | head -20'
tx-graph --rules "$FIXTURES/11-amaru-treasury-swap-real/rules.yaml" | head -20
sleep 4

say '# Section 2 — body emit on fixture 11 (real Amaru swap mirror): inputs / outputs / multi-asset.'
say 'sed -n "55,95p" .../11-amaru-treasury-swap-real/expected.ttl'
sed -n '55,95p' "$FIXTURES/11-amaru-treasury-swap-real/expected.ttl"
sleep 5

say '# Section 3 — datum + scriptRef on fixture 01 (Amaru treasury swap with inline datum).'
say 'grep -A4 "hasDatum\|hasReferenceScript" .../01-amaru-treasury-swap/expected.ttl | head -25'
grep -A4 'hasDatum\|hasReferenceScript' "$FIXTURES/01-amaru-treasury-swap/expected.ttl" | head -25
sleep 5

say '# Section 4 — mint signed quantity on fixture 04 + withdrawal canonical on fixture 05.'
say 'grep -B1 -A3 "mintsAsset\|withdrawalAccount" fixtures/04/expected.ttl fixtures/05/expected.ttl'
grep -B1 -A3 'mintsAsset\|withdrawalAccount' \
  "$FIXTURES/04-mint-spend-script-overlap/expected.ttl" \
  "$FIXTURES/05-withdrawal-script-stake/expected.ttl"
sleep 6

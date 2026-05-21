#!/usr/bin/env bash
# Demo: tx-graph — body emitter Conway semantic completeness (#70).
#
# Record with:
#   nix develop /code/dev-assets/asciinema -c \
#     asciinema rec -c ./tx-graph.sh --overwrite ../tx-graph.cast
#
# Cast demonstrates the rich body output that #70 closed:
#  * post-T122c Identifier-typed nodes for identity-bearing
#    positions (hasRequiredSigner, scriptDataHash, hash on Datum
#    / ReferenceScript) — joinable on bnode equality;
#  * fromTxOutRef decomposed into a typed cardano:TxOutRef
#    sub-node with hasTxId Identifier + hasIndex;
#  * per-output cardano:lovelace, cardano:hasAssetValue
#    multi-asset RDF list, cardano:hasDatum sub-block,
#    cardano:hasReferenceScript with Plutus/Native discrimination;
#  * body-root predicates (cardano:hasValidityInterval,
#    cardano:networkId, ...);
#  * certificate / withdrawal / mint / proposal / vote clusters
#    with canonical predicate names;
#  * cert + proposal variants beyond StakeDelegation /
#    TreasuryWithdrawals via the cardano:OpaqueLeaf fallback
#    (T120 / T121).
#
# The Section-* fixture excerpts are the EXACT byte-equal output
# of `tx-graph --tx` on each rewrite-redesign harness-built tx.
set -euo pipefail

export PATH="/tmp/cast-bin-070:$PATH"
WORKTREE=/code/cardano-tx-tools-070-body-emit
FIXTURES="$WORKTREE/test/fixtures/rewrite-redesign"
CACHE="$WORKTREE/test/fixtures/blockfrost-cache"

say() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.4; }

clear
say 'tx-graph --help'
tx-graph --help
sleep 3

say '# Section 1 — overlay mode: operator-declared entities from rules.yaml.'
say 'tx-graph --rules .../11-amaru-treasury-swap-real/rules.yaml | head -20'
tx-graph --rules "$FIXTURES/11-amaru-treasury-swap-real/rules.yaml" | head -20
sleep 4

say '# Section 2 — body emit on fixture 11: inputs / outputs / multi-asset.'
say '#            Notice fromTxOutRef now binds an inputTxOutRefK sub-node (T122c).'
say 'sed -n "55,100p" .../11-amaru-treasury-swap-real/expected.ttl'
sed -n '55,100p' "$FIXTURES/11-amaru-treasury-swap-real/expected.ttl"
sleep 5

say '# Section 3 — Identifier-typed bnodes for credential / hash positions (T119b + T122c).'
say 'grep -B1 -A3 "a cardano:Identifier" .../11-amaru-treasury-swap-real/expected.ttl | head -25'
grep -B1 -A3 'a cardano:Identifier' "$FIXTURES/11-amaru-treasury-swap-real/expected.ttl" | head -25
sleep 5

say '# Section 4 — datum + scriptRef on fixture 01 (now typed as cardano:NativeScript per T118).'
say 'grep -B1 -A5 "hasDatum\|NativeScript\|PlutusScript" .../01-amaru-treasury-swap/expected.ttl'
grep -B1 -A5 'hasDatum\|NativeScript\|PlutusScript' "$FIXTURES/01-amaru-treasury-swap/expected.ttl" | head -25
sleep 5

say '# Section 5 — body-root predicates (validity / networkId / scriptDataHash) + mint signed quantity.'
say 'grep -B1 -A2 "hasValidityInterval\|networkId\|scriptDataHash\|mintsAsset" .../04 .../05'
grep -B1 -A2 'hasValidityInterval\|networkId\|scriptDataHash\|mintsAsset' \
  "$FIXTURES/04-mint-spend-script-overlap/expected.ttl" \
  "$FIXTURES/05-withdrawal-script-stake/expected.ttl" | head -25
sleep 5

say '# Section 6 — real-chain acceptance: the operator-paste tx decodes + emits cleanly (T127).'
say 'tx-graph --tx test/fixtures/blockfrost-cache/operator-paste-2026-05-21.cbor.hex | head -25'
tx-graph --tx "$CACHE/operator-paste-2026-05-21.cbor.hex" | head -25
sleep 6

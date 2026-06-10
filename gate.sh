#!/usr/bin/env bash
set -euo pipefail
git diff --check
nix develop --quiet -c just ci

# Ticket-specific proof (#127): the tx-build sub-library is the single
# source of truth, so its modules must stay reconciled with the
# cardano-ledger-rdf reference copy until that repo deletes its copy and
# depends on tx-build (its #86). Build.hs and Balance.hs are byte-identical
# to the reference; Witnesses/Deposits/Scripts/Credentials/Inputs were
# already identical; MinUtxoSpec.hs (min-UTxO auto-compensation, rdf#81)
# is byte-identical. Ledger.hs is intentionally NOT checked: its module
# Haddock paragraph differs by design (sub-library-neutral wording here).
#
# Guarded: the reference is a local read-only sibling checkout, so skip
# (don't fail) when it is absent — this keeps the gate runnable elsewhere.
REF=/code/cardano-ledger-rdf
if [ -d "$REF/src/Cardano/Tx" ]; then
    for m in Build Balance Witnesses Deposits Scripts Credentials Inputs; do
        diff -q "src-tx-build/Cardano/Tx/$m.hs" "$REF/src/Cardano/Tx/$m.hs"
    done
    diff -q test/Cardano/Tx/Build/MinUtxoSpec.hs \
        "$REF/test/Cardano/Tx/Build/MinUtxoSpec.hs"
    echo "drift-parity: tx-build modules byte-identical to cardano-ledger-rdf reference"
else
    echo "drift-parity: SKIPPED ($REF not present)"
fi

#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR backing issue #70
# (body emitter Conway semantic completeness — WriterT/State seam;
#  successor to #58, child of epic #46).
# Subagents MUST run ./gate.sh and observe success before returning a commit.
# Removed in the final `chore: drop gate.sh (ready for review)` commit before
# the PR is marked ready.
set -euo pipefail

git diff --check

# T115 exhaustivity lint: symmetric set-equality between the
# ConwayDiffValue constructor list declared in Cardano.Tx.Diff and
# the hand list maintained in
# test/Cardano/Tx/Graph/Emit/ExhaustivitySpec.hs.
#
# Per A-006 (architectural correction): the compiler is the
# load-bearing exhaustivity gate (-Wincomplete-patterns -Werror,
# constitution-mandated). This lint is informational only — drift
# in either direction prints a warning but does NOT fail the gate
# until the canonical pin is regenerated downstream-first from
# Vocab.hs (T122b). Until then the hand list is a documentation
# aid, not an invariant.
exhaustivity_lint() {
    local ledger hand
    ledger=$(
        grep -hE '^[[:space:]]+\| Conway[A-Z][A-Za-z]*Value' \
            src/Cardano/Tx/Diff.hs \
            | sed -E 's/^[[:space:]]+\| ([A-Za-z]+).*$/\1/' \
            | sort -u
    )
    hand=$(
        grep -hE '^[[:space:]]+, "Conway[A-Z][A-Za-z]*Value"$' \
            test/Cardano/Tx/Graph/Emit/ExhaustivitySpec.hs \
            | sed -E 's/^[[:space:]]+, "([A-Za-z]+)"$/\1/' \
            | sort -u
    )
    if ! diff -u <(printf '%s\n' "$ledger") <(printf '%s\n' "$hand") >&2; then
        echo >&2
        echo "  [informational] ExhaustivitySpec.allConwayDiffConstructors" >&2
        echo "  is out of sync with Cardano.Tx.Diff.ConwayDiffValue." >&2
        echo "  This is non-failing per A-006 — the compiler" >&2
        echo "  (-Wincomplete-patterns -Werror) is the load-bearing gate." >&2
        echo "  Update the hand list when the emitter's case-arms stabilize." >&2
    fi
}

exhaustivity_lint

nix develop --quiet -c just build
nix develop --quiet -c just unit

nix develop --quiet -c cabal-fmt -c cardano-tx-tools.cabal
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +"
nix develop --quiet -c bash -c "find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +"

# Hackage-ready quality (constitution Principle IV) — inherited from #48 / #58
nix develop --quiet -c cabal check
nix develop --quiet -c cabal -O0 haddock lib:cardano-tx-tools

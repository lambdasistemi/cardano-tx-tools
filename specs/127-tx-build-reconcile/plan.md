# Plan — #127 tx-build drift reconciliation

Tech stack: existing — Haskell, GHC 9.12.3 via haskell.nix; no new
deps. All edits confined to `src-tx-build/`, `README.md`, `gate.sh`,
and `specs/`.

Gate: `./gate.sh` = `git diff --check` + `nix develop --quiet -c just ci`
(build, unit incl. MinUtxoSpec, smokes, cabal-fmt/fourmolu/hlint).
Extended in slice 3 with byte-parity diffs against
`/code/cardano-ledger-rdf` (read-only reference).

Risk: fourmolu config drift between the two repos could make the
ported text reformat differently here. If `just ci` format-check
rewrites the ported hunks, local formatting wins and the gate parity
check must be relaxed for the affected file (document in PR body).

## Slice 1 — docs port (Build.hs, Ledger.hs)

Port from the rdf copy into `src-tx-build/Cardano/Tx/Build.hs`:
the `-- $conwayLedgerTypes` export-list anchor, the
`{- $conwayLedgerTypes ... -}` named chunk, and the Haddock blocks on
`draftWith` and `build`. Reconcile the `Ledger.hs` module Haddock to
sub-library-neutral wording. Doc-only; no behavior change.

Commit: `docs(tx-build): port Hackage-ready Haddock from the cardano-ledger-rdf copy`

## Slice 2 — foldl' reconciliation (Build.hs, Balance.hs)

Replace the 7 `List.foldl'` call sites with Prelude `foldl'`; drop the
now-unused `Data.List qualified as List` import from both files
(Build.hs keeps `Data.List (elemIndex)`). After this slice Build.hs
and Balance.hs must be byte-identical to the reference copy.
Behavior-neutral (same function, different provenance).

Commit: `refactor(tx-build): use Prelude foldl' to match the cardano-ledger-rdf copy`

## Slice 3 — README policy + gate parity extension

Add one sentence to README.md recording the integration policy
(FR4). Orchestrator then extends gate.sh with the byte-parity check
over the 7 reconciled pairs + MinUtxoSpec.

Commits:
- `docs(readme): record the cq-rdf CLI-boundary integration policy`
- `chore: extend gate.sh with rdf drift-parity check`

## Finalization

PR body audit, `chore: drop gate.sh (ready for review)`, mark ready,
Q-file to parent for merge confirmation (no self-merge).

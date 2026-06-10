# Spec — tx-build: reconcile drift with the cardano-ledger-rdf copy (#127)

## P1 user story

As a maintainer of the builder DSL, I want the `tx-build` public
sub-library to be the single source of truth for the builder modules,
so that `cardano-ledger-rdf` can delete its drifted copy and depend on
`tx-build` directly (its #86).

## Context

`cardano-ledger-rdf` (read-only reference checkout at
`/code/cardano-ledger-rdf`, main) carries a copy of
`src/Cardano/Tx/{Build,Balance,Witnesses,Deposits,Scripts,Credentials,Inputs,Ledger}.hs`
that drifted from the `tx-build` sub-library carved out in #123.

Baseline drift survey (2026-06-10):

| Module pair | Drift |
|---|---|
| Build.hs | `$conwayLedgerTypes` named Haddock chunk + export-list anchor; Haddock on `draftWith` and `build`; `List.foldl'` vs Prelude `foldl'` (4 sites) |
| Balance.hs | `List.foldl'` vs Prelude `foldl'` (3 sites) + unused `Data.List qualified` import |
| Ledger.hs | Module Haddock paragraph: tx-tools text justifies the repo's cardano-node-clients pin; rdf text is generic ("keeps the graph library independent from node-client packages") |
| Witnesses, Deposits, Scripts, Credentials, Inputs | byte-identical |
| test/Cardano/Tx/Build/MinUtxoSpec.hs | byte-identical |

## Functional requirements

- FR1: The Hackage-ready Haddock from lambdasistemi/cardano-ledger-rdf#77
  (the `$conwayLedgerTypes` named chunk and the `draftWith`/`build`
  function docs) is present in `src-tx-build/Cardano/Tx/Build.hs`.
- FR2: Min-UTxO auto-compensation (lambdasistemi/cardano-ledger-rdf#81)
  behaves identically on both sides. Verified at baseline:
  `MinUtxoSpec.hs` is byte-identical and the implementing modules carry
  no behavioral diff. No code change required; the parity is locked by
  a gate check.
- FR3: After reconciliation, `Build.hs` and `Balance.hs` are
  byte-identical to the reference copy; `Witnesses.hs`, `Deposits.hs`,
  `Scripts.hs`, `Credentials.hs`, `Inputs.hs` remain byte-identical.
  `Ledger.hs` may differ only in the module Haddock paragraph, whose
  final wording must be sub-library-neutral (no claim that only makes
  sense inside cardano-ledger-rdf or only inside cardano-tx-tools'
  resolver chain).
- FR4: README records the integration policy in one sentence:
  cardano-tx-tools consumes cq-rdf output at the CLI boundary (pipes);
  it never links the cardano-ledger-rdf library.

## Decisions

- D1: Adopt Prelude `foldl'` (rdf side) over `List.foldl'` in the
  tx-build modules. Rationale: makes Build.hs/Balance.hs byte-identical
  to the reference, which the gate can then enforce mechanically until
  the rdf copy is deleted; GHC 9.12 exports `foldl'` from Prelude. The
  `src/` tree keeps its own `List.foldl'` convention — different
  component, out of scope.
- D2: No RED tests. Every change is doc-only or behavior-neutral
  (TDD exception, documented per slice); behavior parity is already
  established at baseline and locked by the gate's diff checks.

## Success criteria

- `./gate.sh` green at HEAD, including the drift-parity extension
  (byte-equality of the 7 reconciled module pairs + MinUtxoSpec
  against /code/cardano-ledger-rdf).
- PR #128 body documents the survey, decisions, and residual
  (Ledger.hs doc paragraph) drift.

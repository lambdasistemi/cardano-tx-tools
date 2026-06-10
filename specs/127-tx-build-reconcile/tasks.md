# Tasks — #127 tx-build drift reconciliation

## Slice 1 — docs port

- [X] T001-S1 Port `$conwayLedgerTypes` named chunk + export-list anchor into src-tx-build/Cardano/Tx/Build.hs
- [X] T002-S1 Port `draftWith` and `build` Haddock blocks into src-tx-build/Cardano/Tx/Build.hs
- [X] T003-S1 Reconcile src-tx-build/Cardano/Tx/Ledger.hs module Haddock to sub-library-neutral wording
- [X] T004-S1 Gate green; one commit `docs(tx-build): ...`

## Slice 2 — foldl' reconciliation

- [ ] T005-S2 Replace `List.foldl'` with Prelude `foldl'` in Build.hs (4 sites) and Balance.hs (3 sites); drop unused `Data.List qualified as List` imports
- [ ] T006-S2 Verify Build.hs and Balance.hs byte-identical to /code/cardano-ledger-rdf reference; gate green; one commit `refactor(tx-build): ...`

## Slice 3 — README policy + gate extension

- [ ] T007-S3 Add the cq-rdf CLI-boundary integration-policy sentence to README.md; gate green; one commit `docs(readme): ...`
- [ ] T008-S3 Extend gate.sh with the rdf drift-parity check (orchestrator)

## Verification (no code change)

- [ ] T009 MinUtxoSpec parity (rdf#81): byte-identical at baseline, locked by gate extension; recorded in PR body

# 154 — Restore the TxBuild mainnet golden suite

Issue: lambdasistemi/cardano-tx-tools#154. Base: `main@7bfe95b`.

## User stories

- **US1** A maintainer changing `Cardano.Tx.Build` gets a red `unit`
  check when `draft` or offline `build` stops reproducing a real
  mainnet Conway transaction committed under
  `test/fixtures/mainnet-txbuild/`.
- **US2** A maintainer changing the Conway certificate or proposal
  builders gets a red `unit` check when `registerAndVoteAbstain` or
  `proposeTreasuryWithdrawal` stops matching the cardano-cli CBOR in
  `test/fixtures/mainnet-txbuild/conway-042/`.

## Requirements

- **R1** The `unit-tests` suite contains a describe group
  `TxBuild mainnet golden vectors` with one example per committed
  `test/fixtures/mainnet-txbuild/<txid>.cbor.hex` (14 today). Each
  example decodes the fixture, reconstructs a `TxBuild` program from
  it, and checks `draft` and offline `buildWith` (with the
  `inputs/<txid>.inputs` input coins) against the fixture.
- **R2** The same suite contains a describe group
  `TxBuild Conway CLI artifact parity` with the two cardano-cli parity
  examples of the original suite (certificate CBOR, proposal CBOR).
- **R3** The assertions are those of the original suite
  (`cardano-node-clients@38fc191^:test/Cardano/Node/Client/TxBuildGoldenSpec.hs`)
  unless a deviation is listed and justified in the PR body.
- **R4** The suite is compiled and executed by the `unit` CI check.

## Invariants (failure ⇒ red)

- **I1** Every `<txid>.cbor.hex` directly under
  `test/fixtures/mainnet-txbuild/` is exercised by exactly one golden
  example, and every exercised fixture has its `inputs/<txid>.inputs`.
  A fixture added to the directory without coverage, or a covered
  fixture missing, makes the suite red (or is covered automatically);
  the set the suite ranges over is never empty.
- **I2** Each golden example fails when `draft`'s reconstruction of the
  fixture differs from the fixture in any field the original
  `assertStructurallyEquivalent` compared (inputs, collateral inputs,
  reference inputs, outputs, mint, withdrawals, required signers,
  validity interval, metadata, witness scripts, redeemer purposes and
  data).
- **I3** Each golden example fails when the offline `buildWith` result
  differs in any field the original
  `assertBalancedStructurallyEquivalent` compared (above plus: one
  extra change output at the selected change address with no datum,
  fee > 0, redeemer ExUnits).
- **I4** The two parity examples fail when the built certificate /
  proposal differs from the decoded `conway-042` artifact.
- **I5** The suite can fail: a perturbation of `Cardano.Tx.Build`
  behaviour and a perturbation of one fixture byte each turn at least
  one example red (evidence recorded, not committed).
- **I6** No change to `src-tx-build/` behaviour, to any fixture file,
  or to the main library's dependencies.

## Non-goals

New fixtures; builder fixes; CI workflow changes (#155).

## Observable success

Acceptance rows 1–4 of the ticket brief, each bound to a CI command in
the frozen gate.

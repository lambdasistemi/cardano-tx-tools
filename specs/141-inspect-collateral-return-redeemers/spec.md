# 141 — tx-inspect / tx-diff: render collateralReturn and redeemers

Issue: lambdasistemi/cardano-tx-tools#141. Base: `main@7bfe95b`.

## User stories

- **US1** An operator running `tx-inspect` on a Conway tx sees the
  collateral-return output (address and value, ADA plus native assets)
  next to `collateralInputs` and `totalCollateral`.
- **US2** An operator running `tx-inspect --witnesses` sees every
  redeemer the tx carries: purpose tag, index, Plutus data, ExUnits —
  enough to answer "which validator action does this tx invoke".
- **US3** An operator running `tx-diff` on two txs that differ only in
  `collateralReturn` sees that difference; with `--witnesses`, two txs
  that differ only in a redeemer show that difference.

## Requirements

- **R1** The body projection walked by `tx-inspect` and `tx-diff`
  carries a `collateralReturn` child (Conway body key 16).
- **R2** A present `collateralReturn` renders through the same output
  projection as an entry of `outputs`: address, coin, assets, datum,
  referenceScript. Rename rules apply to its address exactly as to an
  `outputs` entry's address.
- **R3** An absent `collateralReturn` renders as an explicit absent
  leaf, the same way an absent `totalCollateral` renders today. It is
  never silently omitted.
- **R4** `tx-inspect` and `tx-diff` each accept `--witnesses`. With it,
  the existing witness-set projection (`witnesses` node: bootstraps,
  datums, redeemers, scripts, vkeys) is rendered. Without it, output is
  byte-identical to the pre-ticket behaviour apart from R1–R3.
- **R5** `docs/tx-inspect.md` and `docs/tx-diff.md` document
  `--witnesses` (usage synopsis and a section), and the
  `collateralReturn` node, in the same diff.
- **R6** Each tool's `--help` lists `--witnesses`.

## Invariants (failure ⇒ red)

- **I1** For a fixture tx whose body carries `collateralReturn`, the
  `tx-inspect` render contains a `collateralReturn` node whose address
  and value equal the decoded body's collateral-return output
  (including at least one native asset when the fixture's output has
  one).
- **I2** For a fixture tx with Plutus redeemers, `tx-inspect
  --witnesses` shows, for every redeemer, its purpose tag, index, data
  and ExUnits; the redeemer count in the render equals the decoded
  count.
- **I3** `tx-diff` on two txs differing only in `collateralReturn`
  reports a difference located under `body.collateralReturn`.
- **I4** `tx-diff --witnesses` on two txs differing only in one
  redeemer reports a difference located under `witnesses.redeemers`;
  without `--witnesses` the same pair still reports no difference
  (default surface is body-only, unchanged).
- **I5** Every pre-existing golden diff introduced by this ticket is
  an addition of `collateralReturn` lines only; no existing line is
  removed or rewritten.
- **I6** `tx-graph` output (RDF emission) for every existing fixture is
  byte-identical to the base.
- **I7** A rename rule matching the collateral-return address renames
  it in the `collateralReturn` node.

## Rejection / non-goals

- Witnesses do not render by default (see plan.md D1).
- No redesign of vkey/bootstrap witness rendering; no rename inside
  datum subtrees (#39); no new rename kinds (#34–#38).
- The library keeps no node-client dependency.

## Observable success

Acceptance rows A1–A5 of the ticket brief, each bound to a CI command
in the frozen gate.

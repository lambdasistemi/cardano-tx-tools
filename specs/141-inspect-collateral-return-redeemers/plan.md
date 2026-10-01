# Plan — 141

## Decisions

- **D1 Redeemers behind `--witnesses`, default off, on both tools.**
  Reason: the witness projection already exists (`ConwayWitnessesValue`,
  `Diff.hs:2601`) and is gated by `txDiffIncludeWitnesses` (default
  False). Defaulting it on would (a) dump full Plutus script CBOR and
  vkey signatures into every inspect render and (b) make `tx-diff`
  report signature differences between an unsigned and a signed build
  of the same tx — a semantic change to tx-diff's default surface.
  An opt-in flag mirrors the existing `--links` precedent ("default
  off; existing render is byte-stable"). Rejected: default-on for
  tx-inspect only (asymmetric surfaces between the two tools that share
  one renderer).
- **D2 collateralReturn reuses the output projection**, so rename rules,
  native-asset rendering (`f41c357`) and datum rendering apply without a
  second code path.
- **D3 tx-graph unchanged.** It has its own collateral-return
  projection (`Graph/Emit/Project.hs`); its output must not move (I6).

## Live boundaries

None (pure decode + render). Resolver flags unaffected.

## Slices

One bisect-safe OWNER slice **S1** covering R1–R6 / I1–I7: library
projection change, CLI flags, unit tests, smoke/golden updates, docs.

## Constraints

- Golden changes justified line-by-line in the PR body (additions only).
- Conventional commits; no AI attribution; no runtime IDs in commits.

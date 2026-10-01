# Plan — 154

## Decisions

- **D1 Port, don't redesign.** The original 652-line suite is the
  reference; adaptation is limited to module renames
  (`Cardano.Node.Client.TxBuild` → `Cardano.Tx.Build`,
  `Cardano.Node.Client.Balance` → `Cardano.Tx.Balance`,
  `Cardano.Node.Client.Ledger` → `Cardano.Tx.Ledger`) and ledger API
  drift since the split (e.g. `ConwayTx = Tx TopTx ConwayEra`).
- **D2 Coverage is quantified over the directory (I1).** The 14
  fixtures equal the 14 cases of the original suite (verified at
  planning: identical hash sets). Human-readable case names may be
  kept; the fixture-set/case-set agreement is asserted, not assumed.
- **D3 A fixture failing for a real builder regression is not fixed
  here.** It is reported upward with evidence before any relaxation.

## Live boundaries

None. Pure decode + offline build against synthesised UTxO.

## Slices

One bisect-safe OWNER slice **S1** covering R1–R4 / I1–I6.

## Constraints

- Conventional commits; no AI attribution; no runtime IDs in commits.
- Deviations from the original suite enumerated in the PR body.

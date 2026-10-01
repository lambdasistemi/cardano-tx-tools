# Functions model — 141

No new exported function is required. Changed behaviour only:

- **F1** `conwayDiffProjection :: TxDiffOptions -> ConwayDiffValue ->
  DiffProjection ConwayDiffValue` — body case yields D-1. Signature
  unchanged.
- **F2** If a new `ConwayDiffValue` constructor is introduced to carry
  `StrictMaybe (TxOut ConwayEra)`, it must be registered wherever the
  constructor set is enumerated (e.g. the tx-graph exhaustivity hand
  list) without changing tx-graph output (I6).

# Data model — 141

- **D-1** Body projection children (M1): existing set plus
  `collateralReturn :: StrictMaybe (TxOut ConwayEra)`; `SJust` projects
  as the same value an `outputs` element projects as; `SNothing`
  projects as the same absent leaf `totalCollateral` uses.
- **D-2** tx-inspect CLI options (M2): gains one Boolean witness-
  inclusion field, default False, set by `--witnesses`.
- **D-3** tx-diff CLI options (M3): same as D-2.
- **D-4** `TxDiffOptions.txDiffIncludeWitnesses` (existing): unchanged
  type and default; now reachable from both CLIs.

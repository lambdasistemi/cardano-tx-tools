# Modules model — 141

- **M1 `Cardano.Tx.Diff`** (library): owns the Conway projection. Gains
  the `collateralReturn` body child (R1–R3). No new dependency.
  Dependency direction unchanged: executables → library.
- **M2 `app/tx-inspect/Main.hs`**: owns the tx-inspect CLI surface;
  gains `--witnesses`, mapped to the library option
  `txDiffIncludeWitnesses` (R4, R6). See data-model D-2.
- **M3 tx-diff CLI module** (wherever tx-diff's option parser lives):
  same as M2 for tx-diff (R4, R6). See data-model D-3.
- **M4 docs** `docs/tx-inspect.md`, `docs/tx-diff.md` (R5).
- **M5 `Cardano.Tx.Graph.Emit*`**: untouched (D3, I6).

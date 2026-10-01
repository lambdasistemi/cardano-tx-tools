# Modules model — 154

- **M1 `Cardano.Tx.Build.GoldenSpec`** (`test/Cardano/Tx/Build/GoldenSpec.hs`,
  test-only): owns R1, R2, I1–I4. Consumes the `tx-build` sublibrary
  public API only (`Cardano.Tx.Build`, `Cardano.Tx.Balance`,
  `Cardano.Tx.Ledger`). Dependency direction: test → sublibrary.
- **M2 `test/unit-main.hs`, `cardano-tx-tools.cabal` (`unit-tests`)**:
  register M1 (R4). Test-suite `build-depends` may grow only if M1
  needs a package the original suite used; the main library's
  dependencies do not change (I6).
- **M3 `src-tx-build/`**: untouched (I6).

# cardano-tx-tools-issue-8 Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-05-15

## Active Technologies
- Haskell, GHC 9.12.3 via `haskell.nix` (constitution Operational Constraints). + `cardano-ledger-api`, `cardano-ledger-conway`, `cardano-ledger-core`, `cardano-ledger-shelley` (new direct dep — for `Cardano.Ledger.Shelley.API.Mempool` and the `NewEpochState` `Default` instance), `cardano-ledger-alonzo`, `cardano-ledger-mary`, `cardano-slotting`, `microlens`, `data-default` (new direct dep — for `def :: NewEpochState ConwayEra`). (014-validate-phase1)
- N/A. Pure function. Test fixtures on disk under `test/fixtures/`. (014-validate-phase1)

- Haskell, GHC 9.12.3 via `haskell.nix` (`compiler-nix-name = "ghc9123"`, constitution Operational Constraints). (008-txbuild-integrity-hash)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Haskell, GHC 9.12.3 via `haskell.nix` (`compiler-nix-name = "ghc9123"`, constitution Operational Constraints).

## Code Style

Haskell, GHC 9.12.3 via `haskell.nix` (`compiler-nix-name = "ghc9123"`, constitution Operational Constraints).: Follow standard conventions

## Recent Changes
- 014-validate-phase1: Added Haskell, GHC 9.12.3 via `haskell.nix` (constitution Operational Constraints). + `cardano-ledger-api`, `cardano-ledger-conway`, `cardano-ledger-core`, `cardano-ledger-shelley` (new direct dep — for `Cardano.Ledger.Shelley.API.Mempool` and the `NewEpochState` `Default` instance), `cardano-ledger-alonzo`, `cardano-ledger-mary`, `cardano-slotting`, `microlens`, `data-default` (new direct dep — for `def :: NewEpochState ConwayEra`).

- 008-txbuild-integrity-hash: Added Haskell, GHC 9.12.3 via `haskell.nix` (`compiler-nix-name = "ghc9123"`, constitution Operational Constraints).

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->

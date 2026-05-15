# Implementation Plan: TxBuild self-validates against ledger Phase-1

**Branch**: `008-txbuild-integrity-hash` | **Date**: 2026-05-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/008-txbuild-integrity-hash/spec.md`

## Summary

Make the ledger's Phase-1 application function (`applyTx` / `Cardano.Ledger.Api.Tx.applyTx` from `cardano-ledger-api`) a mandatory step inside `Cardano.Tx.Build`'s build/finalize path. The same `PParams` value drives fee estimation, exec-units, integrity-hash computation, and the self-validation step — threaded structurally as a single argument, never re-fetched. The existing `script_integrity_hash` divergence is fixed as one instance the new gate catches.

Bug-level technical approach for the integrity hash itself:

- `computeScriptIntegrity` (`src/Cardano/Tx/Scripts.hs:84`) currently takes a single `Language` and a `Redeemers ConwayEra` and folds in one `LangDepView`. The Conway witness set serializes redeemers as a map; verify `hashScriptIntegrity` from `Cardano.Ledger.Alonzo.Tx` follows the body's CBOR serialization (Conway map form, witness-set key `5`). If it does not, switch to the Conway-era `hashScriptIntegrity` from `Cardano.Ledger.Conway` / `Cardano.Ledger.Api`.
- Replace the single-`Language` argument with the *set* of languages actually referenced by redeemers in the body, derived from the body itself — never from caller convention. All three current call sites in `src/Cardano/Tx/Build.hs` (lines 1042, 1288, 1774) hardcode the literal `PlutusV3`.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (`compiler-nix-name = "ghc9123"`, constitution Operational Constraints).
**Primary Dependencies**:
- `cardano-ledger-conway` — already in closure.
- `cardano-ledger-alonzo` — `hashScriptIntegrity`, `ScriptIntegrity`, `LangDepView`, `getLanguageView`.
- `cardano-ledger-api` — `applyTx` (or equivalent Phase-1 functional path) for self-validation.
- `cardano-ledger-core` — `PParams`, `ApplyTxError`.
- All already pulled in via the existing `Cardano.Tx.*` source tree; no new `source-repository-package` entries expected.
**Storage**: N/A. `Cardano.Tx.Build` is a pure assembly layer.
**Testing**: `hspec`. New tests live in `test/Cardano/Tx/BuildSpec.hs` (new file) and `test/Cardano/Tx/ScriptsSpec.hs` (new file). Fixtures under `test/fixtures/`.
**Target Platform**: Linux x86_64 (same as repo CI).
**Project Type**: Haskell library (`cardano-tx-tools`, exposed modules under `Cardano.Tx.*`).
**Performance Goals**: One additional `applyTx` call per build (a few ms against an in-memory UTxO). Not a hot path; well within `nix flake check` budget.
**Constraints**:
- Same `PParams` instance threaded through the whole build call. Structural, not by convention — single argument.
- Self-validation runs against the UTxO TxBuild already has in scope; no new network query.
- Failure must surface the ledger's `ApplyTxError` faithfully to the caller.
- Default-offline (constitution VI): the test suite must not touch the network.
**Scale/Scope**: Two source modules touched (`src/Cardano/Tx/Build.hs`, `src/Cardano/Tx/Scripts.hs`), two new test specs, plus golden fixtures for the mainnet reproduction.

## Constitution Check

| Principle | Status | Notes |
|---|---|---|
| I. One-Way Dependency On Node-Clients | PASS | Fix lives entirely in `Cardano.Tx.*`. No reverse imports from `cardano-node-clients` introduced. The ledger Phase-1 function comes from `cardano-ledger-api` directly. |
| II. Module Namespace Discipline | PASS | All touched / added modules under `Cardano.Tx.*`. |
| III. Conway-Only Era | PASS | Spec, fixtures, and tests target Conway exclusively. |
| IV. Hackage-Ready Quality | PASS | No public-API surface change planned beyond adding constructors / type parameters within the existing `LedgerCheck` story. Haddock + module-header updates are in Phase 5. |
| V. Strict Warnings | PASS | No new flags. |
| VI. Default-Offline Semantics | PASS | The regression test reads `test/fixtures/pparams.json` + on-disk UTxO + on-disk tx body; no LSQ / HTTPS at test time. |
| VII. TDD Vertical Bisect-Safe Commits | PASS | tasks.md groups RED + GREEN into single commits per behavior change. No "added tests" follow-up commits. |
| Build And Test Toolchain (`nix flake check`) | PASS | New tests run inside the existing `cabal test-suite`, invoked via `nix flake check --no-eval-cache`. |
| Release Hygiene (rebase merge, conventional commits) | PASS | Standard. |

No violations; Complexity Tracking section is empty.

## Project Structure

### Documentation (this feature)

```text
specs/008-txbuild-integrity-hash/
├── plan.md                       # This file
├── spec.md
├── checklists/
│   └── requirements.md
├── research.md                   # Phase 0 output
├── data-model.md                 # Phase 1 output
├── quickstart.md                 # Phase 1 output
├── contracts/                    # Phase 1 output
│   └── txbuild-self-validation.md
└── tasks.md                      # /speckit.tasks output
```

### Source Code (repository root)

```text
src/Cardano/Tx/
├── Build.hs          # Integrate Phase-1 self-validation at the return
│                     # point. Thread the single PParams arg via
│                     # PParamsBound. Extend LedgerCheck.
├── Scripts.hs        # Fix `computeScriptIntegrity`: accept Set Language
│                     # derived from the body, accept witness-set datums,
│                     # use the Conway-era hashScriptIntegrity if needed.
├── Balance.hs        # PParams flows through fee estimation; confirm
│                     # same value is passed to self-validation.
├── Inputs.hs / Witnesses.hs / Deposits.hs / Credentials.hs / Ledger.hs
│                     # Likely untouched; confirm no PParams source
│                     # is re-fetched here.

test/Cardano/Tx/
├── BuildSpec.hs             # NEW. Golden tests for self-validation
│                            # (positive + negative + mainnet repro).
├── ScriptsSpec.hs           # NEW. Focused integrity-hash tests over
│                            # Conway redeemers + mixed langs.

test/fixtures/
├── pparams.json             # ALREADY COMMITTED (from tx-diff migration).
│                            # Reused as the mainnet snapshot for the
│                            # swap-cancel reproduction.
└── mainnet-txbuild/
    └── swap-cancel-issue-8/  # NEW fixture dir
        ├── utxo.json         # 3 inputs: 2 spend + 1 reference, captured
        │                     # from mainnet via this repo's resolver or
        │                     # an LSQ one-off (default-offline at test time).
        ├── plan.hs           # The exact TxBuild plan
        └── body.cbor.hex     # The failing body
                              # (copied from /code/cancel.cbor.hex).
```

**Structure Decision**: stay within the existing `cardano-tx-tools` Haskell library layout. No new top-level directories. Self-validation is exposed as a small public helper (so consumers can use it too if they ever construct bodies by hand), but the build/finalize path calls it unconditionally.

## Phase 0: Outline & Research

See [research.md](./research.md) for the six items closed before implementation (R-001…R-006). Summary:

- R-001: `Cardano.Ledger.Api.Tx.applyTx` is the Phase-1 entry point.
- R-002: keep `Cardano.Ledger.Alonzo.Tx.hashScriptIntegrity`; T011 golden-vector check decides whether a Conway swap is needed.
- R-003: body-derived `Set Language` via `languagesUsedInBody` helper. All three call sites currently hardcode `PlutusV3`.
- R-004: add `PParamsBound era` newtype.
- R-005: `test/fixtures/pparams.json` already committed in this repo (from tx-diff migration); reuse. Verify epoch alignment with the failing tx's slot at T011.
- R-006: UTxO for `applyTx` = `inputUtxos ∪ boCollateralUtxos ∪ refUtxos` already in scope at `buildWith` (`src/Cardano/Tx/Build.hs:1250`).

## Phase 1: Design & Contracts

**Prerequisites**: `research.md` complete.

### Data model

See [data-model.md](./data-model.md). Two additions: `PParamsBound era` newtype; `Phase1Rejected (ApplyTxError era)` constructor on `LedgerCheck`. One signature change to `computeScriptIntegrity`. One new helper `languagesUsedInBody`.

### Contracts

See [contracts/txbuild-self-validation.md](./contracts/txbuild-self-validation.md). Seven invariants C-1..C-7.

### Quickstart

See [quickstart.md](./quickstart.md). Caller usage, swap-cancel reproduction recipe, negative-test recipe.

### Agent context update

Run `./.specify/scripts/bash/update-agent-context.sh claude` after Phase 1 to refresh `CLAUDE.md`.

**Outputs**: `data-model.md`, `contracts/txbuild-self-validation.md`, `quickstart.md`, `CLAUDE.md` updated.

## Phase 2: Tasks (preview — generated by /speckit.tasks)

Sketch only:

1. Phase 1 — closing research items (no code).
2. Phase 2 — fixtures (`test/fixtures/mainnet-txbuild/swap-cancel-issue-8/{body.cbor.hex, utxo.json}`).
3. Phase 3 (US1 MVP) — per constitution VII, each behavior change ships as ONE commit with both RED and GREEN:
   - Hash fix: signature change + body-derived language set + Conway redeemers, with the mainnet-#8 golden test added in the same commit.
   - Self-validation: `Phase1Rejected`, `PParamsBound`, the `applyTx` hook in `buildWith`'s return path, and the negative test, all in one commit.
   - Property test for edge cases as a separate commit.
4. Phase 4 (US2) — close the companion `amaru-treasury-tx` ticket; verify consumers carry no duplicate gate.
5. Phase 5 — Haddock, PR description, final `nix flake check`.

## Complexity Tracking

No constitution violations; section intentionally empty.

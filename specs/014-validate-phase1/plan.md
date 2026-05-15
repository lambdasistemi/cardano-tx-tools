# Implementation Plan: Phase-1 pre-flight for unsigned transactions

**Branch**: `014-validate-phase1` | **Date**: 2026-05-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/014-validate-phase1/spec.md`

## Summary

Add a pure Haskell function `validatePhase1` that runs the ledger's
Conway Phase-1 rule (UTXOW + LEDGER via `Mempool.applyTx`) against
an unsigned `ConwayTx`, given a `NetworkId`, a `PParamsBound`, the
caller-resolved input/reference-input UTxO, and a slot. Returns
`Either (ApplyTxError ConwayEra) ()` with the ledger's full failure
list (witness-completeness failures included; caller filters at
their end).

The recipe (synthesise `Globals`, seed `NewEpochState`, call
`Mempool.mkMempoolEnv`/`mkMempoolState`/`applyTx`) is duplicated
from
[`cardano-ledger-inspector`'s `Conway.Inspector.Validation`](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs)
per the explicit decision in
[spec.md "Implementation strategy"](./spec.md#implementation-strategy);
no cross-repo dependency. The new module's Haddock header cites the
upstream as the canonical reference.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (constitution Operational Constraints).
**Primary Dependencies**: `cardano-ledger-api`, `cardano-ledger-conway`, `cardano-ledger-core`, `cardano-ledger-shelley` (new direct dep — for `Cardano.Ledger.Shelley.API.Mempool` and the `NewEpochState` `Default` instance), `cardano-ledger-alonzo`, `cardano-ledger-mary`, `cardano-slotting`, `microlens`, `data-default` (new direct dep — for `def :: NewEpochState ConwayEra`).
**Storage**: N/A. Pure function. Test fixtures on disk under `test/fixtures/`.
**Testing**: `hspec` via the existing `unit-tests` test-suite (already wired in `cardano-tx-tools.cabal`).
**Target Platform**: `nix flake check` on `x86_64-linux` (and Darwin if the flake fans out; check the existing flake).
**Project Type**: Single Haskell library (`src/`, `test/`).
**Performance Goals**: Not load-bearing. One call per tx; the cost is one ledger STS evaluation against a tiny synthesised state.
**Constraints**: Default-offline (constitution VI). No network at test time. No `cardano-node-clients` import (constitution I — `Cardano.Tx.Validate` stays in the inner ring).
**Scale/Scope**: ~60-line kernel + ~30-line `loadUtxo` JSON helper + ~150-line spec test file. One new public function on the library's public surface.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. One-Way Dependency On Node-Clients | ✅ | New `Cardano.Tx.Validate` module imports only `cardano-ledger-*` and `cardano-slotting`. No `cardano-node-clients`, no N2C. |
| II. Module Namespace Discipline | ✅ | New module is `Cardano.Tx.Validate`. No `Cardano.Node.Client.*` introduced. |
| III. Conway-Only Era | ✅ | Function signature is `ConwayTx → Either (ApplyTxError ConwayEra) ()`. Hardcoded to Conway era. |
| IV. Hackage-Ready Quality | ✅ | Haddock on the new export; module header in canonical `{- &#124; … -}` form citing upstream; `cabal check` to pass (the `werror` flag pattern is already in place). |
| V. Strict Warnings | ✅ | Inherits the library's existing `-Wall -Werror …` block via `import: warnings`. |
| VI. Default-Offline Semantics | ✅ | The function is pure (no `IO`); the test suite uses on-disk fixtures only. `loadUtxo` reads from disk; no HTTPS, no LSQ. |
| VII. TDD With Vertical Bisect-Safe Commits | ✅ | One commit per behavior slice (kernel + first happy-path test together; negative test + fixture together; etc.). No "added tests" follow-ups. |
| Resolver Architecture (Operational) | ✅ | This feature does not add a resolver. The UTxO list is caller-supplied, matching constitution VI's "no silent fallback to remote sources." |

No violations to track in the Complexity Tracking table.

## Project Structure

### Documentation (this feature)

```text
specs/014-validate-phase1/
├── plan.md              # This file
├── research.md          # Phase 0 output (this command)
├── data-model.md        # Phase 1 output (this command)
├── quickstart.md        # Phase 1 output (this command)
├── contracts/
│   └── validate-phase1.md   # Public-surface contract
├── checklists/
│   └── requirements.md  # Created during /speckit.specify
├── spec.md              # /speckit.specify output
└── tasks.md             # /speckit.tasks output (NOT created here)
```

### Source Code (repository root)

```text
src/Cardano/Tx/
├── Validate.hs              # NEW — validatePhase1 + Globals synthesis + NewEpochState seeding
└── (existing modules unchanged)

test/
├── Cardano/Tx/
│   └── ValidateSpec.hs      # NEW — hspec coverage of validatePhase1 (Stories 1 & 2 from spec)
├── Cardano/Tx/Validate/
│   └── LoadUtxo.hs          # NEW — test-only helper, parses cardano-cli JSON UTxO
└── fixtures/
    ├── pparams.json         # EXISTING — reuse
    ├── mainnet-txbuild/     # EXISTING — pre-fix and post-fix issue-#8 unsigned bodies
    │   ├── post-fix-tx.cbor.hex
    │   ├── pre-fix-tx.cbor.hex
    │   └── utxo.json        # NEW — captured cardano-cli `query utxo` output for the fixture's TxIns
```

**Structure Decision**: Single-project Haskell library. `validatePhase1` lives in a new `Cardano.Tx.Validate` module (NOT extending `Cardano.Tx.Ledger`, which stays minimal as a `ConwayTx` type-alias module per its current Haddock). `LoadUtxo` is a test-only helper, not exposed from the library — per constitution II we don't ship test scaffolding on the public surface, and per FR-009 the helper is local to `test/`.

## Phase 0 — Research

Five concrete unknowns to resolve before writing code; documented in detail in [research.md](./research.md):

1. **`Mempool.applyTx` entry point at the pinned `cardano-ledger-shelley` version** — confirm the signature `applyTx :: Globals -> LedgerEnv era -> MempoolState era -> CoreTx era -> Except (ApplyTxError era) (MempoolState era, Validated (CoreTx era))` holds. Inspector uses this verbatim against a slightly newer index-state; our `index-state` is `2026-02-17` so we re-verify.
2. **`NewEpochState ConwayEra` `Default` instance** — comes from `cardano-ledger-shelley`'s `Cardano.Ledger.Shelley.LedgerState`. Confirm exposure at the pinned version.
3. **`Globals` constants** — copy the inspector recipe verbatim. The constants (k=2160, slot length 1s, epoch size 432000, active-slots-coeff 1/20, max-lovelace-supply 45 × 10¹⁵, max-KES-evolutions 62, quorum 5) are network-invariant; the only network-parameterised field is `networkId`.
4. **UTxO JSON shape from `cardano-cli query utxo`** — pin to the schema cardano-cli emits at the era we're targeting (Conway). Decide whether to use the per-input shape (`{ "txhash#index": { "address": ..., "value": {...}, "datumhash": ..., "inlineDatum": ..., "referenceScript": ... } }`) or a more compact custom JSON. Recommendation: parse the cardano-cli shape exactly; the host can pipe `cardano-cli query utxo` output directly into the test helper.
5. **Cert-state seeding — required for this PR?** Inspector's `seedCertStateRewards` exists for withdraw-zero validation patterns (SundaeSwap, Indigo, Minswap V2). The issue-#8 reproduction has no withdrawals. Decide: ship cert-state seeding now (parity with inspector, future-proof), or land minimal and add later (smaller PR, RED+GREEN folds tighter). Recommendation: **defer**. The first version covers the bug class issue #14 cares about; cert-state seeding lands when a withdrawal-bearing test fixture motivates it.

## Phase 1 — Design & Contracts

### Public API contract

See [contracts/validate-phase1.md](./contracts/validate-phase1.md). The function:

```haskell
{- |
Module      : Cardano.Tx.Validate
Description : Conway Phase-1 pre-flight against ledger applyTx.
License     : Apache-2.0

Recipe duplicated from
[cardano-ledger-inspector](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs)
per spec 014 "Implementation strategy". See upstream consolidation
ticket lambdasistemi/cardano-ledger-inspector#73.
-}
module Cardano.Tx.Validate
    ( validatePhase1
    , -- exported for caller filtering convenience; see Haddock
      isWitnessCompletenessFailure
    ) where

validatePhase1
    :: BaseTypes.Network
    -> PParamsBound
    -> [(TxIn, TxOut ConwayEra)]
    -> SlotNo
    -> ConwayTx
    -> Either (ApplyTxError ConwayEra) ()
```

`isWitnessCompletenessFailure :: ConwayLedgerPredFailure ConwayEra -> Bool` is the helper FR-010 calls for: it answers "is this failure constructor part of the expected witness-completeness noise on an unsigned tx?" Caller filter logic becomes a one-liner: `filter (not . isWitnessCompletenessFailure)`.

The noise constructors enumerated (per FR-010, locked in by SC-004):

- `ConwayUtxowFailure (MissingVKeyWitnessesUTXOW _)` — required signers without vkey witnesses.
- `ConwayUtxowFailure (MissingScriptWitnessesUTXOW _)` — native-script witnesses missing. (Strict reading: native scripts that *require* a signature; the field surfaces the script hashes.)
- `ConwayUtxowFailure (MissingTxBodyMetadataHash _)` / `MissingTxMetadata _` — metadata-hash consistency. Borderline noise: only fires if the tx claims metadata; the unsigned-vs-signed dimension doesn't affect it. **Decision per Phase 0**: do NOT mark these as noise; if the tx body declares an aux-data hash, both the unsigned and signed paths trip them, so the failure is genuinely structural.
- *(Phase 0 to confirm the exact constructor names against the pinned ledger version.)*

### Data model

See [data-model.md](./data-model.md). The only new typed surface is the function signature; no new data types are introduced in this PR (cert-state seeding deferred per Phase 0 research item 5).

### Quickstart for callers

See [quickstart.md](./quickstart.md). Three-step caller workflow:

1. Build the tx with `buildWith pp utxo slot plan`.
2. Run `validatePhase1 net pp utxo slot tx`.
3. Pattern-match the result; filter witness-completeness noise via `isWitnessCompletenessFailure`; if anything remains, fail the pipeline before signing.

### Agent context update

Will run `.specify/scripts/bash/update-agent-context.sh claude` after this plan lands to refresh `CLAUDE.md` with the feature's technology marker. Mechanical; no manual edits inside markers.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

None. The Constitution Check passes outright.

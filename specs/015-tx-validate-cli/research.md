# Phase 0 Research: tx-validate CLI

**Feature**: 015-tx-validate-cli
**Date**: 2026-05-16
**Status revision**: 2026-05-16 — Blockfrost-side items deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

## R1. `Provider` accessors at the pinned `cardano-node-clients`

**Decision**: use `Cardano.Node.Client.Provider.queryProtocolParams`, `queryUTxOByTxIn`, and `queryLedgerSnapshot` exactly as `amaru-treasury-tx`'s [`liveContext`](https://github.com/lambdasistemi/amaru-treasury-tx/blob/main/lib/Amaru/Treasury/ChainContext.hs#L130-L162) does. Tip slot is `ledgerTipSlot snapshot`.

**Rationale**: this is the canonical N2C-driving pattern across our toolkit. Inspector duplicates a JSON-shaped variant of the same recipe; `tx-tools`' existing `Cardano.Tx.Diff.Resolver.N2C` uses the typed form.

**Re-verification path**: open `Cardano.Node.Client.Provider` in the resolved build plan, confirm the three function signatures. The pin in `cabal.project` is the one PR #16 used; we are not bumping it.

## R2. *(deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))*  Blockfrost pparams schema

The first plan draft claimed `cardano-ledger-conway`'s `FromJSON (PParams ConwayEra)` instance would decode Blockfrost's `GET /epochs/latest/parameters` response. False: Blockfrost emits a flat snake_case schema (`a0`, `e_max`, `cost_models_raw`, `dvt_p_p_*`, `gov_action_deposit`, …) that the instance cannot consume — the instance expects the cardano-cli-shaped object. A custom decoder is needed; that work moved to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

## R3. *(deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))*  Blockfrost tip-slot fetcher

Same reason — out of scope without the Blockfrost session.

## R4. *(deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))*  HTTP fetcher record-of-functions

Same reason.

## R5. N2C session lifecycle

**Decision**: a `withSession` bracket that owns the N2C connection's lifetime:

```haskell
data Session = Session
    { sessionNetwork       :: Network
    , sessionPParams       :: PParams ConwayEra
    , sessionSlot          :: SlotNo
    , sessionUtxoResolvers :: [Resolver]         -- [n2cResolver provider] in v1
    }

withSession ::
    TxValidateCliOptions ->
    (Session -> IO a) ->
    IO a
```

The bracket opens the LSQ + LTxS mux against the cardano-node socket, queries `PParams` + tip slot, builds the `n2cResolver`, runs the action with the immutable `Session` in scope, then tears down the mux.

**Rationale**: mirrors `amaru-treasury-tx`'s `withLiveContext`.

## R6. Resolver chain ordering (v1 degenerate)

**Decision**: chain is `[n2cResolver]`. The `resolveChain` infrastructure is preserved unchanged; in v1 it always sees one entry.

**Rationale**: keeps the code structure aligned with the future shape from [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21), so the second resolver can slot in without restructuring.

## R7. JSON output envelope

**Decision**: see [contracts/json-output.md](./contracts/json-output.md). Top-level keys: `status`, `exit_code`, `structural_failures`, `witness_completeness_count`, `pparams_source`, `slot_source`, `utxo_sources`.

In v1 the source fields will all be `"n2c"`; we keep them in the envelope for forward-compat.

## R8. Release plumbing

**Decision**: extend `flake.nix` with:

- `txValidate` symlink-join wrapper (mirrors `txDiff`). For v1 the CA-cert injection isn't strictly needed (N2C is a local socket, no HTTPS), but we keep the wrapper so the future Blockfrost path inherits it without restructuring.
- `mkTxValidateDarwinHomebrewBundle` (mirrors `mkTxDiffDarwinHomebrewBundle`).
- `tx-validate-linux-release-artifacts` + `tx-validate-linux-dev-release-artifacts` (mirrors `linux-release-artifacts` / `linux-dev-release-artifacts`).
- A `tx-validate-image` docker image (mirrors `cardano-tx-generator-image`).
- `apps.tx-validate` for `nix run .#tx-validate`.
- Extend `linux-artifact-smoke` to smoke-test the `tx-validate` AppImage.

**Rationale**: copy-paste of the existing `tx-diff` plumbing — minimal new abstraction; trivially reviewable.

---

## Open items for `/speckit.tasks`

None left after the Blockfrost deferral. Two genuine "happens during implementation" callouts:

- R1 re-verification: confirm `queryLedgerSnapshot` is exposed on the pinned `cardano-node-clients`. If the symbol moved, the failure is a compile error (bisect-safe).
- Mock-`Provider` shape for tests: confirm `Cardano.Tx.Diff.Resolver.N2C`'s unit tests already provide a record-of-functions stub that the new test-suite can re-use. If not, ship one in T002 alongside the session-driver implementation.

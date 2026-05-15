# Research: TxBuild self-validates against ledger Phase-1

**Branch**: `008-txbuild-integrity-hash` | **Date**: 2026-05-15
**Plan**: [plan.md](./plan.md)

Phase-0 design questions, each closed before any code lands.
Decision / Rationale / Alternatives. Source-reading evidence was
done in the predecessor branch
[cardano-node-clients#154](https://github.com/lambdasistemi/cardano-node-clients/pull/154);
line numbers carry over because the migration to this repo (commit
`22d0001`) renamed the modules but kept the file contents
identical.

---

## R-001: Which ledger function exposes Phase-1 validation?

**Status**: RESOLVED (2026-05-15)

**Decision**: `Cardano.Ledger.Api.Tx.applyTx` from
`cardano-ledger-api`. It performs the full UTXOW transition,
which includes the `script_integrity_hash` check, fee /
min-utxo / collateral checks, and witness completeness; under
Phase-1 it does **not** execute Plutus scripts — script
evaluation happens in a separate Phase-2 function. This is the
entry point the plan calls out and the one already used by the
wider ecosystem for offline tx validation.

**Rationale**: smallest API surface that fully matches FR-003
("ledger Phase-1 on its own output"), already in the closure,
and behaves the same way as the node at submission time.

**Alternatives considered**:
- `reapplyTx` — re-applies an already-validated tx; may skip
  checks we care about. Rejected.
- `Cardano.Ledger.Shelley.Rules.UTXOW` via `applyRuleByName` /
  `runRule` — lower-level, same semantics but more boilerplate.
  Rejected.
- A bespoke Phase-1 reimplementation in this repo — rejected on
  FR-002 / constitution Principle I (no parallel ledger).

**Caveat**: the exact type signature of `applyTx` in the version
pinned by `cabal.project` is verified empirically at T011 when
we first call it from a test. If the signature forces a
wrapper, the wrapper lives in `Cardano.Tx.Build` and exposes
the simpler shape
`applyTxBody :: PParamsBound era -> UTxO era -> SlotNo -> Tx era
-> Either (ApplyTxError era) ()`.

---

## R-002: Does `hashScriptIntegrity` already use Conway redeemer encoding?

**Status**: DEFERRED (decision rule recorded; empirical
verification happens at T011).

**Decision rule**: keep
`Cardano.Ledger.Alonzo.Tx.hashScriptIntegrity` for now — the
`Redeemers ConwayEra` value's `EncCBOR` instance is
era-parameterized and is expected to produce the Conway map
form (witness-set key `5`). The first golden test (T011)
computes the hash for the issue-#8 fixture and compares it to
the ledger's expected value `41a7cd57…dcf9`.

- If the result matches → the existing `hashScriptIntegrity`
  is correct for Conway; the bug is purely in the cost-models /
  language-set scope (R-003). No change to
  `hashScriptIntegrity` itself.
- If the result differs → the encoding bug is real; switch to
  the Conway-era equivalent
  (`Cardano.Ledger.Conway.Tx.hashScriptIntegrity` if it exists,
  or a re-export from `Cardano.Ledger.Api`).

**Rationale for deferring**: an empirical golden-vector check
is cheaper and more reliable than reading the ledger source
through cabal. The check is required anyway (SC-002), so this
is a no-cost deferral.

**Acceptance**: T011 (the regression test for the mainnet
reproduction) computes the hash and compares it to
`41a7cd57…dcf9`. The R-002 outcome is encoded in whether the
hash-fix commit needs to change `hashScriptIntegrity`'s
import or not.

---

## R-003: Cost-models scope — single language or set?

**Status**: RESOLVED (2026-05-15)

**Decision**: derive the language set from the body via

```haskell
languagesUsedInBody
  :: TxBody ConwayEra
  -> UTxO ConwayEra
  -> Set Language
```

Walks (a) the body's spending redeemers and their resolved
scripts, (b) reference-script inputs that supply a Plutus
script. Native (timelock) scripts do not contribute.

**Confirmed by source reading**: all three call sites in
`src/Cardano/Tx/Build.hs` (lines 1043, 1289, 1775) currently
hardcode the literal `PlutusV3`. Caller convention is the only
guarantee today — exactly the footgun this re-scopes away.

**Rationale**: aligns with FR-001 "derived from the body, not
from caller convention" and removes a recurring footgun.
Implementable from data already in scope; no new query.

**Alternatives considered**:
- Keep single `Language`, audit all three call sites.
  Rejected: same bug class will recur on the next
  mixed-language transaction.
- Derive from the resolved UTxO instead of the body.
  Equivalent for a well-formed body. Body-derived chosen
  because it keeps the helper independent of any enclosing
  UTxO map's completeness.

---

## R-004: `PParams` threading — does it need a newtype?

**Status**: RESOLVED (2026-05-15, user decision)

**Decision**: introduce `PParamsBound era` per
[data-model.md](./data-model.md) E-1. Smart constructor at the
build entrypoint; every internal helper that depends on
protocol parameters takes `PParamsBound era` instead of
`PParams era`.

**Rationale**: a structural guarantee is preferred over a
behavioral one even if today's flow happens to be
single-instance. The newtype is ~10 lines, the API surface
change is internal-only (callers still pass `PParams era` to
the build entry point and the wrapper is constructed inside),
and it eliminates the entire "PParams source drift" failure
mode at the type level, which is the FR-002 contract.

**Acceptance**: every reference to `PParams` inside the
`Cardano.Tx.Build` build path either takes `PParamsBound era`
or is visibly the single `unPParamsBound` unwrap at a leaf
consumer (`estimateMinFeeTx`, the ledger Phase-1 call) where
the underlying ledger API still demands raw `PParams`.

---

## R-005: Test PParams snapshot — reuse the committed file or take a fresh one?

**Status**: RESOLVED (2026-05-15)

**Decision**: reuse the already-committed
`test/fixtures/pparams.json` (added by commit `8325820` "feat:
migrate Blueprint, TxDiff stack, Evaluate, and tx-diff exe").
The capture mechanism that originally produced it is
unspecified at the file level; what matters for SC-002 is that
the snapshot's cost-models match those in force when the
swap-cancel tx was rejected.

**Verification**: T011 computes the integrity hash against
this PParams snapshot and asserts it equals the ledger's
expected value `41a7cd57…dcf9`. If the snapshot's epoch is
wrong, T011 fails immediately and the fixture is recaptured
via this project's own resolvers (LSQ N2C against a mainnet
socket — never Blockfrost, per memory `feedback_fix_own_tools`
and the predecessor PR's R-005 ruling).

**Acceptance**: T011 passes with the currently-committed
`pparams.json`. If it doesn't, re-capture and re-commit
*before* shipping any TxBuild fix.

---

## R-006: UTxO source for self-validation

**Status**: RESOLVED (2026-05-15)

**Decision**: build the `UTxO ConwayEra` argument to `applyTx`
as the union of three lists already in scope at the return
point of `buildWith` in `src/Cardano/Tx/Build.hs`:
`inputUtxos`, `boCollateralUtxos opts`, and `refUtxos`. No
new query is required.

**Confirmed by source reading**:
`src/Cardano/Tx/Build.hs` lines 1245–1246, 1250 (the three
UTxO lists arrive at `buildWith` as parameters); lines
1309–1316 (`balanceTxWith` is called with all three); lines
1515 and 1569 (the final balanced tx is returned while all
three lists remain in lexical scope).
`src/Cardano/Tx/Balance.hs` (signature of `balanceTxWith`
taking all three UTxO sources separately, port of the original
in the predecessor repo).

**Combined-UTxO helper**: introduce a small
`combinedUtxo :: [(TxIn, TxOut era)] -> [(TxIn, TxOut era)]
-> [(TxIn, TxOut era)] -> UTxO era` (or inline at the call
site) that folds the three lists into a single
`Map TxIn (TxOut era)` and wraps it in `UTxO`. It is the
caller of `applyTx`, not part of the public API.

**Acceptance**: the `applyTx` call site at finalize time
consumes exactly the inputs + reference inputs + collateral
that the body declares. The negative test verifies this by
passing a body whose collateral references a UTxO outside the
union and observing the resulting `UtxoFailure` is surfaced.

---

## Summary of decisions (2026-05-15)

| ID | Decision |
|----|----------|
| R-001 | Phase-1 entry point = `Cardano.Ledger.Api.Tx.applyTx`. Signature verified empirically at T011; wrapper added if needed. |
| R-002 | Keep `Cardano.Ledger.Alonzo.Tx.hashScriptIntegrity`; rely on `Redeemers ConwayEra`'s era-parameterized encoding. T011 golden-vector check decides whether a Conway-specific replacement is needed. |
| R-003 | Body-derived `Set Language` via `languagesUsedInBody`. All three call sites at `src/Cardano/Tx/Build.hs:1043,1289,1775` currently hardcode `PlutusV3`. |
| R-004 | Add `PParamsBound era` newtype per [data-model.md](./data-model.md) E-1. |
| R-005 | Reuse already-committed `test/fixtures/pparams.json`. If T011 reveals an epoch mismatch, re-capture via this repo's resolvers (LSQ N2C) — **no Blockfrost / external service**. |
| R-006 | `UTxO ConwayEra` for `applyTx` = `inputUtxos ∪ boCollateralUtxos opts ∪ refUtxos`, all in scope at `buildWith` (`src/Cardano/Tx/Build.hs:1250`). |

These are the inputs to `/speckit.tasks`.

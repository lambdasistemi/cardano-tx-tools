# Contract: `Cardano.Tx.Validate.validatePhase1`

**Feature**: 014-validate-phase1
**Module**: `Cardano.Tx.Validate` (new)
**Stability**: same as the rest of `Cardano.Tx.*` — public surface, follows the
repo's normal semver discipline (constitution IV: Hackage-Ready).

## Module header (Haddock, normative)

```haskell
{- |
Module      : Cardano.Tx.Validate
Description : Conway Phase-1 pre-flight against ledger applyTx.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Run the Conway ledger's Phase-1 rule (UTXOW + LEDGER) against a
candidate transaction without submitting it. The transaction is
typically the unsigned 'ConwayTx' that
'Cardano.Tx.Build.buildWith' returns; callers invoke
'validatePhase1' between build and sign to catch structural bugs
(script integrity hash mismatch, fee bounds, min-utxo, collateral,
validity interval, ref-script bytes, language-view consistency)
before paying the signing or submission cost.

On unsigned input, 'applyTx' always raises
'MissingVKeyWitnessesUTXOW' (and similar native-script-signature
failures) alongside any genuine structural problems. These are
recognised as expected noise; callers filter them via
'isWitnessCompletenessFailure'. A 'Right' result is therefore
essentially impossible on unsigned input — the contract is "no
structural failure remained after filtering."

The implementation duplicates the recipe from
[Conway.Inspector.Validation in cardano-ledger-inspector](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs).
See spec 014 "Implementation strategy" and upstream
consolidation ticket
<https://github.com/lambdasistemi/cardano-ledger-inspector/issues/73>
for the rationale (and the swap-to-dependency path if/when the
typed kernel ships upstream).
-}
module Cardano.Tx.Validate
    ( validatePhase1
    , isWitnessCompletenessFailure
    ) where
```

## `validatePhase1`

### Signature

```haskell
validatePhase1
    :: BaseTypes.Network
    -> PParamsBound
    -> [(TxIn, TxOut ConwayEra)]
    -> SlotNo
    -> ConwayTx
    -> Either (ApplyTxError ConwayEra) ()
```

### Haddock

```haskell
{- | Run Conway Phase-1 validation against a candidate transaction.

The function is pure (no @IO@). It synthesises a ledger
'BaseTypes.Globals' from the supplied 'BaseTypes.Network', seeds
a fresh 'NewEpochState' with the unwrapped 'PParams' and the
supplied UTxO at the given 'SlotNo', and calls
@Cardano.Ledger.Shelley.API.Mempool.applyTx@. The returned
'ApplyTxError' is exposed verbatim — no re-classification, no
filtering. Callers needing to drop witness-completeness noise
should filter the carried @NonEmpty ConwayLedgerPredFailure@ via
'isWitnessCompletenessFailure'.

== Caller workflow

@
case validatePhase1 net pp utxo slot tx of
    Right () -> -- proceed to sign
    Left (ConwayApplyTxError errs) ->
        let structural =
              NonEmpty.filter
                (not . isWitnessCompletenessFailure)
                errs
        in case structural of
            [] -> -- only witness noise; proceed to sign
            _  -> -- real Phase-1 bug; surface to caller
@

== Mempool seeding caveat

If the supplied UTxO does not contain at least one entry for any
of the transaction's inputs, the mempool short-circuits via
@whenFailureFreeDefault@ and the only failure reported is the
duplicate-detection one. The test suite covers this as a
defensive negative case (see "ValidateSpec.hs").
-}
```

### Failure semantics

Returns `Left (ApplyTxError ConwayEra)` whenever the ledger's
UTXOW + LEDGER rule rejects the body. The payload carries the full
`NonEmpty (ConwayLedgerPredFailure ConwayEra)` — every accumulated
failure from the STS, not just the first one (per the research
recorded in `spec.md`).

Returns `Right ()` only if every check passes. Essentially impossible
on unsigned input; intended for callers who already filtered
witness-completeness noise out (or for callers who invoke
`validatePhase1` on a *signed* tx — supported per `spec.md` edge
cases, not the primary path).

### Purity

No `IO`. No `MonadIO`. No mutable references. Same input always
produces the same output.

## `isWitnessCompletenessFailure`

### Signature

```haskell
isWitnessCompletenessFailure
    :: ConwayLedgerPredFailure ConwayEra -> Bool
```

### Haddock

```haskell
{- | Recognise the failure constructors that any unsigned
candidate transaction will trip via @applyTx@'s UTXOW rule.
These are not structural bugs; they reflect the fact that
'validatePhase1' is a pre-flight run BEFORE signing.

Callers typically use this to filter:

@
let structural =
        NonEmpty.filter
            (not . isWitnessCompletenessFailure)
            (errsFromApplyTxError result)
@

Constructors recognised as noise (locked in by SC-004):

* 'ConwayUtxowFailure' (@MissingVKeyWitnessesUTXOW _@) — required
  signers without vkey witnesses (the obvious one).
* 'ConwayUtxowFailure' (@MissingScriptWitnessesUTXOW _@) — native
  scripts whose signatures aren't in the witness set.

Constructors deliberately NOT recognised as noise (they fire on
both signed and unsigned input, so they're genuine structural
issues either way):

* metadata-hash mismatches
* PPViewHashes / script-integrity mismatches
* fee / min-utxo / collateral / validity-interval failures
* ref-script bytes / language-view consistency

Subject to revision when the pinned ledger version adds new
witness-completeness constructors; see the test suite for the
current locked list.
-}
```

## Build-plan deltas

New direct dependencies in the main library's `build-depends`
(`cardano-tx-tools.cabal`):

```
, cardano-ledger-shelley
, data-default
```

`cardano-ledger-shelley` is in the transitive closure via
`cardano-ledger-conway`; the explicit add is required by
`cabal check`'s strict mode (constitution IV) because we import its
modules directly.

`data-default` is the `Default` typeclass package on Hackage. Used
solely for `def :: NewEpochState ConwayEra`.

## Test surface (informative; the test file itself is not the contract)

- `test/Cardano/Tx/ValidateSpec.hs` — hspec test cases from spec.md
  Stories 1 & 2 (4 + 1 acceptance scenarios) plus the mempool
  short-circuit defensive negative case.
- `test/Cardano/Tx/Validate/LoadUtxo.hs` — test-only helper, reads a
  directory of producer-tx CBOR-hex files (one per producer `TxId`)
  and resolves `[(TxIn, TxOut ConwayEra)]` for a list of requested
  `TxIn`s. Not exported from the library (FR-009; constitution II).
  See [research.md R4](../research.md#r4-utxo-evidence-shape-producer-tx-cbors-revised-mid-implementation)
  for the evidence-shape rationale.
- `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex` —
  the post-fix unsigned body from PR #9.
- `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs/<txid>.cbor.hex` —
  producer-tx CBORs for the two `TxId`s the body references
  (`59e10ca5…` and `f5f1bdfa…`). Fetched once via Blockfrost,
  committed for offline replay.

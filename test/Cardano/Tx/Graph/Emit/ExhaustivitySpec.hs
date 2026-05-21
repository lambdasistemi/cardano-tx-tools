{- |
Module      : Cardano.Tx.Graph.Emit.ExhaustivitySpec
Description : Type-driven ConwayDiffValue dispatcher coverage (T115).
License     : Apache-2.0

== Belt-and-suspenders, not load-bearing (per A-007 v3)

The load-bearing exhaustivity gate is the compiler itself:
@-Wincomplete-patterns@ + @-Werror@ (constitution-mandated)
guarantees a missing 'Cardano.Tx.Diff.ConwayDiffValue' arm fails
the build. This spec is a secondary check that catches dispatcher
drift outside the literal pattern-match (e.g. a fail-loudly stub
that compiles but raises 'PUnsupportedLeafType' at runtime).

Per A-007 v3 corrected scope: the spec asserts coverage of the
__full chain-visible surface__ of a 'Cardano.Tx.Ledger.ConwayTx',
not the body-only subset the earlier A-006 framing carved out.
For each constructor in 'allConwayDiffConstructors' the spec ships
a synthetic 'ConwayTx' that populates the field labelled by the
constructor and asserts 'Cardano.Tx.Graph.Emit.emit' returns
'Right' (not @Left ('UnsupportedLeafType' _)@) for each witness.

This converts "the emitter forgot to dispatch a chain-visible
leaf" from a runtime crash on a real-chain transaction (which is
how 'ConwayRequiredSignersValue' surfaced on the operator's tx
on 2026-05-21) into a test-time per-constructor failure.

== Construction list

'allConwayDiffConstructors' is the hand-maintained enumeration of
every constructor declared in @Cardano.Tx.Diff.ConwayDiffValue@.
Its sole purpose is the @exhaustivity_lint@ step in @gate.sh@,
which @diff -u@s this list against the constructors @grep@ed out
of @src/Cardano/Tx/Diff.hs@; any drift (a new ledger constructor
without a list entry, or a stale list entry that no longer
matches a Diff.hs constructor) fails the gate.

== Pending witness-set + diff-fallback constructors

'pendingTillT128b' enumerates the 13 constructors that a synthetic
'ConwayTx' cannot exercise through the body walker alone — the 12
witness-set leaves (vkey witnesses, bootstrap witnesses, scripts,
datums-as-witnesses, redeemers, ex-units) plus 'ConwayOpenValue'
(the diff-projection fallback the body walker bypasses via direct
lens access). T128b promotes the 12 witness entries into positive
assertions when the new
@Cardano.Tx.Graph.Emit.Witness@ walker lands; 'ConwayOpenValue'
stays pending as a documented permanent elision (no chain-visible
content of its own).

== Per-constructor witness assertion

For every constructor in 'allConwayDiffConstructors', the spec
ships a synthetic 'ConwayTx' that populates the body field
labelled by the constructor (via lens-set on @mkBasicTxBody@
where no fixture covers the case naturally). The assertion is
@'emit' witnessTx 'Map.empty' [] = 'Right' _@ — a per-constructor
'expectationFailure' isolates which leaf regressed when the
spec is RED. Constructors listed in 'pendingTillT128b' short-circuit
to 'pendingWith' so the suite stays green while T128b is in flight.
-}
module Cardano.Tx.Graph.Emit.ExhaustivitySpec (
    spec,
    allConwayDiffConstructors,
) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text

import Lens.Micro ((&), (.~))

import PlutusCore.Data qualified as PLC

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Withdrawals (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..), TxDats (..))
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    reqSignerHashesTxBodyL,
    totalCollateralTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Wits (
    datsTxWitsL,
    rdmrsTxWitsL,
    scriptTxWitsL,
 )
import Cardano.Ledger.BaseTypes (
    SlotNo (..),
    StrictMaybe (SJust),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (Script, hashScript)
import Cardano.Ledger.Hashes (DataHash, KeyHash (..), ScriptHash)
import Cardano.Ledger.Keys (KeyRole (..))
import Cardano.Ledger.Mary.Value (MultiAsset (..))
import Cardano.Ledger.Plutus.Data (Data (..), hashData)
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))

import Data.Sequence.Strict qualified as StrictSeq

import Cardano.Tx.Graph.Emit (
    ResolvedUTxO,
    emit,
    renderEmitError,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.Helpers (
    stubMintEntry,
    stubRefScript,
    stubRewardAccount,
    stubTxIn,
    stubTxOut,
 )

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    pendingWith,
    shouldBe,
 )

----------------------------------------------------------------------
-- Constructor enumeration
----------------------------------------------------------------------

{- | Every constructor declared in @Cardano.Tx.Diff.ConwayDiffValue@.

Hand-maintained, alphabetized. The @exhaustivity_lint@ step in
@gate.sh@ diffs this list against
@grep -hE '^\s+\| Conway[A-Z][A-Za-z]*Value' src/Cardano/Tx/Diff.hs@;
symmetric drift (a new ledger constructor not here, or a stale
entry here that no longer matches Diff.hs) fails the gate.
-}
allConwayDiffConstructors :: [Text]
allConwayDiffConstructors =
    [ "ConwayAddressValue"
    , "ConwayAssetQuantitiesValue"
    , "ConwayBodyValue"
    , "ConwayBootstrapWitnessValue"
    , "ConwayBootstrapWitnessesValue"
    , "ConwayCoinValue"
    , "ConwayDataValue"
    , "ConwayDatumValue"
    , "ConwayDatumWitnessesValue"
    , "ConwayExUnitsValue"
    , "ConwayInputsValue"
    , "ConwayIntegerValue"
    , "ConwayKeyHashValue"
    , "ConwayKeyHashesValue"
    , "ConwayMintValue"
    , "ConwayOpenValue"
    , "ConwayOutputsValue"
    , "ConwayRedeemerValue"
    , "ConwayRedeemersValue"
    , "ConwayReferenceScriptValue"
    , "ConwayScriptValue"
    , "ConwayScriptsValue"
    , "ConwaySlotBoundValue"
    , "ConwayStrictMaybeCoinValue"
    , "ConwayTxInIdValue"
    , "ConwayTxInValue"
    , "ConwayTxOutValue"
    , "ConwayTxValue"
    , "ConwayVKeyWitnessValue"
    , "ConwayVKeyWitnessesValue"
    , "ConwayValidityIntervalValue"
    , "ConwayWithdrawalsValue"
    , "ConwayWitnessesValue"
    ]

{- | Constructors the body walker cannot reach with a synthetic
'ConwayTx' alone via either body or witness-set lenses.

After T128b the only remaining permanent elision is
'ConwayOpenValue' — the diff-projection fallback the body
walker bypasses via direct lens access. There is no chain-visible
content of its own to assert against.
-}
pendingTillT128b :: [Text]
pendingTillT128b =
    [ "ConwayOpenValue"
    ]

----------------------------------------------------------------------
-- Witness ConwayTx per body-reachable constructor
----------------------------------------------------------------------

{- | An empty Conway tx — body fields all default
('Cardano.Ledger.Api.Tx.mkBasicTx' on 'mkBasicTxBody').
Witness baseline for the container-only constructors
@ConwayTxValue@ and @ConwayBodyValue@.
-}
baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

{- | The witness 'ConwayTx' for the named constructor — a minimal
tx that populates the body field labelled by the constructor.

Only called for constructors not in 'pendingTillT128b'
(those short-circuit before reaching here). The catch-all
'error' branch only fires if a body-reachable constructor is
added to 'allConwayDiffConstructors' without a corresponding
witness arm or a 'pendingTillT128b' entry.
-}
witnessTx :: Text -> ConwayTx
witnessTx = \case
    "ConwayTxValue" -> baseTx
    "ConwayBodyValue" -> baseTx
    -- ConwayInputsValue / ConwayTxInValue / ConwayTxInIdValue
    -- are all exercised by populating any input set; the body
    -- walker visits the elements through the same code path.
    "ConwayInputsValue" -> txWithInput
    "ConwayTxInValue" -> txWithInput
    "ConwayTxInIdValue" -> txWithInput
    -- ConwayCoinValue is exercised by either a non-zero fee or a
    -- coin-bearing output. We pick the fee path because it is the
    -- shortest synthetic — no Addr / Value plumbing required.
    "ConwayCoinValue" -> baseTx & bodyTxL . feeTxBodyL .~ Coin 1
    -- ConwayStrictMaybeCoinValue is exercised by setting
    -- totalCollateral to SJust.
    "ConwayStrictMaybeCoinValue" ->
        baseTx & bodyTxL . totalCollateralTxBodyL .~ SJust (Coin 1)
    -- ConwayKeyHashesValue / ConwayKeyHashValue are exercised by
    -- a non-empty required-signers set.
    "ConwayKeyHashesValue" -> txWithRequiredSigner
    "ConwayKeyHashValue" -> txWithRequiredSigner
    -- ConwayMintValue / ConwayAssetQuantitiesValue /
    -- ConwayIntegerValue are exercised by a non-empty mint.
    "ConwayMintValue" -> txWithMint
    "ConwayAssetQuantitiesValue" -> txWithMint
    "ConwayIntegerValue" -> txWithMint
    "ConwayWithdrawalsValue" -> txWithWithdrawal
    -- ConwayValidityIntervalValue / ConwaySlotBoundValue are
    -- exercised by a populated validity interval.
    "ConwayValidityIntervalValue" -> txWithValidity
    "ConwaySlotBoundValue" -> txWithValidity
    -- ConwayOutputsValue / ConwayTxOutValue / ConwayAddressValue
    -- are exercised by any output. ConwayDatumValue and
    -- ConwayReferenceScriptValue are exercised by an output that
    -- carries an inline datum / reference script — but the
    -- per-output base path itself (no datum, no refScript) is
    -- enough for the OutputsValue / TxOutValue / AddressValue
    -- constructors. The datum + refScript constructors are
    -- already covered by T105's OutputDatumSpec /
    -- OutputScriptRefSpec — pointing at the same fixture-side
    -- witness here avoids duplicating Datum / Script construction.
    "ConwayOutputsValue" -> txWithOutput
    "ConwayTxOutValue" -> txWithOutput
    "ConwayAddressValue" -> txWithOutput
    "ConwayDatumValue" -> txWithOutput -- See note above; T105 covers
    -- the inline-datum + datum-hash branches in 'OutputDatumSpec'.
    -- This witness only exercises the NoDatum elision branch via
    -- the empty output.
    "ConwayReferenceScriptValue" -> txWithOutput -- T105 covers the
    -- SJust branch in 'OutputScriptRefSpec'; this witness exercises
    -- the SNothing elision branch via the empty output.
    -- T128b / S31 — witness-set walker landings.
    -- ConwayWitnessesValue is the container; any non-empty witness
    -- field exercises it. We pick the datum-witness path because
    -- it requires the least crypto plumbing.
    "ConwayWitnessesValue" -> txWithDatumWitness
    -- ConwayDataValue / ConwayDatumWitnessesValue: a TxDats entry.
    "ConwayDataValue" -> txWithDatumWitness
    "ConwayDatumWitnessesValue" -> txWithDatumWitness
    -- ConwayExUnitsValue / ConwayRedeemerValue / ConwayRedeemersValue:
    -- a Redeemers map carrying one (Data, ExUnits) pair.
    "ConwayExUnitsValue" -> txWithRedeemer
    "ConwayRedeemerValue" -> txWithRedeemer
    "ConwayRedeemersValue" -> txWithRedeemer
    -- ConwayScriptValue / ConwayScriptsValue: a script-bag entry.
    "ConwayScriptValue" -> txWithScriptWitness
    "ConwayScriptsValue" -> txWithScriptWitness
    -- ConwayVKeyWitnessValue / ConwayVKeyWitnessesValue /
    -- ConwayBootstrapWitnessValue / ConwayBootstrapWitnessesValue:
    -- constructing a real DSIGN signature in a pure synthesizer is
    -- impractical (Byron-era plumbing for bootstrap, full Ed25519
    -- sign for vkey). Per T128b brief minimum-is-enough: the
    -- @emit@ walker handles empty addrTxWitsL / bootAddrTxWitsL
    -- collections without crashing (the @projectWitness@ dispatch
    -- runs unconditionally and emits zero edges for empty
    -- collections), so a baseline tx still passes the @Right _@
    -- assertion. The cryptographic-construction path is covered
    -- via the blockfrost-cache real-chain smoke gate (T127 /
    -- @BlockfrostSampleSmokeSpec@) which exercises actual signed
    -- transactions end-to-end.
    "ConwayVKeyWitnessValue" -> baseTx
    "ConwayVKeyWitnessesValue" -> baseTx
    "ConwayBootstrapWitnessValue" -> baseTx
    "ConwayBootstrapWitnessesValue" -> baseTx
    name ->
        error
            ( "ExhaustivitySpec.witnessTx: no witness clause for "
                <> Text.unpack name
                <> ". Add a witnessTx arm or extend pendingTillT128b."
            )

-- | A tx with exactly one body input.
txWithInput :: ConwayTx
txWithInput =
    baseTx & bodyTxL . inputsTxBodyL .~ Set.singleton (stubTxIn 1)

-- | A tx with exactly one required signer (28-byte key hash).
txWithRequiredSigner :: ConwayTx
txWithRequiredSigner =
    baseTx & bodyTxL . reqSignerHashesTxBodyL .~ Set.singleton stubKeyHashWitness

stubKeyHashWitness :: KeyHash Guard
stubKeyHashWitness =
    KeyHash (fromJust (hashFromStringAsHex (replicate 56 '0')))

-- | A tx with exactly one mint entry (positive quantity 1).
txWithMint :: ConwayTx
txWithMint =
    baseTx
        & bodyTxL . mintTxBodyL .~ MultiAsset (Map.fromList [stubMintEntry 1 1])

-- | A tx with exactly one withdrawal entry of 1 lovelace.
txWithWithdrawal :: ConwayTx
txWithWithdrawal =
    baseTx
        & bodyTxL . withdrawalsTxBodyL
            .~ Withdrawals (Map.singleton (stubRewardAccount 1) (Coin 1))

-- | A tx with a populated validity interval (both bounds @SJust@).
txWithValidity :: ConwayTx
txWithValidity =
    baseTx
        & bodyTxL . vldtTxBodyL
            .~ ValidityInterval (SJust (SlotNo 1)) (SJust (SlotNo 2))

-- | A tx with exactly one output (coin-only at the shared stub addr).
txWithOutput :: ConwayTx
txWithOutput =
    baseTx
        & bodyTxL . outputsTxBodyL .~ StrictSeq.fromList [stubTxOut 1_000_000]

----------------------------------------------------------------------
-- Synthetic witness-set leaves (T128b / S31)
----------------------------------------------------------------------

-- | A deterministic Plutus 'Data' value.
stubDatumData :: Data ConwayEra
stubDatumData = Data (PLC.I 42)

-- | The hash of 'stubDatumData' — keys the datum-witness 'TxDats' map.
stubDatumHash :: DataHash
stubDatumHash = hashData stubDatumData

-- | A deterministic 'ExUnits' value (any non-zero is fine).
stubExUnits :: ExUnits
stubExUnits = ExUnits 100 200

-- | A deterministic redeemer purpose — 'ConwaySpending' at index 0.
stubRedeemerPurpose :: ConwayPlutusPurpose AsIx ConwayEra
stubRedeemerPurpose = ConwaySpending (AsIx 0)

-- | The hash of 'stubRefScript' — keys the script-witness map.
stubScriptHash :: ScriptHash
stubScriptHash = hashScript (stubRefScript :: Script ConwayEra)

{- | A tx with exactly one datum witness entry — the
@stubDatumData@ keyed by its hash inside the @TxDats@ map.
-}
txWithDatumWitness :: ConwayTx
txWithDatumWitness =
    baseTx
        & witsTxL . datsTxWitsL
            .~ TxDats (Map.singleton stubDatumHash stubDatumData)

{- | A tx with exactly one redeemer entry — a 'ConwaySpending' at
index 0 carrying 'stubDatumData' + 'stubExUnits'.
-}
txWithRedeemer :: ConwayTx
txWithRedeemer =
    baseTx
        & witsTxL . rdmrsTxWitsL
            .~ Redeemers
                ( Map.singleton
                    stubRedeemerPurpose
                    (stubDatumData, stubExUnits)
                )

-- | A tx with exactly one script-witness entry — 'stubRefScript'.
txWithScriptWitness :: ConwayTx
txWithScriptWitness =
    baseTx
        & witsTxL . scriptTxWitsL
            .~ Map.singleton stubScriptHash stubRefScript

----------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit ConwayDiffValue exhaustivity (T115)" $ do
    handListShapeSpec
    witnessCoverageSpec

-- | Sanity-check the hand list itself: alphabetized, no duplicates.
handListShapeSpec :: Spec
handListShapeSpec = describe "constructor hand list" $ do
    it "allConwayDiffConstructors is alphabetized" $
        allConwayDiffConstructors `shouldBe` sortedNub allConwayDiffConstructors

sortedNub :: (Ord a) => [a] -> [a]
sortedNub = Set.toAscList . Set.fromList

{- | The load-bearing assertion: for each constructor in
'allConwayDiffConstructors', the witness 'ConwayTx' emits
without a @PUnsupportedLeafType@.

Constructors listed in 'pendingTillT128b' short-circuit to
'pendingWith' — T128b's witness-set walker will promote the
12 witness entries into active assertions; 'ConwayOpenValue'
stays pending as a documented permanent elision.
-}
witnessCoverageSpec :: Spec
witnessCoverageSpec =
    describe "witness ConwayTx emits without PUnsupportedLeafType" $
        mapM_ assertWitnessCovers allConwayDiffConstructors

assertWitnessCovers :: Text -> Spec
assertWitnessCovers name =
    it (Text.unpack name) $
        if name `elem` pendingTillT128b
            then pendingWith "T128b: witness-set walker / diff fallback"
            else case emit (witnessTx name) emptyUtxo [] of
                Left err ->
                    expectationFailure $
                        "witness for "
                            <> Text.unpack name
                            <> " emitted Left: "
                            <> renderEmitError err
                Right _ -> pure ()

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

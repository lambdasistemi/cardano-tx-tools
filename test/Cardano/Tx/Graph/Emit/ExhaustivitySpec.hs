{- |
Module      : Cardano.Tx.Graph.Emit.ExhaustivitySpec
Description : Type-driven ConwayDiffValue dispatcher coverage (T115).
License     : Apache-2.0

== Belt-and-suspenders, not load-bearing (per A-006)

The load-bearing exhaustivity gate is the compiler itself:
@-Wincomplete-patterns@ + @-Werror@ (constitution-mandated)
guarantees a missing 'Cardano.Tx.Diff.ConwayDiffValue' arm fails
the build. This spec is a secondary check that catches dispatcher
drift outside the literal pattern-match (e.g. a fail-loudly stub
that compiles but raises 'PUnsupportedLeafType' at runtime).

For each body-reachable constructor the spec ships a synthetic
'Cardano.Tx.Ledger.ConwayTx' that populates the body field
labelled by the constructor (via lens-set on @mkBasicTxBody@
where no fixture covers the case naturally) and asserts
'Cardano.Tx.Graph.Emit.emit' returns 'Right' (not
@Left ('UnsupportedLeafType' _)@) for each witness.

This converts "the emitter forgot to dispatch a body-reachable
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

== Body-reachable subset

'bodyReachableConstructors' carves the subset of constructors the
body walker actually visits. Witness-set, redeemer, and
inner-bytestring leaves (which the body walker never reaches) are
excluded, each with an inline rationale comment so a future
reader can audit the carve-out after a ledger update.

== Per-constructor witness assertion

For every body-reachable constructor, the spec ships a synthetic
'ConwayTx' that populates the body field labelled by the
constructor (via lens-set on @mkBasicTxBody@ where no fixture
covers the case naturally). The assertion is
@'emit' witnessTx 'Map.empty' [] = 'Right' _@ — a per-constructor
'expectationFailure' isolates which leaf regressed when the
spec is RED.

Constructors the emitter does not yet positively dispatch
(@ConwayKeyHashesValue@ / @ConwayKeyHashValue@ — required
signers; @ConwayStrictMaybeCoinValue@ — total collateral)
are marked 'pendingWith' the slice (@T116@, @T117@) that
flips them. Each subsequent coverage slice promotes its
'pendingWith' entry into an active assertion.
-}
module Cardano.Tx.Graph.Emit.ExhaustivitySpec (
    spec,
    allConwayDiffConstructors,
    bodyReachableConstructors,
) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Withdrawals (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
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
import Cardano.Ledger.BaseTypes (
    SlotNo (..),
    StrictMaybe (SJust),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Hashes (KeyHash (..))
import Cardano.Ledger.Keys (KeyRole (..))
import Cardano.Ledger.Mary.Value (MultiAsset (..))

import Data.Sequence.Strict qualified as StrictSeq

import Cardano.Tx.Graph.Emit (
    ResolvedUTxO,
    emit,
    renderEmitError,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.Helpers (
    stubMintEntry,
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

{- | The body-reachable subset of 'allConwayDiffConstructors'.

A constructor is body-reachable iff the emit walker
('Cardano.Tx.Graph.Emit.Project.projectBody') visits its leaf when
walking the body of a populated Conway tx. Excluded constructors
carry inline rationale; the carve-out is what
'A-004-exhaustivity-approach.md' (Option B's "document the elision
rationale inline next to each excluded constructor") prescribes.
-}
bodyReachableConstructors :: [Text]
bodyReachableConstructors =
    [ "ConwayAddressValue" -- output address leaf
    , "ConwayAssetQuantitiesValue" -- per-policy mint container
    , "ConwayBodyValue" -- body container (always reached)
    , -- Excluded: "ConwayBootstrapWitnessValue" — witness-set, not body.
      -- Excluded: "ConwayBootstrapWitnessesValue" — witness-set, not body.
      "ConwayCoinValue" -- fee, output coin, total-collateral coin
    , -- Excluded: "ConwayDataValue" — datum witness, not body leaf
      -- (per-output datum flows through ConwayDatumValue).
      "ConwayDatumValue" -- output datum (T105)
    , -- Excluded: "ConwayDatumWitnessesValue" — witness-set datum
      -- collection, not body.
      -- Excluded: "ConwayExUnitsValue" — redeemer execution units,
      -- witness-set side, not body.
      "ConwayInputsValue" -- inputs / refInputs / collateralInputs container
    , "ConwayIntegerValue" -- mint quantity leaf
    , "ConwayKeyHashValue" -- required-signer key-hash leaf
    , "ConwayKeyHashesValue" -- required-signers container
    , "ConwayMintValue" -- mint container
    , -- Excluded: "ConwayOpenValue" — diff projection fallback for
      -- fields that have no dedicated constructor (governance
      -- procedures, etc.); the emit walker reaches these via
      -- direct lens access, not via the diff projection.
      "ConwayOutputsValue" -- outputs container
    , -- Excluded: "ConwayRedeemerValue" — witness-set, not body.
      -- Excluded: "ConwayRedeemersValue" — witness-set, not body.
      "ConwayReferenceScriptValue" -- output reference script (T105)
    , -- Excluded: "ConwayScriptValue" — witness-set script leaf,
      -- not body (output reference scripts flow through
      -- ConwayReferenceScriptValue).
      -- Excluded: "ConwayScriptsValue" — witness-set, not body.
      "ConwaySlotBoundValue" -- validity-interval slot bound leaf
    , "ConwayStrictMaybeCoinValue" -- total-collateral StrictMaybe coin
    , "ConwayTxInIdValue" -- TxIn id leaf
    , "ConwayTxInValue" -- per-input
    , "ConwayTxOutValue" -- per-output
    , "ConwayTxValue" -- root tx (always reached)
    , -- Excluded: "ConwayVKeyWitnessValue" — witness-set, not body.
      -- Excluded: "ConwayVKeyWitnessesValue" — witness-set, not body.
      "ConwayValidityIntervalValue" -- validity interval container
    , "ConwayWithdrawalsValue" -- withdrawals container
    -- Excluded: "ConwayWitnessesValue" — the witness set itself,
    -- which the body walker does not traverse.
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

{- | The witness 'ConwayTx' for the named body-reachable
constructor — a minimal tx that populates the body field labelled
by the constructor.

Total over 'bodyReachableConstructors'; the catch-all 'error'
branch fails 'GHC2021' incomplete-patterns warnings during
development but only fires at runtime if a hand-list entry has no
corresponding witness clause (which the per-constructor 'it' loop
below would surface as a per-case failure anyway).
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
    name ->
        error
            ( "ExhaustivitySpec.witnessTx: no witness clause for body-reachable "
                <> Text.unpack name
                <> ". Add a witness here when extending bodyReachableConstructors."
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
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit ConwayDiffValue exhaustivity (T115)" $ do
    handListShapeSpec
    bodyReachableShapeSpec
    witnessCoverageSpec

{- | Sanity-check the hand list itself: alphabetized, no duplicates,
body-reachable subset of all.
-}
handListShapeSpec :: Spec
handListShapeSpec = describe "constructor hand list" $ do
    it "allConwayDiffConstructors is alphabetized" $
        allConwayDiffConstructors `shouldBe` sortedNub allConwayDiffConstructors
    it "bodyReachableConstructors is alphabetized" $
        bodyReachableConstructors
            `shouldBe` sortedNub bodyReachableConstructors
    it "bodyReachableConstructors is a subset of allConwayDiffConstructors" $
        let all_ = Set.fromList allConwayDiffConstructors
            br = Set.fromList bodyReachableConstructors
         in (br `Set.difference` all_) `shouldBe` Set.empty

sortedNub :: (Ord a) => [a] -> [a]
sortedNub = Set.toAscList . Set.fromList

{- | Body-reachable subset shape: every body-reachable constructor
also appears in 'allConwayDiffConstructors'. This is the same as
the subset assertion above, surfaced under a per-name spec block
so a regression on a specific constructor surfaces with that
constructor's name.
-}
bodyReachableShapeSpec :: Spec
bodyReachableShapeSpec =
    describe "every body-reachable constructor is in the all-list" $
        mapM_
            ( \name ->
                it (Text.unpack name) $
                    Set.member name (Set.fromList allConwayDiffConstructors)
                        `shouldBe` True
            )
            bodyReachableConstructors

{- | The load-bearing assertion: for each body-reachable
constructor, the witness 'ConwayTx' emits without a
@PUnsupportedLeafType@.

Constructors not yet positively dispatched are 'pendingWith' the
slice that flips them. Each subsequent coverage slice
(T116..T122) promotes its 'pendingWith' branch into an active
assertion by deleting the 'pendingWith' line.
-}
witnessCoverageSpec :: Spec
witnessCoverageSpec =
    describe "witness ConwayTx emits without PUnsupportedLeafType" $
        mapM_ assertWitnessCovers bodyReachableConstructors

assertWitnessCovers :: Text -> Spec
assertWitnessCovers name = it (Text.unpack name) $ do
    case name of
        -- T116: required signers (cardano:hasRequiredSigner).
        "ConwayKeyHashesValue" -> pendingWith "T116 — required-signers emission"
        "ConwayKeyHashValue" -> pendingWith "T116 — required-signers emission"
        -- T117: totalCollateral (cardano:totalCollateral) and
        -- collateralReturn (cardano:hasCollateralReturn).
        "ConwayStrictMaybeCoinValue" ->
            pendingWith "T117 — total-collateral emission"
        _ -> case emit (witnessTx name) emptyUtxo [] of
            Left err ->
                expectationFailure $
                    "witness for "
                        <> Text.unpack name
                        <> " emitted Left: "
                        <> renderEmitError err
            Right _ -> pure ()

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

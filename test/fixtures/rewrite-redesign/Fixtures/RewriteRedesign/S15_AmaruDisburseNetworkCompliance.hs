{- |
Module      : Fixtures.RewriteRedesign.S15_AmaruDisburseNetworkCompliance
Description : Conway tx builder mirroring the network-compliance disburse.
License     : Apache-2.0

Mirrors the on-disk network-compliance disburse source transaction at
@\/code\/amaru-treasury-tx-issue-237\/transactions\/2026\/network_compliance\/affe90d1fa9a93b3e2a48009ef80634e9de8428640f5d673e85b002a86399982\/@.
A-002 anchors this fixture to that path; the prior
@antithesis-disburse-draft@ directory has been flattened away in the
sister repo.

Body shape per A-002:

* 5 treasury script inputs at script hash
  @32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d@ — each
  carries a @TreasurySpendRedeemer.Disburse@ redeemer with the
  @Pairs\<PolicyId, Pairs\<AssetName, Int\>\>@ amount field.
* 1 wallet input (pubkey, also sources collateral).
* 3 outputs: treasury return (ADA + USDM leftover), payee
  (ADA + 400000000000 USDM), and one change output back to the wallet.
* 2 required signers.
* 4 reference inputs (treasury validator, network-compliance
  permissions, registry, scopes references).
* 1 collateral input from the same wallet.
* 1 zero-lovelace withdrawal against the network-compliance permissions
  stake script @a64d1b9e1aeffe54056034d84977061b45a92691efc282fbee3fc094@.

Per A-001 / spec FR-009 this fixture pins the __current__ SchemaMap
typed output: the @TreasurySpendRedeemer.Disburse@ amount field
materializes as a parent @:TreasurySpendRedeemer_amount@ predicate
pointing at an opaque child bnode. The
@OpenArray [OpenObject {"key", "value"}]@ map shape is intentionally
not walked further — the walker extension is deferred to a later
ticket.

The body's wallet input is at body-index 0 (the lowest @TxId@ in the
sorted input set), with the five script-spend redeemers indexed
@AsIx 1@ through @AsIx 5@ over the remaining inputs. The on-chain tx
has a different ordering (wallet at body index 1); the
@assertShape@-only harness does not inspect the per-AsIx mapping —
what matters for the @:TreasurySpendRedeemer_amount@ emission is that
five spend redeemers attach to script-credential inputs whose resolved
UTxO entries (supplied via
@Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo@) live at the treasury
payment script.
-}
module Fixtures.RewriteRedesign.S15_AmaruDisburseNetworkCompliance (
    storyId,
    tx,
    shape,
    treasuryScriptHash,
    permissionsStakeScriptHash,
    usdmPolicy,
    usdmAssetName,
    payeePubKeyHash,
    walletPubKeyHash,
    treasuryInputs,
    treasuryUtxoEntry,
) where

import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Short qualified as SBS
import Data.Maybe (fromJust)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (Guard, Payment))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxIn)

import Data.Map.Strict qualified as Map

import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

import Fixtures.RewriteRedesign.Helpers (
    ExpectedShape (..),
    StoryId (..),
    TxBuilder (..),
    baseShape,
    mkTx,
    stubTxIn,
 )

import Cardano.Tx.Build (
    collateral,
    output,
    reference,
    requireSignature,
    spend,
    spendScript,
    withdrawScript,
 )
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "15-amaru-disburse-network-compliance"

----------------------------------------------------------------------
-- On-chain identifiers from the A-002 source
----------------------------------------------------------------------

{- | The @amaru-treasury.network_compliance@ payment-script hash. Used
both as the spending credential on the five treasury inputs (via
the resolved-UTxO map supplied by 'fixtureUtxo' in
@Cardano.Tx.Graph.EmitGoldenSpec@) and as the payment credential on
the treasury-return output.
-}
treasuryScriptHash :: ScriptHash
treasuryScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d"
            )
        )

{- | The @amaru-treasury.permissions@ stake-script hash that hosts the
zero-lovelace withdrawal in the source transaction. Distinct from
the treasury's own payment-script credential.
-}
permissionsStakeScriptHash :: ScriptHash
permissionsStakeScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "a64d1b9e1aeffe54056034d84977061b45a92691efc282fbee3fc094"
            )
        )

{- | The USDM policy id used by the on-chain Amaru treasury (shared
with fixtures 03 + 04 + 11).
-}
usdmPolicy :: PolicyID
usdmPolicy =
    PolicyID
        ( ScriptHash
            ( fromJust
                ( hashFromStringAsHex
                    "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad"
                )
            )
        )

{- | The CIP-68 USDM token name bytes (@0014df105553444d@ — the 8-byte
prefix + ASCII @USDM@).
-}
usdmAssetName :: AssetName
usdmAssetName = AssetName (SBS.toShort (decodeHex "0014df105553444d"))

{- | The Crypto Accounting Group payee's payment-key hash, decoded from
the on-chain @addr1q8qrds2…@ disbursement address.
-}
payeePubKeyHash :: KeyHash Payment
payeePubKeyHash =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "c036c15399bd8f9a36c042afbf3cad16edb71dbc13c2ede6c38942cb"
            )
        )

{- | The @amaru.network-wallet@ payment-key hash that pays fees, sources
collateral, and receives change.
-}
walletPubKeyHash :: KeyHash Payment
walletPubKeyHash =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1"
            )
        )

----------------------------------------------------------------------
-- Treasury inputs (re-exported for fixtureUtxo)
----------------------------------------------------------------------

{- | The five synthetic @TxIn@ values used as treasury script inputs.
Re-exported so 'Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo' can
build the resolved-UTxO map that lets the emitter resolve each
spend redeemer to the treasury payment-script credential and emit
the typed @:TreasurySpendRedeemer_amount@ predicates.
-}
treasuryInputs :: [TxIn]
treasuryInputs = [stubTxIn 2, stubTxIn 3, stubTxIn 4, stubTxIn 5, stubTxIn 6]

{- | A resolved 'TxOut' at the treasury script address, used by
@Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo@ when wiring the
fixture-15 resolved-UTxO entries. Coin + USDM quantities are
illustrative — only the address's payment-script credential is
load-bearing for the typed redeemer lookup.
-}
treasuryUtxoEntry :: TxOut ConwayEra
treasuryUtxoEntry =
    mkBasicTxOut treasuryAddr treasuryValue
  where
    treasuryValue =
        MaryValue
            (Coin 121_488_832)
            ( MultiAsset
                ( Map.singleton
                    usdmPolicy
                    (Map.singleton usdmAssetName 1_349_523_953)
                )
            )

----------------------------------------------------------------------
-- Conway tx body
----------------------------------------------------------------------

{- | Conway tx body for fixture 15 per A-002. See module Haddock for
the full per-field provenance.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1) -- wallet pubkey input
    _ <- spendScript (stubTxIn 2) disburseRedeemer -- treasury #1
    _ <- spendScript (stubTxIn 3) disburseRedeemer -- treasury #2
    _ <- spendScript (stubTxIn 4) disburseRedeemer -- treasury #3
    _ <- spendScript (stubTxIn 5) disburseRedeemer -- treasury #4
    _ <- spendScript (stubTxIn 6) disburseRedeemer -- treasury #5
    _ <- output (treasuryReturnOutput 120_299_272 1_349_523_953)
    _ <- output (payeeOutput 1_189_560 400_000_000_000)
    _ <- output (changeOutput 80_733_583)
    collateral (stubTxIn 100)
    reference (stubTxIn 200) -- treasury validator reference script
    reference (stubTxIn 201) -- permissions reference script
    reference (stubTxIn 202) -- registry reference script
    reference (stubTxIn 203) -- scopes reference script
    requireSignature signerCagPayee
    requireSignature signerNetworkWallet
    withdrawScript
        permissionsRewardAccount
        (Coin 0)
        withdrawRedeemer

----------------------------------------------------------------------
-- Outputs
----------------------------------------------------------------------

treasuryReturnOutput :: Integer -> Integer -> TxOut ConwayEra
treasuryReturnOutput coin usdmQty =
    mkBasicTxOut treasuryAddr value
  where
    value =
        MaryValue
            (Coin coin)
            ( MultiAsset
                ( Map.singleton
                    usdmPolicy
                    (Map.singleton usdmAssetName usdmQty)
                )
            )

payeeOutput :: Integer -> Integer -> TxOut ConwayEra
payeeOutput coin usdmQty =
    mkBasicTxOut payeeAddr value
  where
    value =
        MaryValue
            (Coin coin)
            ( MultiAsset
                ( Map.singleton
                    usdmPolicy
                    (Map.singleton usdmAssetName usdmQty)
                )
            )

changeOutput :: Integer -> TxOut ConwayEra
changeOutput coin =
    mkBasicTxOut walletAddr (MaryValue (Coin coin) (MultiAsset mempty))

----------------------------------------------------------------------
-- Addresses + reward account
----------------------------------------------------------------------

treasuryAddr :: Addr
treasuryAddr =
    Addr Testnet (ScriptHashObj treasuryScriptHash) StakeRefNull

payeeAddr :: Addr
payeeAddr =
    Addr Testnet (KeyHashObj payeePubKeyHash) StakeRefNull

walletAddr :: Addr
walletAddr =
    Addr Testnet (KeyHashObj walletPubKeyHash) StakeRefNull

permissionsRewardAccount :: AccountAddress
permissionsRewardAccount =
    AccountAddress Testnet (AccountId (ScriptHashObj permissionsStakeScriptHash))

----------------------------------------------------------------------
-- Required signers
----------------------------------------------------------------------

signerCagPayee :: KeyHash Guard
signerCagPayee =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1"
            )
        )

signerNetworkWallet :: KeyHash Guard
signerNetworkWallet =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "f3ab64b0f97dcf0f91232754603283df5d75a1201337432c04d23e2e"
            )
        )

----------------------------------------------------------------------
-- Redeemers
----------------------------------------------------------------------

{- | Raw 'PLC.Data' redeemer wrapper. Carries an already-decoded
@PlutusCore.Data@ tree through 'spendScript' / 'withdrawScript'
which require a 'ToData' instance. The instance round-trips the
'PLC.Data' unchanged into 'BuiltinData', so the on-wire CBOR matches
the input tree byte-for-byte.
-}
newtype RawData = RawData PLC.Data

instance ToData RawData where
    toBuiltinData (RawData d) = BuiltinData d

{- | The on-chain @TreasurySpendRedeemer.Disburse@ payload — a
single-field constructor (index 3) wrapping a
@Pairs<PolicyId, Pairs<AssetName, Int>>@ map. The map mirrors the
five identical redeemers attached to each treasury spend in the
source tx: ADA leftover (@1_189_560@) plus the 400_000_000_000 USDM
disbursement.
-}
disburseRedeemer :: RawData
disburseRedeemer =
    RawData
        ( PLC.Constr
            3
            [ PLC.Map
                [
                    ( PLC.B mempty
                    , PLC.Map [(PLC.B mempty, PLC.I 1_189_560)]
                    )
                ,
                    ( PLC.B usdmPolicyBytes
                    , PLC.Map [(PLC.B usdmAssetBytes, PLC.I 400_000_000_000)]
                    )
                ]
            ]
        )
  where
    usdmPolicyBytes =
        decodeHex "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad"
    usdmAssetBytes = decodeHex "0014df105553444d"

{- | The on-chain stake-script withdrawal redeemer for the
network-compliance permissions account — an empty list (the
permissions handler reads its arguments from the script context,
not from the redeemer payload).
-}
withdrawRedeemer :: RawData
withdrawRedeemer = RawData (PLC.List [])

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

decodeHex :: ByteString -> ByteString
decodeHex h = case Base16.decode h of
    Right bs -> bs
    Left err ->
        error ("S15_AmaruDisburseNetworkCompliance.decodeHex: " <> err)

----------------------------------------------------------------------
-- Expected structural shape
----------------------------------------------------------------------

{- | Expected structural shape per A-002: 6 inputs (1 wallet + 5
treasury), 3 outputs, 1 withdrawal, 1 collateral, 4 reference
inputs, blueprint registered for the treasury script.
-}
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 6
        , esOutputs = 3
        , esWithdrawals = 1
        , esCollateral = 1
        , esReferenceIns = 4
        , esBlueprintRef =
            Just "test/fixtures/rewrite-redesign/blueprints/amaru-treasury.cip57.json"
        }

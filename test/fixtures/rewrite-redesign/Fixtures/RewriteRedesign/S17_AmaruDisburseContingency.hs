{- |
Module      : Fixtures.RewriteRedesign.S17_AmaruDisburseContingency
Description : Conway tx builder mirroring the 4-of-4 contingency disburse.
License     : Apache-2.0

Mirrors the on-disk contingency disburse source transaction at
@\/code\/amaru-treasury-tx\/transactions\/2026\/contingency\/18d57a4f104df4cc776104ce626958e2110122392e4c4c7671edc8861b48452e\/@
(block @60509ac5a41a8919d9e00a77578f0309380d08a9002f088e85055ee6c7c883a7@,
slot @187_809_147@, fee 415_814 lovelace).

Body shape per A-002:

* 1 contingency treasury script input at payment-script hash
  @e6dbff09245eb89c4f583faaa428387e42c471f1868637a848602a4e@ —
  carries a @TreasurySpendRedeemer.Disburse@ redeemer with an
  ADA-only @Pairs\<PolicyId, Pairs\<AssetName, Int\>\>@ amount of
  205_000_000_000 lovelace.
* 1 wallet pubkey input (sources fee + collateral + change). The
  wallet is the shared @amaru.network-wallet@
  (@8bd03209…@), reused from fixture 15.
* 3 outputs: treasury return (3_852_000_000_000 lovelace back to the
  contingency treasury), beneficiary (205_000_000_000 lovelace to the
  network-compliance treasury at script
  @32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d@), and
  wallet change (92_141_887 lovelace).
* 4 required signers — the 4-of-4 contingency multisig from
  @intent.json@: @7095faf3…@, @f3ab64b0…@, @8bd03209…@, and
  @97e0f6d6…@.
* 4 reference inputs (treasury validator, permissions, registry,
  scopes references — stubbed via @stubTxIn 200..203@).
* 1 collateral input from the same wallet (@stubTxIn 100@).
* 1 zero-lovelace withdrawal against the contingency permissions
  stake script @2810b46b73cb27292cd8511274b6930188eee61b7d8635af6b1b626a@.

Per A-001 / spec FR-009 this fixture pins the __current__ SchemaMap
typed output: the @TreasurySpendRedeemer.Disburse@ amount field
materializes as a parent @:TreasurySpendRedeemer_amount@ predicate
pointing at an opaque child bnode. The
@OpenArray [OpenObject {"key", "value"}]@ map shape is intentionally
not walked further — the walker extension is deferred to a later
ticket.

The on-chain wallet address carries both payment and stake key
credentials; the DSL reconstruction uses @StakeRefNull@ for parity
with fixture 15. The assertShape-only harness counts inputs and does
not inspect address bytes, so the per-leaf address details are not
load-bearing for the typed @:TreasurySpendRedeemer_amount@ emission.
What is load-bearing is the resolved-UTxO map supplied via
'Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo': it maps the treasury
'TxIn' to a 'TxOut' at the contingency payment-script credential so
the emitter can resolve the spend purpose and emit the typed
redeemer predicates.
-}
module Fixtures.RewriteRedesign.S17_AmaruDisburseContingency (
    storyId,
    tx,
    shape,
    treasuryScriptHash,
    beneficiaryScriptHash,
    permissionsStakeScriptHash,
    walletPubKeyHash,
    treasuryInput,
    treasuryUtxoEntry,
) where

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
    MaryValue (..),
    MultiAsset (..),
 )
import Cardano.Ledger.TxIn (TxIn)

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
storyId = StoryId "17-amaru-disburse-contingency"

----------------------------------------------------------------------
-- On-chain identifiers from the A-002 source
----------------------------------------------------------------------

{- | The @amaru-treasury.contingency@ payment-script hash. Used both
as the spending credential on the single treasury input (via the
resolved-UTxO map supplied by 'fixtureUtxo' in
@Cardano.Tx.Graph.EmitGoldenSpec@) and as the payment credential on
the treasury-return output.
-}
treasuryScriptHash :: ScriptHash
treasuryScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "e6dbff09245eb89c4f583faaa428387e42c471f1868637a848602a4e"
            )
        )

{- | The @amaru-treasury.network_compliance@ payment-script hash, used
as the payment credential on the beneficiary output (the
contingency disburse funds the network-compliance treasury). Same
script hash that fixture 15 uses as its source-treasury credential.
-}
beneficiaryScriptHash :: ScriptHash
beneficiaryScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d"
            )
        )

{- | The contingency permissions stake-script hash that hosts the
zero-lovelace withdrawal in the source transaction. Distinct from
the contingency treasury's own payment-script credential and
distinct from fixture 15's network-compliance permissions stake
script.
-}
permissionsStakeScriptHash :: ScriptHash
permissionsStakeScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "2810b46b73cb27292cd8511274b6930188eee61b7d8635af6b1b626a"
            )
        )

{- | The @amaru.network-wallet@ payment-key hash that pays fees,
sources collateral, and receives change. Same wallet fixture 15
uses; on-chain @intent.json@ pins it as the contingency disburse
wallet.
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
-- Treasury input (re-exported for fixtureUtxo)
----------------------------------------------------------------------

{- | The single synthetic 'TxIn' used as the contingency treasury
script input. Re-exported so
'Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo' can build the
resolved-UTxO map that lets the emitter resolve the spend redeemer
to the contingency treasury payment-script credential and emit the
typed @:TreasurySpendRedeemer_amount@ predicate.
-}
treasuryInput :: TxIn
treasuryInput = stubTxIn 2

{- | A resolved 'TxOut' at the contingency treasury script address.
Used by @Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo@ to wire the
fixture-17 resolved-UTxO entry. The 4_057_000_000_000 lovelace
quantity mirrors the on-chain input value
(@46c11538…#0@); only the address's payment-script credential is
load-bearing for the typed redeemer lookup.
-}
treasuryUtxoEntry :: TxOut ConwayEra
treasuryUtxoEntry =
    mkBasicTxOut treasuryAddr treasuryValue
  where
    treasuryValue =
        MaryValue (Coin 4_057_000_000_000) (MultiAsset mempty)

----------------------------------------------------------------------
-- Conway tx body
----------------------------------------------------------------------

{- | Conway tx body for fixture 17 per A-002. See module Haddock for
the full per-field provenance.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1) -- wallet pubkey input
    _ <- spendScript treasuryInput disburseRedeemer -- contingency treasury
    _ <- output (treasuryReturnOutput 3_852_000_000_000)
    _ <- output (beneficiaryOutput 205_000_000_000)
    _ <- output (changeOutput 92_141_887)
    collateral (stubTxIn 100)
    reference (stubTxIn 200) -- treasury validator reference script
    reference (stubTxIn 201) -- permissions reference script
    reference (stubTxIn 202) -- registry reference script
    reference (stubTxIn 203) -- scopes reference script
    requireSignature signerScopeOwner
    requireSignature signerExtraOne
    requireSignature signerExtraTwo
    requireSignature signerExtraThree
    withdrawScript
        permissionsRewardAccount
        (Coin 0)
        withdrawRedeemer

----------------------------------------------------------------------
-- Outputs
----------------------------------------------------------------------

treasuryReturnOutput :: Integer -> TxOut ConwayEra
treasuryReturnOutput coin =
    mkBasicTxOut treasuryAddr (MaryValue (Coin coin) (MultiAsset mempty))

beneficiaryOutput :: Integer -> TxOut ConwayEra
beneficiaryOutput coin =
    mkBasicTxOut beneficiaryAddr (MaryValue (Coin coin) (MultiAsset mempty))

changeOutput :: Integer -> TxOut ConwayEra
changeOutput coin =
    mkBasicTxOut walletAddr (MaryValue (Coin coin) (MultiAsset mempty))

----------------------------------------------------------------------
-- Addresses + reward account
----------------------------------------------------------------------

treasuryAddr :: Addr
treasuryAddr =
    Addr Testnet (ScriptHashObj treasuryScriptHash) StakeRefNull

beneficiaryAddr :: Addr
beneficiaryAddr =
    Addr Testnet (ScriptHashObj beneficiaryScriptHash) StakeRefNull

walletAddr :: Addr
walletAddr =
    Addr Testnet (KeyHashObj walletPubKeyHash) StakeRefNull

permissionsRewardAccount :: AccountAddress
permissionsRewardAccount =
    AccountAddress Testnet (AccountId (ScriptHashObj permissionsStakeScriptHash))

----------------------------------------------------------------------
-- Required signers (4-of-4 multisig)
----------------------------------------------------------------------

{- | The contingency scope-owner key hash — the @selectedScopeOwner@
signer source from @report.json@.
-}
signerScopeOwner :: KeyHash Guard
signerScopeOwner =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "7095faf3d48d582fbae8b3f2e726670d7a35e2400c783d992bbdeffb"
            )
        )

-- | First @extraSigner@ key hash from the on-chain @intent.json@.
signerExtraOne :: KeyHash Guard
signerExtraOne =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "f3ab64b0f97dcf0f91232754603283df5d75a1201337432c04d23e2e"
            )
        )

{- | Second @extraSigner@ key hash — the network-wallet key, shared
with fixture 15's @signerNetworkWallet@.
-}
signerExtraTwo :: KeyHash Guard
signerExtraTwo =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1"
            )
        )

-- | Third @extraSigner@ key hash from the on-chain @intent.json@.
signerExtraThree :: KeyHash Guard
signerExtraThree =
    KeyHash
        ( fromJust
            ( hashFromStringAsHex
                "97e0f6d6c86dbebf15cc8fdf0981f939b2f2b70928a46511edd49df2"
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
@Pairs\<PolicyId, Pairs\<AssetName, Int\>\>@ map. Decoded from the
spend redeemer in the source @tx.cbor@: a single ADA entry of
205_000_000_000 lovelace under the empty policy id / empty asset
name. No USDM entry (the contingency disburse moves ADA only).
-}
disburseRedeemer :: RawData
disburseRedeemer =
    RawData
        ( PLC.Constr
            3
            [ PLC.Map
                [
                    ( PLC.B mempty
                    , PLC.Map [(PLC.B mempty, PLC.I 205_000_000_000)]
                    )
                ]
            ]
        )

{- | The on-chain stake-script withdrawal redeemer for the contingency
permissions account — an empty list (the permissions handler reads
its arguments from the script context, not from the redeemer
payload).
-}
withdrawRedeemer :: RawData
withdrawRedeemer = RawData (PLC.List [])

----------------------------------------------------------------------
-- Expected structural shape
----------------------------------------------------------------------

{- | Expected structural shape per A-002: 2 inputs (1 wallet + 1
treasury), 3 outputs, 1 withdrawal, 1 collateral, 4 reference
inputs, blueprint registered for the contingency treasury script.
-}
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 2
        , esOutputs = 3
        , esWithdrawals = 1
        , esCollateral = 1
        , esReferenceIns = 4
        , esBlueprintRef =
            Just "test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json"
        }

{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Fixtures.RewriteRedesign.S12BlueprintTyped
Description : Fixture 12 — typed SwapOrder datum emission (T103 / S3).
License     : Apache-2.0

First behaviour-changing on-disk fixture for feature 050
(blueprint-decode typed triples). Mirrors the SwapOrder shape
extracted from the operator-paste CBOR at
@test/fixtures/blockfrost-cache/operator-paste-2026-05-21.cbor.hex@.

The transaction body is the minimum needed to exercise typed
blueprint-driven datum emission plus the SC-002 cross-bnode
@bytesHex@ join the navigator RED spec asserts:

* Input 1 — user-wallet fuel input (pubkey credential, stub address).
* Output 1 — at the @amaru.swap.v2@ script-credential address
  ('swapScriptHash'). Carries an inline SwapOrder datum:
  @Constr 0 [Constr 0 [B 0x64f35d…]]@ —
  SwapOrder { recipient = PubKeyCredential 0x64f35d… }.
* Output 2 — at the recipient's pubkey-credential address (payment
  key-hash = 'recipientPubKeyHash'). No datum. Its payment-credential
  bytesHex equals the SwapOrder recipient's bytesHex; the navigator's
  @bytes-match-output-address@ invariant counts the cross-bnode
  occurrences (≥ 2) of that literal in the emitted Turtle.

The SwapOrder script hash and the recipient pubKeyHash are the
real on-chain values from the operator-paste; using the actual
mainnet bytes keeps the fixture's @rules.yaml@ blueprint
registration and the navigator's SC-002 invariant grounded in a
real-world Conway swap.
-}
module Fixtures.RewriteRedesign.S12BlueprintTyped (
    storyId,
    tx,
    shape,
    swapScriptHash,
    recipientPubKeyHash,
) where

import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Function ((&))
import Data.Maybe (fromJust)
import Lens.Micro ((.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Datum)
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    datumTxOutL,
    mkBasicTxOut,
 )
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (Payment))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.Data (mkInlineDatum)
import PlutusCore.Data qualified as PLC

import Fixtures.RewriteRedesign.Helpers (
    ExpectedShape (..),
    StoryId (..),
    TxBuilder (..),
    baseShape,
    mkTx,
    stubTxIn,
 )

import Cardano.Tx.Build (output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "12-blueprint-typed"

{- | The @amaru.swap.v2@ payment-credential script hash. Re-uses the
mainnet on-chain hash that fixture @11-amaru-treasury-swap-real@
already mirrors. Re-exported so 'Cardano.Tx.Graph.EmitGoldenSpec'
can register the blueprint index entry keyed on this hash.
-}
swapScriptHash :: ScriptHash
swapScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"
            )
        )

{- | The SwapOrder recipient's pubKeyHash, decoded from the
operator-paste CBOR's inline datum payload. The raw 28-byte
ByteString feeds both the inline-datum 'PLC.B' leaf and the
recipient output's payment key-hash, so the cross-bnode
@bytesHex@ join (SC-002) is realised end-to-end.
-}
recipientPubKeyHash :: ByteString
recipientPubKeyHash =
    case Base16.decode "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef" of
        Right bs -> bs
        Left err ->
            error
                ( "S12BlueprintTyped.recipientPubKeyHash: hex decode failed: "
                    <> err
                )

{- | Conway tx body for fixture 12: 1 input, 2 outputs. Output 1
sits at the SwapOrder script-credential address with an inline
SwapOrder datum; output 2 sits at the recipient's
pubkey-credential address.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1) -- user-wallet fuel input
    _ <- output (swapOrderOutput 5_000_000)
    _ <- output (recipientOutput 2_000_000)
    pure ()

-- | Expected structural shape for fixture 12.
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 1
        , esOutputs = 2
        , esBlueprintRef =
            Just "test/fixtures/rewrite-redesign/blueprints/swap-v2-datum.cip57.json"
        }

----------------------------------------------------------------------
-- Outputs
----------------------------------------------------------------------

{- | The SwapOrder output: at the @amaru.swap.v2@ script-credential
address with an inline SwapOrder datum
(@Constr 0 [Constr 0 [B <recipient>]]@ — PubKeyCredential branch).
-}
swapOrderOutput :: Integer -> TxOut ConwayEra
swapOrderOutput coin =
    mkBasicTxOut swapOrderAddr (MaryValue (Coin coin) (MultiAsset mempty))
        & datumTxOutL .~ swapOrderDatum

{- | The recipient output: at a pubkey-credential address whose
payment key-hash equals the SwapOrder recipient's pubKeyHash.
This is the cross-bnode anchor the navigator @bytes-match-output-address@
invariant asserts on.
-}
recipientOutput :: Integer -> TxOut ConwayEra
recipientOutput coin =
    mkBasicTxOut recipientAddr (MaryValue (Coin coin) (MultiAsset mempty))

swapOrderAddr :: Addr
swapOrderAddr = Addr Testnet (ScriptHashObj swapScriptHash) StakeRefNull

recipientAddr :: Addr
recipientAddr =
    Addr
        Testnet
        ( KeyHashObj
            ( KeyHash
                ( fromJust
                    ( hashFromStringAsHex
                        "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef"
                    )
                ) ::
                KeyHash Payment
            )
        )
        StakeRefNull

{- | The inline SwapOrder datum on output 1:
@Constr 0 [Constr 0 [B 0x64f35d…]]@ — the CIP-57 wire shape for
@SwapOrder { recipient = PubKeyCredential 0x64f35d… }@.
-}
swapOrderDatum :: Datum ConwayEra
swapOrderDatum =
    mkInlineDatum
        ( PLC.Constr
            0
            [PLC.Constr 0 [PLC.B recipientPubKeyHash]]
        )

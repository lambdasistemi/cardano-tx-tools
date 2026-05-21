{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Fixtures.RewriteRedesign.S14BlueprintDecodeFail
Description : Fixture 14 — wrong-shape blueprint → decodeError literal (T105 / S5).
License     : Apache-2.0

Third behaviour-changing on-disk fixture for feature 050
(blueprint-decode typed triples). The transaction body is byte-equal
to fixtures 12 + 13 (same SwapOrder inline datum on output 1 at the
@amaru.swap.v2@ script-credential address, same recipient
pubkey-credential output 2), but the fixture's @rules.yaml@
registers a __wrong-shape__ blueprint
('blueprints/swap-v2-wrong-shape.cip57.json') against the SwapOrder
script hash.

The wrong-shape blueprint declares the SwapOrder @recipient@ field
as a flat @bytes@ leaf at the top level, with no Credential /
PubKeyCredential wrapper. The real payload's @recipient@ is a
@Constr@ value, so 'decodeBlueprintData' returns
@'Left' ('BlueprintDataTypeMismatch' "bytes")@. The walker hits the
'DecodeFailed' branch in 'Cardano.Tx.Graph.Emit.Blueprint' and
emits the pre-#50 opaque @cardano:hasRawBytes@ literal AND exactly
one @cardano:decodeError@ literal on the Datum subject
(FR-005 / D-001d FIRST-error-only).

The @tx-graph@ exe additionally writes one stderr warning line per
@cardano:decodeError@ triple in the emitted graph, so an operator
sees the failure on stderr while the graph still exits 0.

The structural divergence is deliberately the smallest possible
(constructor wrap vs flat leaf on a single field) so the @expected.ttl@
diff against fixtures 12 + 13 reads as a single, focused behaviour
change.
-}
module Fixtures.RewriteRedesign.S14BlueprintDecodeFail (
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
storyId = StoryId "14-blueprint-decode-fail"

{- | The @amaru.swap.v2@ payment-credential script hash. Same on-chain
mainnet hash as fixtures 11 + 12 + 13. The fixture registers the
__wrong-shape__ blueprint
('blueprints/swap-v2-wrong-shape.cip57.json') against this hash —
that mismatch is the variable under test.
-}
swapScriptHash :: ScriptHash
swapScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"
            )
        )

{- | The SwapOrder recipient's pubKeyHash, byte-equal to fixtures 12
+ 13. Re-declared so this fixture's builder stands alone; the
shared bytes keep the cross-fixture byte-diff focused on the
blueprint shape difference, not the datum payload.
-}
recipientPubKeyHash :: ByteString
recipientPubKeyHash =
    case Base16.decode "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef" of
        Right bs -> bs
        Left err ->
            error
                ( "S14BlueprintDecodeFail.recipientPubKeyHash: hex decode failed: "
                    <> err
                )

{- | Conway tx body for fixture 14: 1 input, 2 outputs. Body
byte-equal to fixtures 12 + 13; the behaviour change is in the
fixture's @rules.yaml@ pointing at the wrong-shape blueprint.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1) -- user-wallet fuel input
    _ <- output (swapOrderOutput 5_000_000)
    _ <- output (recipientOutput 2_000_000)
    pure ()

{- | Expected structural shape for fixture 14. Same 1-input /
2-output counts as fixtures 12 + 13; 'esBlueprintRef' points at
the wrong-shape blueprint on disk so 'assertShape' fails loudly if
the file goes missing.
-}
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 1
        , esOutputs = 2
        , esBlueprintRef =
            Just
                "test/fixtures/rewrite-redesign/blueprints/swap-v2-wrong-shape.cip57.json"
        }

----------------------------------------------------------------------
-- Outputs
----------------------------------------------------------------------

{- | The SwapOrder output: at the @amaru.swap.v2@ script-credential
address with the inline SwapOrder datum
(@Constr 0 [Constr 0 [B <recipient>]]@). Byte-equal to
fixtures 12 + 13.
-}
swapOrderOutput :: Integer -> TxOut ConwayEra
swapOrderOutput coin =
    mkBasicTxOut swapOrderAddr (MaryValue (Coin coin) (MultiAsset mempty))
        & datumTxOutL .~ swapOrderDatum

{- | The recipient output: at a pubkey-credential address whose
payment key-hash equals the SwapOrder recipient's pubKeyHash. Same
as fixtures 12 + 13.
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

{- | The inline SwapOrder datum on output 1: byte-equal to
fixtures 12 + 13. Encoded as
@Constr 0 [Constr 0 [B 0x64f35d…]]@. Decoded against the
wrong-shape blueprint (@SwapOrder { recipient: bytes }@) this
payload's @recipient@ position carries a @Constr@ where the schema
expects a @bytes@ leaf, surfacing 'BlueprintDataTypeMismatch'
\"bytes\".
-}
swapOrderDatum :: Datum ConwayEra
swapOrderDatum =
    mkInlineDatum
        ( PLC.Constr
            0
            [PLC.Constr 0 [PLC.B recipientPubKeyHash]]
        )

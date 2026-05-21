{- |
Module      : Cardano.Tx.Graph.Emit.NativeScriptRefScriptSpec
Description : Reference-script script-language discrimination (T118 / S17).
License     : Apache-2.0

Asserts the T118 / S17 invariant: every reference-script
sub-block carries a discriminating @rdf:type@ — either
@cardano:NativeScript@ (when the ledger script is a Conway
@TimelockScript@) or @cardano:PlutusScript@ (when it's a Plutus
script). The Plutus branch additionally carries
@cardano:hasVersion N@ where N is the Plutus version (1/2/3/4).

The fixture-driven path is covered by
'Cardano.Tx.Graph.Emit.OutputScriptRefSpec' against the 11
rewrite-redesign fixtures (fixture 01's @stubRefScript@ is a
@TimelockScript@). This spec is the synthetic Path-A complement —
it exercises the native-script discrimination in isolation,
anchored on a minimal 'ConwayTx' witness so the
@cardano:NativeScript@ type triple is independently testable
without fixture churn.
-}
module Cardano.Tx.Graph.Emit.NativeScriptRefScriptSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Sequence.Strict qualified as StrictSeq

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (mkRequireSignatureTimelock)
import Cardano.Ledger.Alonzo.Scripts (AlonzoScript (NativeScript))
import Cardano.Ledger.Api.Scripts (Script)
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (mkBasicTxBody, outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (mkBasicTxOut, referenceScriptTxOutL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    StrictMaybe (SJust),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (KeyHash (..))
import Cardano.Ledger.Keys (KeyRole (..))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec =
    describe
        "Cardano.Tx.Graph.Emit reference-script language discrimination (T118)"
        $ do
            it "types a TimelockScript ref-script as cardano:NativeScript" $ do
                let bytes = emitBytes (txWithRefScript nativeRefScript)
                bytes
                    `shouldSatisfy` BS8.isInfixOf
                        "_:outputRefScript1 a cardano:NativeScript"
            it "TimelockScript ref-script has no cardano:hasVersion" $ do
                let bytes = emitBytes (txWithRefScript nativeRefScript)
                bytes
                    `shouldSatisfy` ( \b ->
                                        let refBlock = sliceRefBlock 1 b
                                         in not (BS8.isInfixOf "cardano:hasVersion" refBlock)
                                    )
            it "TimelockScript ref-script emits hasHash + hasRawBytes" $ do
                let bytes = emitBytes (txWithRefScript nativeRefScript)
                    refBlock = sliceRefBlock 1 bytes
                refBlock `shouldSatisfy` BS8.isInfixOf "cardano:hasHash"
                refBlock `shouldSatisfy` BS8.isInfixOf "cardano:hasRawBytes"

----------------------------------------------------------------------
-- Synthesis helpers
----------------------------------------------------------------------

baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

txWithRefScript :: Script ConwayEra -> ConwayTx
txWithRefScript script =
    baseTx
        & bodyTxL . outputsTxBodyL
            .~ StrictSeq.fromList
                [ mkBasicTxOut stubAddr (MaryValue (Coin 1_000_000) (MultiAsset mempty))
                    & referenceScriptTxOutL .~ SJust script
                ]

{- | A deterministic Conway native script: a single
'RequireSignature' timelock requiring a 28-byte witness
key-hash filled with @0x22@.
-}
nativeRefScript :: Script ConwayEra
nativeRefScript =
    NativeScript (mkRequireSignatureTimelock keyHash)
  where
    keyHash :: KeyHash Witness
    keyHash =
        KeyHash (fromJust (hashFromStringAsHex (replicate 56 '2')))

stubAddr :: Addr
stubAddr =
    Addr
        Testnet
        (KeyHashObj (KeyHash (fromJust (hashFromStringAsHex (replicate 56 '0'))) :: KeyHash Payment))
        StakeRefNull

emitBytes :: ConwayTx -> ByteString
emitBytes tx =
    case emit tx emptyUtxo [] [] of
        Right g -> serialize Turtle "native-ref-script-spec" g
        Left e -> error ("NativeScriptRefScriptSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

-- | Slice the bytes between @_:outputRefScriptK a@ and the next blank line.
sliceRefBlock :: Int -> ByteString -> ByteString
sliceRefBlock k bs =
    let needle =
            "_:outputRefScript"
                <> BS8.pack (show k)
                <> " a "
        (_, suf) = BS8.breakSubstring needle bs
        (block, _) = BS8.breakSubstring "\n\n" suf
     in block

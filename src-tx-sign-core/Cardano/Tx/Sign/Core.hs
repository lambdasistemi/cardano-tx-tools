{- |
Module      : Cardano.Tx.Sign.Core
Description : Pure payment-key signing core
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Four operations only: decode a @PaymentSigningKeyShelley_ed25519@ JSON
envelope, sign a Conway transaction's annotated body hash using ledger
DSIGN, construct a detached vkey witness, and attach that witness to the
transaction. No Vault, no encryption, no CLI parsing, no release checking,
no node-client access, no subprocess execution, no networking — this
sublibrary is buildable and runnable with @-build-node-tools@, unlike the
full @cardano-tx-tools@ library.

The 34-byte, @0x58 0x20@-prefixed length guard in 'decodePaymentSigningKey'
is load-bearing, not incidental: for the pinned Ed25519 DSIGN algorithm,
'Cardano.Crypto.DSIGN.Class.rawDeserialiseSignKeyDSIGN' succeeds for
/every/ 32-byte input, so this guard is the only thing standing between a
well-formed request and a signing key some other 32-byte value was
silently coerced into. It must stay ahead of the DSIGN decode, not after.
-}
module Cardano.Tx.Sign.Core (
    PureSignError (..),
    decodePaymentSigningKey,
    signConwayTxBodyHash,
    mkPaymentWitness,
    attachPaymentWitness,
) where

import Cardano.Crypto.DSIGN.Class (
    SignKeyDSIGN,
    SignedDSIGN,
    deriveVerKeyDSIGN,
    rawDeserialiseSignKeyDSIGN,
 )
import Cardano.Crypto.Hash.Class (Hash)
import Cardano.Ledger.Api.Tx (addrTxWitsL, bodyTxL)
import Cardano.Ledger.Core (witsTxL)
import Cardano.Ledger.Hashes (
    EraIndependentTxBody,
    HASH,
    extractHash,
    hashAnnotated,
 )
import Cardano.Ledger.Keys (
    DSIGN,
    KeyRole (Witness),
    VKey (..),
    WitVKey (..),
    signedDSIGN,
 )
import Cardano.Tx.Ledger (ConwayTx)
import Data.Aeson (Value, withObject, (.:))
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Lens.Micro ((%~), (&), (^.))

{- | Failure decoding a payment-key envelope. Both constructors carry full
rendered text so a consumer can reconstruct an operator-visible message
without this module knowing anything about its caller's error type.
-}
data PureSignError
    = -- | Malformed JSON shape, malformed hex, or malformed key bytes.
      PureSignMalformedSigningKey !Text
    | -- | A well-formed envelope naming an unsupported @"type"@.
      PureSignUnsupportedEnvelopeType !Text
    deriving stock (Eq, Show)

data PaymentSigningKeyEnvelope = PaymentSigningKeyEnvelope
    { pskeType :: !Text
    , pskeCborHex :: !Text
    }

{- | The parser's Aeson object label is the exact legacy string
@"SigningKeyEnvelope"@ (not this record's own name) so a non-object
input's rendered error text is byte-for-byte unchanged from base
'Cardano.Tx.Sign.Witness' — see NOTE-009 / the ninth
'Cardano.Tx.Sign.WitnessCompatSpec' row.
-}
parsePaymentSigningKeyEnvelope :: Value -> Parser PaymentSigningKeyEnvelope
parsePaymentSigningKeyEnvelope =
    withObject "SigningKeyEnvelope" $ \o ->
        PaymentSigningKeyEnvelope
            <$> o .: "type"
            <*> o .: "cborHex"

-- | 1. Decode a @PaymentSigningKeyShelley_ed25519@ JSON envelope.
decodePaymentSigningKey :: Value -> Either PureSignError (SignKeyDSIGN DSIGN)
decodePaymentSigningKey value = do
    envelope <-
        case parseEither parsePaymentSigningKeyEnvelope value of
            Left err -> Left (PureSignMalformedSigningKey (T.pack err))
            Right parsed -> Right parsed
    if pskeType envelope /= "PaymentSigningKeyShelley_ed25519"
        then Left (PureSignUnsupportedEnvelopeType (pskeType envelope))
        else do
            keyBytes <-
                case B16.decode (TE.encodeUtf8 (pskeCborHex envelope)) of
                    Left err ->
                        Left (PureSignMalformedSigningKey (T.pack ("hex decode: " <> err)))
                    Right bytes -> Right bytes
            rawKey <- decode32ByteCborBytestring keyBytes
            case rawDeserialiseSignKeyDSIGN @DSIGN rawKey of
                Nothing ->
                    Left
                        (PureSignMalformedSigningKey "could not decode Ed25519 signing key bytes")
                Just signKey -> Right signKey

-- | The load-bearing length\/prefix guard — see the module haddock.
decode32ByteCborBytestring :: ByteString -> Either PureSignError ByteString
decode32ByteCborBytestring bytes
    | BS.length bytes == 34 && BS.take 2 bytes == "\x58\x20" =
        Right (BS.drop 2 bytes)
    | otherwise =
        Left (PureSignMalformedSigningKey "expected a 32-byte CBOR bytestring signing key")

-- | 2. Sign the transaction's annotated body hash using ledger DSIGN.
signConwayTxBodyHash ::
    SignKeyDSIGN DSIGN ->
    ConwayTx ->
    SignedDSIGN DSIGN (Hash HASH EraIndependentTxBody)
signConwayTxBodyHash signKey tx =
    signedDSIGN signKey (extractHash (hashAnnotated (tx ^. bodyTxL)))

-- | 3. Construct a detached vkey witness.
mkPaymentWitness ::
    SignKeyDSIGN DSIGN ->
    SignedDSIGN DSIGN (Hash HASH EraIndependentTxBody) ->
    WitVKey Witness
mkPaymentWitness signKey =
    WitVKey (VKey (deriveVerKeyDSIGN signKey))

{- | 4. Attach the witness to the transaction and return the signed
transaction.
-}
attachPaymentWitness :: WitVKey Witness -> ConwayTx -> ConwayTx
attachPaymentWitness witness tx =
    tx & witsTxL . addrTxWitsL %~ Set.insert witness

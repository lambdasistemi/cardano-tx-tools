{- |
Module      : Cardano.Tx.Sign.CoreSpec
Description : #181 upstream pure signing core — focused proof

Exercises "Cardano.Tx.Sign.Core"'s four named operations (decode envelope,
sign body hash, construct WitVKey, attach witness) composed explicitly —
composition is not reimplementation per the parent ruling that dropped the
PLAN-001 composed fifth entry point.

Reuses the real, independently-generated fixtures at
@test\/fixtures\/tx-sign\/@ (real @cardano-cli@ output, per
@fixture-source.md@) rather than a fabricated envelope, per Opus navigator
guidance. The positive test's key-hash oracle is computed independently —
straight from 'rawDeserialiseSignKeyDSIGN'\/'deriveVerKeyDSIGN'\/'hashKey'
over the fixture's raw key bytes — never by calling
'Cardano.Tx.Sign.Core.decodePaymentSigningKey' a second time (C2). It also
asserts two direct fixture equalities (C6\/C7): the freshly-serialized
detached witness equals @witness.expected.hex@ — which pins
'Cardano.Tx.Sign.Core.signConwayTxBodyHash' itself, not just the derived key
hash — and the freshly-serialized signed transaction equals
@signed.expected.cbor.hex@ as an additional cross-check.

@cabal test@ runs with CWD at the package root, and the frozen gate invokes
it from the package root too, so the relative fixture paths below hold; this
spec must not @cd@.
-}
module Cardano.Tx.Sign.CoreSpec (spec) where

import Cardano.Crypto.DSIGN.Class (deriveVerKeyDSIGN, rawDeserialiseSignKeyDSIGN)
import Cardano.Ledger.Api.Era (eraProtVerLow)
import Cardano.Ledger.Api.Tx (addrTxWitsL)
import Cardano.Ledger.Binary (DecCBOR (decCBOR), decodeFullAnnotator, serialize)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (witsTxL)
import Cardano.Ledger.Hashes (KeyHash (..))
import Cardano.Ledger.Keys (DSIGN, KeyRole (Guard, Witness), VKey (..), WitVKey (..), hashKey)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Sign.Core (
    PureSignError (..),
    attachPaymentWitness,
    decodePaymentSigningKey,
    mkPaymentWitness,
    signConwayTxBodyHash,
 )
import Data.Aeson (Value, eitherDecodeStrict', object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BSL
import Data.Set qualified as Set
import Lens.Micro ((^.))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

{- | Raw 32-byte Ed25519 signing key inside the fixture's @cborHex@, with
the CBOR @5820@ bytestring-length prefix stripped.
-}
fixtureRawKeyHex :: String
fixtureRawKeyHex =
    "83c69e0facc37e938558a50b4335f0ca9855857bb5625f583a68464f54496bde"

loadFixtureBytes :: FilePath -> IO ByteString
loadFixtureBytes name = BS.readFile ("test/fixtures/tx-sign/" <> name)

loadFixtureHexBytes :: FilePath -> IO ByteString
loadFixtureHexBytes name = do
    hex <- loadFixtureBytes name
    case B16.decode (BS8.filter (`notElem` ("\n\r " :: String)) hex) of
        Left err -> fail ("fixture hex decode failed: " <> err)
        Right bytes -> pure bytes

{- | The fixture's raw hex text (not decoded), whitespace-trimmed, for
direct hex-to-hex comparison against freshly-serialized bytes.
-}
loadFixtureHexText :: FilePath -> IO ByteString
loadFixtureHexText name = do
    hex <- loadFixtureBytes name
    pure (BS8.filter (`notElem` ("\n\r " :: String)) hex)

{- | Test-only raw-CBOR loader for a fixture transaction. Mirrors the shape
of the gated main library's own 'Cardano.Tx.Sign.AttachWitness.decodeUnsignedTxHex'
(which this ungated test-suite cannot import), not a second production
decoder — loading a fixture is not "payment-key decoding".
-}
decodeFixtureTx :: ByteString -> IO ConwayTx
decodeFixtureTx raw =
    case decodeFullAnnotator (eraProtVerLow @ConwayEra) "ConwayTx" decCBOR (BSL.fromStrict raw) of
        Right tx -> pure tx
        Left err -> fail ("fixture tx decode failed: " <> show err)

loadPaymentEnvelope :: IO Value
loadPaymentEnvelope = do
    bytes <- loadFixtureBytes "payment.skey"
    case eitherDecodeStrict' bytes of
        Left err -> fail ("fixture envelope decode failed: " <> err)
        Right value -> pure value

{- | Independent oracle: the fixture key's derived payment key hash, computed
straight from crypto primitives, never by calling 'decodePaymentSigningKey'.
-}
oracleKeyHash :: Either String (KeyHash Guard)
oracleKeyHash = do
    rawBytes <-
        either (Left . ("oracle hex decode: " <>)) Right $
            B16.decode (BS8.pack fixtureRawKeyHex)
    case rawDeserialiseSignKeyDSIGN @DSIGN rawBytes of
        Nothing -> Left "oracle: could not decode Ed25519 signing key bytes"
        Just signKey ->
            let vkey = VKey (deriveVerKeyDSIGN signKey) :: VKey Witness
                KeyHash h = hashKey vkey
             in Right (KeyHash h)

malformedEnvelope :: Value
malformedEnvelope = object ["cborHex" .= ("00" :: String)]

unsupportedTypeEnvelope :: Value
unsupportedTypeEnvelope =
    object
        [ "type" .= ("PaymentExtendedSigningKeyShelley_ed25519bip32" :: String)
        , "cborHex" .= ("5820" <> "00" :: String)
        ]

spec :: Spec
spec = describe "Cardano.Tx.Sign.Core (four operations, composed)" $ do
    it "signs a Conway transaction from a payment key envelope" $ do
        envelope <- loadPaymentEnvelope
        unsignedBytes <- loadFixtureHexBytes "unsigned.cbor.hex"
        unsignedTx <- decodeFixtureTx unsignedBytes
        expectedHash <- either (fail . ("oracle failed: " <>)) pure oracleKeyHash
        expectedWitnessHex <- loadFixtureHexText "witness.expected.hex"
        expectedSignedHex <- loadFixtureHexText "signed.expected.cbor.hex"
        case decodePaymentSigningKey envelope of
            Left err -> fail ("decodePaymentSigningKey failed: " <> show err)
            Right signKey -> do
                let signature = signConwayTxBodyHash signKey unsignedTx
                    witness = mkPaymentWitness signKey signature
                    signedTx = attachPaymentWitness witness unsignedTx
                -- C6: constrain signConwayTxBodyHash itself, not just the key
                -- hash — the freshly-encoded witness bytes must equal the
                -- real cardano-cli-produced detached witness, which directly
                -- pins the signed body hash (a wrong-bytes signature would
                -- still carry the right key hash but would fail here).
                B16.encode (BSL.toStrict (serialize (eraProtVerLow @ConwayEra) witness))
                    `shouldBe` expectedWitnessHex
                -- C7: the additional signed-tx cross-check the module
                -- Haddock claims.
                B16.encode (BSL.toStrict (serialize (eraProtVerLow @ConwayEra) signedTx))
                    `shouldBe` expectedSignedHex
                case Set.toList (signedTx ^. witsTxL . addrTxWitsL) of
                    [WitVKey vkey _] -> do
                        let KeyHash h = hashKey vkey
                        KeyHash h `shouldBe` expectedHash
                    other ->
                        fail ("expected exactly one attached vkey witness, got " <> show (length other))

    it "rejects malformed payment key envelopes" $
        decodePaymentSigningKey malformedEnvelope `shouldSatisfy` isMalformed

    it "rejects unsupported payment key envelope types" $
        decodePaymentSigningKey unsupportedTypeEnvelope `shouldSatisfy` isUnsupportedType
  where
    isMalformed (Left (PureSignMalformedSigningKey _)) = True
    isMalformed _ = False
    isUnsupportedType (Left (PureSignUnsupportedEnvelopeType _)) = True
    isUnsupportedType _ = False

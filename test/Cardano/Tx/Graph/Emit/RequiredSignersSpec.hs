{- |
Module      : Cardano.Tx.Graph.Emit.RequiredSignersSpec
Description : Required-signers emission invariant (T116 / S15).
License     : Apache-2.0

Asserts the T116 / S15 invariant: every key hash declared in the
body's @reqSignerHashes@ set surfaces as a
@_:tx cardano:hasRequiredSigner "\<hex\>"@ triple on the
transaction subject block, in ascending-sorted order. An empty
required-signers set elides the predicate.

The required-signers field is what Plutus scripts consult via the
script context to gate spending. Pre-T116 the emit walker
fail-loudly-aborted on a non-empty required-signers set
('PUnsupportedLeafType: ConwayRequiredSignersValue'), which
surfaced on the operator's 2026-05-21 morning tx. This spec
closes that regression at the unit-test layer; the
@BlockfrostSampleSmokeSpec@ terminal gate (T127) closes it at the
real-chain layer.
-}
module Cardano.Tx.Graph.Emit.RequiredSignersSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (mkBasicTxBody, reqSignerHashesTxBodyL)
import Cardano.Ledger.Hashes (KeyHash (..))
import Cardano.Ledger.Keys (KeyRole (..))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit required signers (T116 / S15)" $ do
    it "elides cardano:hasRequiredSigner when reqSignerHashes is empty" $ do
        let bytes = emitBytes baseTx
        bytes `shouldSatisfy` (not . BS8.isInfixOf "cardano:hasRequiredSigner")
    it "emits cardano:hasRequiredSigner as Identifier bnode (single, T122c)" $ do
        let bytes = emitBytes (baseTx & requiredSigners [stubKeyHash 0xaa])
            hex = BS8.replicate 56 'a'
        -- T122c / S22: predicate binds to a PaymentKey
        -- Identifier bnode under the @_:cred_paymentkey_…@
        -- name. The full 56-hex bytes literal is carried by
        -- the bnode's @cardano:bytesHex@ triple.
        bytes
            `shouldSatisfy` BS8.isInfixOf
                "cardano:hasRequiredSigner _:cred_paymentkey_"
        bytes `shouldSatisfy` BS8.isInfixOf "a cardano:Identifier"
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:leafType \"PaymentKey\""
        bytes
            `shouldSatisfy` BS8.isInfixOf ("cardano:bytesHex \"" <> hex <> "\"")
    it "emits one Identifier bnode per signer, ascending sort (T122c)" $ do
        let bytes =
                emitBytes
                    ( baseTx
                        & requiredSigners
                            [stubKeyHash 0xbb, stubKeyHash 0xaa, stubKeyHash 0xcc]
                    )
            hexA = BS8.replicate 56 'a'
            hexB = BS8.replicate 56 'b'
            hexC = BS8.replicate 56 'c'
        -- All three emit as bnode references (the prefix
        -- truncates the hex to 16 chars).
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:hasRequiredSigner _:cred_paymentkey_" <> BS8.take 16 hexA)
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:hasRequiredSigner _:cred_paymentkey_" <> BS8.take 16 hexB)
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:hasRequiredSigner _:cred_paymentkey_" <> BS8.take 16 hexC)
        -- Ascending byte order: 'a' < 'b' < 'c' on the
        -- @hasRequiredSigner@ predicate position.
        let needleA = "cardano:hasRequiredSigner _:cred_paymentkey_" <> BS8.take 16 hexA
            needleB = "cardano:hasRequiredSigner _:cred_paymentkey_" <> BS8.take 16 hexB
            needleC = "cardano:hasRequiredSigner _:cred_paymentkey_" <> BS8.take 16 hexC
            posA = BS8.length (fst (BS8.breakSubstring needleA bytes))
            posB = BS8.length (fst (BS8.breakSubstring needleB bytes))
            posC = BS8.length (fst (BS8.breakSubstring needleC bytes))
        (posA, posB) `shouldSatisfy` uncurry (<)
        (posB, posC) `shouldSatisfy` uncurry (<)

----------------------------------------------------------------------
-- Synthesis helpers
----------------------------------------------------------------------

baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

requiredSigners :: [KeyHash Guard] -> ConwayTx -> ConwayTx
requiredSigners signers =
    bodyTxL . reqSignerHashesTxBodyL .~ Set.fromList signers

{- | A 28-byte 'KeyHash' (role 'Guard' — Conway required-signers)
filled with the given hex-nibble byte (0..255). Used to exercise
the emission path without routing through a real key generation
or fixture.
-}
stubKeyHash :: Int -> KeyHash Guard
stubKeyHash n =
    KeyHash (fromJust (hashFromStringAsHex (concat (replicate 28 (hexByte n)))))
  where
    hexByte b = [d (b `div` 16), d (b `mod` 16)]
    d k = "0123456789abcdef" !! k

emitBytes :: ConwayTx -> ByteString
emitBytes tx =
    case emit tx emptyUtxo [] of
        Right g -> serialize Turtle "required-signers-spec" g
        Left e -> error ("RequiredSignersSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

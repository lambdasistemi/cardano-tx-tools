{- |
Module      : Cardano.Tx.Graph.Emit.BodyRootSpec
Description : Body-root predicate emission (T107 / S6).
License     : Apache-2.0

Asserts the T107 / S6 invariant: the @_:tx@ subject block carries
the four Conway body-root predicates iff their corresponding
'TxBody' field is populated:

* @cardano:hasValidityInterval _:interval1@ + a separate
  @_:interval1@ sub-block carrying @cardano:intervalStart@
  and\/or @cardano:intervalEnd@ — present iff at least one of
  @invalidBefore@ \/ @invalidHereafter@ is 'SJust';
* @cardano:networkId@ — present iff @networkIdTxBodyL@ is 'SJust';
* @cardano:scriptDataHash@ — present iff
  @scriptIntegrityHashTxBodyL@ is 'SJust';
* @cardano:auxiliaryDataHash@ — present iff @auxDataHashTxBodyL@
  is 'SJust'.

The eleven rewrite-redesign fixtures all leave these four fields
at @SNothing@; the byte-equal goldens pin the elision branch.
The populated branches are exercised here via synthetic
'ConwayTx' values built by lens-set on the 'mkBasicTxBody' default
body (no DSL combinator covers the relevant fields).
-}
module Cardano.Tx.Graph.Emit.BodyRootSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Crypto.Hash qualified as Hash
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.TxBody (ScriptIntegrityHash)
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (
    auxDataHashTxBodyL,
    mkBasicTxBody,
    networkIdTxBodyL,
    scriptIntegrityHashTxBodyL,
    vldtTxBodyL,
 )
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    SlotNo (..),
    StrictMaybe (SJust, SNothing),
 )
import Cardano.Ledger.Hashes (HASH, TxAuxDataHash (..), unsafeMakeSafeHash)

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit body-root predicates (T107 / S6)" $ do
    validityIntervalSpecs
    networkIdSpecs
    scriptDataHashSpecs
    auxiliaryDataHashSpecs

----------------------------------------------------------------------
-- cardano:hasValidityInterval
----------------------------------------------------------------------

validityIntervalSpecs :: Spec
validityIntervalSpecs = describe "cardano:hasValidityInterval" $ do
    it "elides hasValidityInterval when both bounds are SNothing" $ do
        let bytes = emitBytes (baseTx & vldt SNothing SNothing)
        txBlockOfBytes bytes
            `shouldSatisfy` (not . BS8.isInfixOf "cardano:hasValidityInterval")
        bytes `shouldSatisfy` (not . BS8.isInfixOf "cardano:intervalStart")
        bytes `shouldSatisfy` (not . BS8.isInfixOf "cardano:intervalEnd")
    it "emits start + end when both bounds are SJust" $ do
        let bytes =
                emitBytes
                    (baseTx & vldt (SJust 1_000_000) (SJust 1_500_000))
        txBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:hasValidityInterval _:interval1"
        intervalBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:intervalStart 1000000"
        intervalBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:intervalEnd 1500000"
    it "emits start only when invalidHereafter is SNothing" $ do
        let bytes = emitBytes (baseTx & vldt (SJust 1_000_000) SNothing)
        txBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:hasValidityInterval _:interval1"
        intervalBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:intervalStart 1000000"
        intervalBlockOfBytes bytes
            `shouldSatisfy` (not . BS8.isInfixOf "cardano:intervalEnd")
    it "emits end only when invalidBefore is SNothing" $ do
        let bytes = emitBytes (baseTx & vldt SNothing (SJust 1_500_000))
        txBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:hasValidityInterval _:interval1"
        intervalBlockOfBytes bytes
            `shouldSatisfy` (not . BS8.isInfixOf "cardano:intervalStart")
        intervalBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:intervalEnd 1500000"

----------------------------------------------------------------------
-- cardano:networkId
----------------------------------------------------------------------

networkIdSpecs :: Spec
networkIdSpecs = describe "cardano:networkId" $ do
    it "elides networkId when SNothing" $ do
        let bytes = emitBytes baseTx
        txBlockOfBytes bytes
            `shouldSatisfy` (not . BS8.isInfixOf "cardano:networkId")
    it "emits networkId 0 for Testnet" $ do
        let bytes = emitBytes (baseTx & networkId (SJust Testnet))
        txBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:networkId 0"
    it "emits networkId 1 for Mainnet" $ do
        let bytes = emitBytes (baseTx & networkId (SJust Mainnet))
        txBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:networkId 1"

----------------------------------------------------------------------
-- cardano:scriptDataHash
----------------------------------------------------------------------

scriptDataHashSpecs :: Spec
scriptDataHashSpecs = describe "cardano:scriptDataHash" $ do
    it "elides scriptDataHash when SNothing" $ do
        let bytes = emitBytes baseTx
        txBlockOfBytes bytes
            `shouldSatisfy` (not . BS8.isInfixOf "cardano:scriptDataHash")
    it "emits scriptDataHash Identifier bnode when SJust (T122c)" $ do
        let h = stubScriptIntegrityHash 0xaa
            bytes = emitBytes (baseTx & scriptDataHash (SJust h))
            hex = BS8.replicate 64 'a'
        -- T122c / S22: hash is now an Identifier-typed bnode
        -- under the @_:hash_scriptdata_…@ name, not a flat
        -- string literal.
        txBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:scriptDataHash _:hash_scriptdata_"
        bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:leafType \"ScriptDataHash\""
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:bytesHex \"" <> hex <> "\"")

----------------------------------------------------------------------
-- cardano:auxiliaryDataHash
----------------------------------------------------------------------

auxiliaryDataHashSpecs :: Spec
auxiliaryDataHashSpecs = describe "cardano:auxiliaryDataHash" $ do
    it "elides auxiliaryDataHash when SNothing" $ do
        let bytes = emitBytes baseTx
        txBlockOfBytes bytes
            `shouldSatisfy` (not . BS8.isInfixOf "cardano:auxiliaryDataHash")
    it "emits auxiliaryDataHash Identifier bnode when SJust (T122c)" $ do
        let h = TxAuxDataHash (unsafeMakeSafeHash (rawHash 0xbb))
            bytes = emitBytes (baseTx & auxDataHash (SJust h))
            hex = BS8.replicate 64 'b'
        txBlockOfBytes bytes
            `shouldSatisfy` BS8.isInfixOf
                "cardano:auxiliaryDataHash _:hash_auxiliarydata_"
        bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:leafType \"AuxiliaryDataHash\""
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:bytesHex \"" <> hex <> "\"")

----------------------------------------------------------------------
-- Synthesis helpers
----------------------------------------------------------------------

{- | An empty Conway tx: zero inputs, zero outputs, zero of everything.
All four body-root predicate fields default to 'SNothing' \/
@ValidityInterval SNothing SNothing@.
-}
baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

-- | Set the body's 'ValidityInterval'.
vldt ::
    StrictMaybe SlotNo ->
    StrictMaybe SlotNo ->
    ConwayTx ->
    ConwayTx
vldt before after =
    bodyTxL . vldtTxBodyL .~ ValidityInterval before after

-- | Set the body's @networkIdTxBodyL@.
networkId :: StrictMaybe Network -> ConwayTx -> ConwayTx
networkId n = bodyTxL . networkIdTxBodyL .~ n

-- | Set the body's @scriptIntegrityHashTxBodyL@.
scriptDataHash ::
    StrictMaybe ScriptIntegrityHash -> ConwayTx -> ConwayTx
scriptDataHash h = bodyTxL . scriptIntegrityHashTxBodyL .~ h

-- | Set the body's @auxDataHashTxBodyL@.
auxDataHash :: StrictMaybe TxAuxDataHash -> ConwayTx -> ConwayTx
auxDataHash h = bodyTxL . auxDataHashTxBodyL .~ h

{- | A 32-byte 'ScriptIntegrityHash' filled with the given byte
(0..255). Used to exercise the @cardano:scriptDataHash@ branch
without routing through CBOR.
-}
stubScriptIntegrityHash :: Int -> ScriptIntegrityHash
stubScriptIntegrityHash = unsafeMakeSafeHash . rawHash

-- | A raw 32-byte 'Hash' filled with the given byte (0..255).
rawHash :: Int -> Hash.Hash HASH a
rawHash b =
    fromJust (hashFromStringAsHex (concat (replicate 32 (hexByte b))))
  where
    hexByte n = [d (n `div` 16), d (n `mod` 16)]
    d k = "0123456789abcdef" !! k

----------------------------------------------------------------------
-- Bytes helpers
----------------------------------------------------------------------

emitBytes :: ConwayTx -> ByteString
emitBytes tx =
    case emit tx emptyUtxo [] [] of
        Right g -> serialize Turtle "body-root-spec" g
        Left e -> error ("BodyRootSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

{- | The @_:tx@ subject block — bytes from the
@_:tx a cardano:Transaction@ anchor to the next blank line.
-}
txBlockOfBytes :: ByteString -> ByteString
txBlockOfBytes = sliceFrom "_:tx a cardano:Transaction"

{- | The @_:interval1@ subject sub-block — bytes from the
@_:interval1@ subject-position anchor (after the blank line
that separates it from the parent @_:tx@ block) to the next
blank line. Returns @""@ when no such block exists. The
@"\n\n_:interval1 "@ pattern dodges the object-position
occurrence of @_:interval1@ inside the parent block.
-}
intervalBlockOfBytes :: ByteString -> ByteString
intervalBlockOfBytes bs =
    case BS8.breakSubstring "\n\n_:interval1 " bs of
        (_, suf)
            | BS.null suf -> ""
            | otherwise ->
                let body = BS8.drop 2 suf -- skip "\n\n"
                    (block, _) = BS8.breakSubstring "\n\n" body
                 in block

sliceFrom :: ByteString -> ByteString -> ByteString
sliceFrom needle bs =
    case BS8.breakSubstring needle bs of
        (_, suf)
            | BS.null suf -> ""
            | otherwise ->
                let (block, _) = BS8.breakSubstring "\n\n" suf
                 in block

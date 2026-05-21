{- |
Module      : Cardano.Tx.Graph.Emit.CertVariantsSpec
Description : Exhaustive Conway cert-variant emit cover (T120 / S19).
License     : Apache-2.0

Asserts the T120 / S19 invariant: every Conway 'TxCert' variant
the body walker reaches emits without 'PUnsupportedLeafType'.

The pre-T120 emitter only positively dispatched the two
StakeDelegation + VoteDelegation patterns; every other variant
(@RegDeposit@, @UnRegDeposit@, @RegDepositDeleg@,
@AuthCommitteeHotKey@, @ResignCommitteeCold@, @RegDRep@,
@UnRegDRep@, @UpdateDRep@, and the Shelley-passthrough
@RegCert@ / @UnRegCert@ / @PoolRegCert@ / @PoolRetireCert@)
fell through the @_ -> Left PUnsupportedLeafType@ catch-all
and crashed the emitter on any real-chain tx that carried one.

T120 lands the OpaqueLeaf fallback shape for those variants —
typed @cardano:Certificate, cardano:OpaqueLeaf@ with a
@cardano:leafType@ discriminator and @cardano:hasRawBytes@
CBOR-hex payload. This spec exercises a representative variant
(@RegDepositTxCert@) to verify the fallback emits the expected
shape; the exhaustivity test (T115) covers compile-time
totality of the pattern match.
-}
module Cardano.Tx.Graph.Emit.CertVariantsSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (certsTxBodyL, mkBasicTxBody)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.TxCert (
    pattern RegDepositTxCert,
 )
import Cardano.Ledger.Core (TxCert)
import Cardano.Ledger.Credential (Credential (KeyHashObj))
import Cardano.Ledger.Hashes (KeyHash (..))
import Cardano.Ledger.Keys (KeyRole (..))
import Data.Sequence.Strict qualified as StrictSeq

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit cert variants (T120 / S19)" $ do
    it "RegDepositTxCert emits without PUnsupportedLeafType" $ do
        let bytes = emitBytes (txWithCert regDepositCert)
        bytes `shouldSatisfy` BS8.isInfixOf "_:cert1 a cardano:Certificate"
    it "RegDepositTxCert emits the cardano:OpaqueLeaf fallback type" $ do
        let bytes = emitBytes (txWithCert regDepositCert)
        bytes `shouldSatisfy` BS8.isInfixOf "a cardano:OpaqueLeaf"
    it "RegDepositTxCert emits cardano:leafType \"ConwayRegDeposit\"" $ do
        let bytes = emitBytes (txWithCert regDepositCert)
        bytes
            `shouldSatisfy` BS8.isInfixOf
                "cardano:leafType \"ConwayRegDeposit\""
    it "RegDepositTxCert emits cardano:hasRawBytes hex literal" $ do
        let bytes = emitBytes (txWithCert regDepositCert)
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:hasRawBytes \""

----------------------------------------------------------------------
-- Synthesis helpers
----------------------------------------------------------------------

baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

txWithCert :: TxCert ConwayEra -> ConwayTx
txWithCert cert =
    baseTx & bodyTxL . certsTxBodyL .~ StrictSeq.fromList [cert]

{- | A stake-credential registration certificate carrying an
explicit deposit field. RegDepositTxCert is one of the Conway
variants the pre-T120 walker rejected.
-}
regDepositCert :: TxCert ConwayEra
regDepositCert =
    RegDepositTxCert (KeyHashObj stakeKey) (Coin 2_000_000)
  where
    stakeKey :: KeyHash Staking
    stakeKey =
        KeyHash (fromJust (hashFromStringAsHex (replicate 56 '7')))

emitBytes :: ConwayTx -> ByteString
emitBytes tx =
    case emit tx emptyUtxo [] [] of
        Right g -> serialize Turtle "cert-variants-spec" g
        Left e -> error ("CertVariantsSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

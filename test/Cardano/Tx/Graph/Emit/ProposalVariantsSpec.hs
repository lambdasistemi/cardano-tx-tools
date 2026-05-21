{- |
Module      : Cardano.Tx.Graph.Emit.ProposalVariantsSpec
Description : Exhaustive Conway proposal-variety emit cover (T121 / S20).
License     : Apache-2.0

Asserts the T121 / S20 invariant: every 'GovAction' constructor
emits without 'PUnsupportedLeafType'. The pre-T121 walker only
positively dispatched @TreasuryWithdrawals@; every other variant
(@ParameterChange@, @HardForkInitiation@, @NoConfidence@,
@UpdateCommittee@, @NewConstitution@, @InfoAction@) crashed the
emitter on any real-chain proposal that carried one.

T121 generalizes the D-006 fallback so every variant emits the
same shape — typed @cardano:Datum@ sub-block carrying
@cardano:decodedAs "\<varietyTag\>"@ + @cardano:hasRawBytes@
CBOR-hex — with the @decodedAs@ literal naming the constructor.

This spec exercises a representative variant
(@InfoAction@) to verify the fallback emits the expected
shape with the @"InfoAction"@ tag; the exhaustivity test
(T115) covers compile-time totality of the pattern match.
-}
module Cardano.Tx.Graph.Emit.ProposalVariantsSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (AccountAddress (..), AccountId (..))
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (mkBasicTxBody, proposalProceduresTxBodyL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    textToUrl,
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Governance (
    Anchor (..),
    GovAction (InfoAction),
    ProposalProcedure (..),
 )
import Cardano.Ledger.Credential (Credential (KeyHashObj))
import Cardano.Ledger.Hashes (KeyHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyRole (..))
import Data.OSet.Strict qualified as OSet

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit proposal variants (T121 / S20)" $ do
    it "InfoAction proposal emits without PUnsupportedLeafType" $ do
        let bytes = emitBytes (txWithProposal infoActionProposal)
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:hasProposal _:proposal1"
    it "InfoAction proposal datum sub-block carries decodedAs \"InfoAction\"" $ do
        let bytes = emitBytes (txWithProposal infoActionProposal)
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:decodedAs \"InfoAction\""
    it "InfoAction proposal datum sub-block carries hasRawBytes literal" $ do
        let bytes = emitBytes (txWithProposal infoActionProposal)
        bytes
            `shouldSatisfy` BS8.isInfixOf "_:proposalDatum1 a cardano:Datum"
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:hasRawBytes \""

----------------------------------------------------------------------
-- Synthesis helpers
----------------------------------------------------------------------

baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

txWithProposal :: ProposalProcedure ConwayEra -> ConwayTx
txWithProposal proposal =
    baseTx
        & bodyTxL . proposalProceduresTxBodyL .~ OSet.fromList [proposal]

infoActionProposal :: ProposalProcedure ConwayEra
infoActionProposal =
    ProposalProcedure (Coin 100_000_000_000) returnAddr InfoAction anchor
  where
    returnAddr :: AccountAddress
    returnAddr =
        AccountAddress
            Testnet
            (AccountId (KeyHashObj (KeyHash hash :: KeyHash Staking)))
    hash = fromJust (hashFromStringAsHex (replicate 56 '4'))
    anchor =
        Anchor
            (fromJust (textToUrl 64 "https://example.invalid/info-anchor"))
            (unsafeMakeSafeHash (fromJust (hashFromStringAsHex (replicate 64 '0'))))

emitBytes :: ConwayTx -> ByteString
emitBytes tx =
    case emit tx emptyUtxo [] [] of
        Right g -> serialize Turtle "proposal-variants-spec" g
        Left e -> error ("ProposalVariantsSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

{- |
Module      : Cardano.Tx.Graph.Emit.TotalCollateralSpec
Description : Total-collateral + collateral-return emission (T117 / S16).
License     : Apache-2.0

Asserts the T117 / S16 invariant: the @_:tx@ subject block
carries @cardano:totalCollateral N@ iff
@totalCollateralTxBodyL@ is 'SJust', and
@cardano:hasCollateralReturn _:collateralReturn1@ iff
@collateralReturnTxBodyL@ is 'SJust'. When set, the
collateral-return output emits its own sub-block typed
@cardano:Output@ with the standard @cardano:atAddress@ +
@cardano:lovelace@ predicates.

Pre-T117 the emit walker fail-loudly-aborted on a 'SJust'
total-collateral
('PUnsupportedLeafType: ConwayTotalCollateralValue'). This spec
closes that regression at the unit-test layer; the
@BlockfrostSampleSmokeSpec@ terminal gate (T127) closes it at the
real-chain layer.
-}
module Cardano.Tx.Graph.Emit.TotalCollateralSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (
    collateralReturnTxBodyL,
    mkBasicTxBody,
    totalCollateralTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (mkBasicTxOut)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    StrictMaybe (SJust),
 )
import Cardano.Ledger.Coin (Coin (..))
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
        "Cardano.Tx.Graph.Emit total collateral + collateral return (T117)"
        $ do
            totalCollateralSpec
            collateralReturnSpec

totalCollateralSpec :: Spec
totalCollateralSpec = describe "cardano:totalCollateral" $ do
    it "elides totalCollateral when SNothing" $ do
        let bytes = emitBytes baseTx
        bytes `shouldSatisfy` (not . BS8.isInfixOf "cardano:totalCollateral")
    it "emits totalCollateral N when SJust" $ do
        let bytes =
                emitBytes
                    ( baseTx
                        & bodyTxL . totalCollateralTxBodyL .~ SJust (Coin 5_000_000)
                    )
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:totalCollateral 5000000"

collateralReturnSpec :: Spec
collateralReturnSpec = describe "cardano:hasCollateralReturn" $ do
    it "elides hasCollateralReturn when SNothing" $ do
        let bytes = emitBytes baseTx
        bytes
            `shouldSatisfy` (not . BS8.isInfixOf "cardano:hasCollateralReturn")
        bytes `shouldSatisfy` (not . BS8.isInfixOf "_:collateralReturn1")
    it "emits the edge + _:collateralReturn1 sub-block when SJust" $ do
        let txOut = mkBasicTxOut stubAddr (MaryValue (Coin 1_000_000) (MultiAsset mempty))
            bytes =
                emitBytes
                    ( baseTx
                        & bodyTxL . collateralReturnTxBodyL .~ SJust txOut
                    )
        bytes
            `shouldSatisfy` BS8.isInfixOf
                "cardano:hasCollateralReturn _:collateralReturn1"
        bytes
            `shouldSatisfy` BS8.isInfixOf "_:collateralReturn1 a cardano:Output"
        bytes
            `shouldSatisfy` BS8.isInfixOf "cardano:lovelace 1000000"

----------------------------------------------------------------------
-- Synthesis helpers
----------------------------------------------------------------------

baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

stubAddr :: Addr
stubAddr =
    Addr
        Testnet
        (KeyHashObj (KeyHash (fromJust (hashFromStringAsHex (replicate 56 '0'))) :: KeyHash Payment))
        StakeRefNull

emitBytes :: ConwayTx -> ByteString
emitBytes tx =
    case emit tx emptyUtxo [] of
        Right g -> serialize Turtle "total-collateral-spec" g
        Left e -> error ("TotalCollateralSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

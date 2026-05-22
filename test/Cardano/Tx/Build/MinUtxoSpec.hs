{-# LANGUAGE EmptyCase #-}

{- |
Module      : Cardano.Tx.Build.MinUtxoSpec
Description : Regression tests for issue #81 — auto-compensation of
              'payTo' / 'payTo'' outputs to the ledger min-UTxO
              threshold, plus the redeemer observation hook.
License     : Apache-2.0

Loads the committed mainnet @PParams@ snapshot
(@test/fixtures/pparams.json@) so that @getMinCoinTxOut@ produces a
realistic non-zero threshold for token-bearing outputs.
-}
module Cardano.Tx.Build.MinUtxoSpec (
    spec,
) where

import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Void (Void)
import Lens.Micro ((^.))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (
    coinTxOutL,
    getMinCoinTxOut,
    mkBasicTxOut,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (
    ConwayPlutusPurpose (..),
 )
import Cardano.Ledger.Core (witsTxL)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (Payment))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

import Cardano.Tx.Balance (
    BalanceError (InsufficientFee),
 )
import Cardano.Tx.Build (
    BuildError (BalanceFailed),
    InterpretIO (..),
    TxBuild,
    build,
    draft,
    mkPParamsBound,
    observeTxOutCoin,
    payTo,
    peek,
    spendScript,
 )

import Cardano.Tx.BuildSpec (loadPParams)

spec :: Spec
spec = describe "Cardano.Tx.Build payTo min-UTxO (issue #81)" $ do
    raisesUnderfundedTokenOutputSpec
    preservesHighLovelaceOutputSpec
    redeemerObservesCompensatedCoinSpec
    insufficientFundsFailsClosedSpec

-- ----------------------------------------------------
-- Common fixtures
-- ----------------------------------------------------

ppFixturePath :: FilePath
ppFixturePath = "test/fixtures/pparams.json"

stubAddr :: Addr
stubAddr =
    let hexStr = replicate 56 '0'
        h = fromJust (hashFromStringAsHex hexStr)
     in Addr
            Testnet
            (KeyHashObj (KeyHash h :: KeyHash Payment))
            StakeRefNull

stubTxIn :: Int -> TxIn
stubTxIn n =
    let hex =
            replicate 60 '0'
                ++ hexByte (n `div` 256)
                ++ hexByte (n `mod` 256)
        h = fromJust (hashFromStringAsHex hex)
     in TxIn (TxId (unsafeMakeSafeHash h)) (TxIx 0)
  where
    hexByte x =
        let s = "0123456789abcdef"
         in [s !! (x `div` 16), s !! (x `mod` 16)]

policyId :: PolicyID
policyId =
    let hex = replicate 56 '0'
        h = fromJust (hashFromStringAsHex hex)
     in PolicyID (ScriptHash h)

stubAsset :: AssetName
stubAsset = AssetName (SBS.toShort (BS8.pack "TKN"))

tokenValueOnly :: MaryValue
tokenValueOnly =
    MaryValue
        (Coin 0)
        ( MultiAsset
            ( Map.singleton
                policyId
                (Map.singleton stubAsset 1)
            )
        )

data NoQ a

interpretNoQ :: InterpretIO NoQ
interpretNoQ = InterpretIO $ \case {}

{- | Re-encode a 'ToData' value the same way the builder does, so
tests can compare against the redeemer 'Data' stored in the
witness set.
-}
asLedgerData :: (ToData a) => a -> Data ConwayEra
asLedgerData x =
    let BuiltinData d = toBuiltinData x in Data d

-- ----------------------------------------------------
-- Specs
-- ----------------------------------------------------

{- | A token-only @payTo@ output is automatically raised to
@getMinCoinTxOut@ when the body is assembled.
-}
raisesUnderfundedTokenOutputSpec :: Spec
raisesUnderfundedTokenOutputSpec =
    describe "raisesUnderfundedTokenOutput" $ do
        it "raises an under-min-UTxO payTo to the ledger threshold" $ do
            pp <- loadPParams ppFixturePath
            let prog :: TxBuild NoQ Void ()
                prog = do
                    _ <- payTo stubAddr tokenValueOnly
                    pure ()
                tx = draft pp prog
                outs =
                    toList (tx ^. bodyTxL . outputsTxBodyL)
            case outs of
                [out] -> do
                    let actual = out ^. coinTxOutL
                        required = getMinCoinTxOut pp out
                    actual `shouldSatisfy` (>= required)
                    actual `shouldSatisfy` (> Coin 0)
                _ ->
                    fail
                        ( "expected one output, saw "
                            <> show (length outs)
                        )

{- | Explicit high-lovelace @payTo@ outputs are kept as-is. The
threshold is below the user-supplied coin, so no compensation
should fire.
-}
preservesHighLovelaceOutputSpec :: Spec
preservesHighLovelaceOutputSpec =
    describe "preservesHighLovelaceOutput" $ do
        it "leaves an already-funded payTo output untouched" $ do
            pp <- loadPParams ppFixturePath
            let explicitCoin = Coin 25_000_000
                MaryValue _ ma = tokenValueOnly
                explicitValue = MaryValue explicitCoin ma
                prog :: TxBuild NoQ Void ()
                prog = do
                    _ <- payTo stubAddr explicitValue
                    pure ()
                tx = draft pp prog
                outs =
                    toList (tx ^. bodyTxL . outputsTxBodyL)
            case outs of
                [out] ->
                    (out ^. coinTxOutL) `shouldBe` explicitCoin
                _ ->
                    fail
                        ( "expected one output, saw "
                            <> show (length outs)
                        )

{- | A script-witnessed spend whose redeemer carries the
post-compensation lovelace observed via 'observeTxOutCoin'
converges with the body's actual output coin.

The redeemer encoding is just @Integer@ for brevity; what
matters is that the redeemer 'Data' stored in the witness set
matches the @getMinCoinTxOut@ value the body finalises on the
output.
-}
redeemerObservesCompensatedCoinSpec :: Spec
redeemerObservesCompensatedCoinSpec =
    describe "redeemerObservesCompensatedCoin" $ do
        it "carries the compensated coin in the spend redeemer" $ do
            pp <- loadPParams ppFixturePath
            let treasuryIn = stubTxIn 7
                prog :: TxBuild NoQ Void ()
                prog = do
                    ix <- payTo stubAddr tokenValueOnly
                    lov <- peek (observeTxOutCoin ix)
                    _ <- spendScript treasuryIn (toRedeemer lov)
                    pure ()
                tx = draft pp prog
                outs =
                    toList (tx ^. bodyTxL . outputsTxBodyL)
                Redeemers rdmrs =
                    tx ^. witsTxL . rdmrsTxWitsL
            beneficiaryCoin <- case outs of
                [out] -> pure (out ^. coinTxOutL)
                _ ->
                    fail
                        ( "expected one output, saw "
                            <> show (length outs)
                        )
            beneficiaryCoin `shouldSatisfy` (> Coin 0)
            case Map.toList rdmrs of
                [(ConwaySpending (AsIx 0), (datum, _))] ->
                    datum
                        `shouldBe` asLedgerData
                            (toRedeemer beneficiaryCoin)
                other ->
                    fail
                        ( "expected one spend redeemer, saw "
                            <> show (map fst other)
                        )
  where
    toRedeemer :: Coin -> Integer
    toRedeemer (Coin n) = n

{- | When the balancer cannot fund the raised min-UTxO compensation,
'build' surfaces a typed 'BalanceFailed' / 'InsufficientFee' error
rather than silently producing a sub-min-UTxO transaction.
-}
insufficientFundsFailsClosedSpec :: Spec
insufficientFundsFailsClosedSpec =
    describe "insufficientFundsFailsClosed" $ do
        it "returns BalanceFailed InsufficientFee when inputs cannot cover" $ do
            pp <- loadPParams ppFixturePath
            let prog :: TxBuild NoQ Void ()
                prog = do
                    _ <- payTo stubAddr tokenValueOnly
                    pure ()
                feeIn = stubTxIn 99
                feeUtxo =
                    mkBasicTxOut
                        stubAddr
                        (MaryValue (Coin 1) (MultiAsset mempty))
                inputs = [(feeIn, feeUtxo)]
                noEval _ = pure Map.empty
            res <-
                build
                    (mkPParamsBound pp)
                    interpretNoQ
                    noEval
                    inputs
                    []
                    stubAddr
                    prog
            case res of
                Left (BalanceFailed (InsufficientFee _ _)) ->
                    pure ()
                Left other ->
                    fail
                        ( "expected BalanceFailed InsufficientFee, saw "
                            <> show other
                        )
                Right _ ->
                    fail
                        "expected balance failure, got a transaction"

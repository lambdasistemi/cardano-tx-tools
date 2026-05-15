{- |
Module      : Cardano.Tx.Validate.LoadUtxoSpec
Description : Sanity coverage for the producer-tx CBOR UTxO loader.
License     : Apache-2.0

Loads the three 'TxIn's the issue-#8 'swap-cancel' fixture
references against the committed producer-tx CBOR files. Asserts
the loader resolves each input to a 'TxOut' with the expected
lovelace value (transcribed once from the committed @utxo.json@
documentation file at fixture-creation time).
-}
module Cardano.Tx.Validate.LoadUtxoSpec (
    spec,
) where

import Data.Maybe (fromJust)
import Lens.Micro ((^.))
import Test.Hspec (Spec, describe, it, shouldBe)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.Validate.LoadUtxo (loadUtxo)

spec :: Spec
spec = describe "Cardano.Tx.Validate.LoadUtxo.loadUtxo" $ do
    it "resolves the issue-#8 swap-cancel UTxO from producer-tx CBORs" $ do
        utxo <- loadUtxo producerTxDir issue8TxIns
        map (\(txIn, out) -> (txIn, out ^. coinTxOutL)) utxo
            `shouldBe` issue8ExpectedCoins
  where
    producerTxDir =
        "test/fixtures/mainnet-txbuild/"
            <> "swap-cancel-issue-8/producer-txs"

{- | The three 'TxIn's the issue-#8 body references (two outputs of
the @59e10ca5…@ producer, plus the reference input from the
@f5f1bdfa…@ producer).
-}
issue8TxIns :: [TxIn]
issue8TxIns =
    [ TxIn (txIdFromHex txId59e10) (TxIx 0)
    , TxIn (txIdFromHex txId59e10) (TxIx 2)
    , TxIn (txIdFromHex txIdF5f1b) (TxIx 0)
    ]

{- | Lovelace at each resolved output. Values transcribed once from
the committed @utxo.json@ at fixture-creation time so the test
catches accidental fixture drift.
-}
issue8ExpectedCoins :: [(TxIn, Coin)]
issue8ExpectedCoins =
    zip
        issue8TxIns
        [ Coin 52819860941
        , Coin 92557701
        , Coin 11667170
        ]

txId59e10 :: String
txId59e10 =
    "59e10ca5e03b8d243c699fc45e1e18a2a825e2a09c5efa6954aec820a4d64dfe"

txIdF5f1b :: String
txIdF5f1b =
    "f5f1bdfad3eb4d67d2fc36f36f47fc2938cf6f001689184ab320735a28642cf2"

{- | Decode a 32-byte hex string into a 'TxId'. The fixture hashes
are well-formed by construction (committed to the repo); a
decode failure is an author bug, surfaced via 'fromJust'.
-}
txIdFromHex :: String -> TxId
txIdFromHex hex =
    TxId
        ( unsafeMakeSafeHash
            (fromJust (hashFromStringAsHex hex))
        )

{- |
Module      : Cardano.Tx.Validate.CliSpec
Description : Coverage for tx-validate's session driver.
License     : Apache-2.0

This revision covers the foundational session driver
('mkSession') only. The parser, the validation driver, and the
verdict renderers ship with their own coverage in subsequent
slices of spec 015.
-}
module Cardano.Tx.Validate.CliSpec (
    spec,
) where

import Control.Exception (ErrorCall (..), throwIO)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Test.Hspec (Spec, describe, it, shouldBe)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet),
    SlotNo (..),
    TxIx (..),
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Provider (Provider (..))

import Cardano.Tx.BuildSpec (loadPParams)
import Cardano.Tx.Diff.Resolver (Resolver (..), resolveChain)
import Cardano.Tx.Diff.Resolver.N2C (n2cResolver)
import Cardano.Tx.Validate.Cli (
    Session (..),
    mkSession,
 )
import Cardano.Tx.Validate.LoadUtxo (loadUtxo)

spec :: Spec
spec = describe "Cardano.Tx.Validate.Cli.mkSession" $ do
    it "packages caller-supplied PParams + slot + resolvers" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        utxos <-
            loadUtxo
                "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs"
                issue8TxIns
        let provider = stubProvider utxos
            resolvers = [n2cResolver provider]
            slot = SlotNo 187382499
            session = mkSession Mainnet pp slot resolvers
        sessionNetwork session `shouldBe` Mainnet
        sessionPParams session `shouldBe` pp
        sessionSlot session `shouldBe` slot
        map resolverName (sessionUtxoResolvers session) `shouldBe` ["n2c"]
        (resolved, _) <-
            resolveChain
                (sessionUtxoResolvers session)
                (Set.fromList issue8TxIns)
        Map.keysSet resolved `shouldBe` Set.fromList issue8TxIns

issue8TxIns :: [TxIn]
issue8TxIns =
    [ TxIn (txIdFromHex txId59e10) (TxIx 0)
    , TxIn (txIdFromHex txId59e10) (TxIx 2)
    , TxIn (txIdFromHex txIdF5f1b) (TxIx 0)
    ]

txId59e10 :: String
txId59e10 =
    "59e10ca5e03b8d243c699fc45e1e18a2a825e2a09c5efa6954aec820a4d64dfe"

txIdF5f1b :: String
txIdF5f1b =
    "f5f1bdfad3eb4d67d2fc36f36f47fc2938cf6f001689184ab320735a28642cf2"

txIdFromHex :: String -> TxId
txIdFromHex hex =
    TxId (unsafeMakeSafeHash (fromJust (hashFromStringAsHex hex)))

{- | A 'Provider IO' that serves only the 'queryUTxOByTxIn'
field the 'n2cResolver' touches. Every other field panics on
call, so an accidental touch surfaces as a loud test failure
rather than a silent 'undefined'.

Mirrors the @stubProvider@ pattern from
@Cardano.Tx.Diff.ResolverSpec@; duplicated here rather than
moved to a shared helper module to keep this PR's surface
tight (the dedup is a follow-up if a second consumer
materialises).
-}
stubProvider ::
    [(TxIn, TxOut ConwayEra)] ->
    Provider IO
stubProvider utxos =
    Provider
        { withAcquired = \_ -> panicIO "withAcquired"
        , queryUTxOs = \_ -> panicIO "queryUTxOs"
        , queryUTxOByTxIn = \needed ->
            pure
                ( Map.fromList
                    [ entry
                    | entry@(txIn, _) <- utxos
                    , Set.member txIn needed
                    ]
                )
        , queryProtocolParams = panicIO "queryProtocolParams"
        , queryLedgerSnapshot = panicIO "queryLedgerSnapshot"
        , queryStakeRewards = \_ -> panicIO "queryStakeRewards"
        , queryRewardAccounts = \_ -> panicIO "queryRewardAccounts"
        , queryVoteDelegatees = \_ -> panicIO "queryVoteDelegatees"
        , queryTreasury = panicIO "queryTreasury"
        , queryGovernanceState = panicIO "queryGovernanceState"
        , evaluateTx = \_ -> panicIO "evaluateTx"
        , posixMsToSlot = \_ -> panicIO "posixMsToSlot"
        , posixMsCeilSlot = \_ -> panicIO "posixMsCeilSlot"
        , queryUpperBoundSlot = \_ -> panicIO "queryUpperBoundSlot"
        }
  where
    panicIO :: String -> IO a
    panicIO field =
        throwIO
            ( ErrorCall
                ("stubProvider." <> field <> " called by an unprepared test")
            )

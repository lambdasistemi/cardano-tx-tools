module Main (main) where

import Control.Concurrent (rtsSupportsBoundThreads)
import Control.Monad (unless)
import Test.Hspec (hspec)

import Cardano.Node.Client.E2E.BalanceSpec qualified as BalanceSpec
import Cardano.Node.Client.E2E.ChainPopulatorSpec qualified as ChainPopulatorSpec
import Cardano.Node.Client.E2E.GovernanceSmokeSpec qualified as GovernanceSmokeSpec
import Cardano.Node.Client.E2E.GraphStateSpec qualified as GraphStateSpec
import Cardano.Node.Client.E2E.MultiAssetChangeSpec qualified as MultiAssetChangeSpec
import Cardano.Node.Client.E2E.TxBuildSpec qualified as TxBuildSpec
import Cardano.Node.Client.E2E.UTxOIndexerSpec qualified as UTxOIndexerSpec

main :: IO ()
main = do
    unless rtsSupportsBoundThreads $
        fail "N2C timers require the e2e-tests executable to be linked with -threaded"
    hspec $ do
        BalanceSpec.spec
        ChainPopulatorSpec.spec
        GraphStateSpec.spec
        GovernanceSmokeSpec.spec
        MultiAssetChangeSpec.spec
        TxBuildSpec.spec
        UTxOIndexerSpec.spec

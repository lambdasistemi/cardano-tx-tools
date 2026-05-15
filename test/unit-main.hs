module Main (main) where

import Test.Hspec (hspec)

import Cardano.Tx.BuildSpec qualified as BuildSpec
import Cardano.Tx.DiffSpec qualified as DiffSpec

main :: IO ()
main = hspec $ do
    DiffSpec.spec
    BuildSpec.spec

module Main (main) where

import Test.Hspec (hspec)

import Cardano.Tx.BuildSpec qualified as BuildSpec
import Cardano.Tx.DiffSpec qualified as DiffSpec
import Cardano.Tx.Validate.LoadUtxoSpec qualified as LoadUtxoSpec
import Cardano.Tx.ValidateSpec qualified as ValidateSpec

main :: IO ()
main = hspec $ do
    DiffSpec.spec
    BuildSpec.spec
    LoadUtxoSpec.spec
    ValidateSpec.spec

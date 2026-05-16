module Main (main) where

import Test.Hspec (hspec)

import Cardano.Tx.Validate.CliSpec qualified as CliSpec

main :: IO ()
main = hspec $ do
    CliSpec.spec

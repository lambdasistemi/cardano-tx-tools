module Main (main) where

import Cardano.Tx.Sign.CoreSpec qualified as CoreSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec CoreSpec.spec

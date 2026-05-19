{- |
Module      : Cardano.Tx.Graph.Rules.LoadSmokeSpec
Description : T001 scaffold smoke spec for the rules loader.
License     : Apache-2.0

Confirms the loader's public surface exists and the unknown-extension
branch returns 'UnsupportedExtension'. Subsequent slices (T002+) replace
the @NotImplemented@ sentinels for @.ttl@ / @.yaml@ / @.yml@ with the
real parsers and add their own specs.
-}
module Cardano.Tx.Graph.Rules.LoadSmokeSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    RulesLoadError (..),
    loadRulesFile,
 )
import System.IO.Temp (withSystemTempFile)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Cardano.Tx.Graph.Rules.Load (T001 scaffold)" $
    it "rejects a .foo extension with UnsupportedExtension" $
        withSystemTempFile "rules.foo" $ \path _ -> do
            result <- loadRulesFile path
            result `shouldBe` Left (UnsupportedExtension path)

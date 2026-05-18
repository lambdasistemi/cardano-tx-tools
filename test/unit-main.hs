module Main (main) where

import Test.Hspec (hspec)

import Cardano.Tx.BuildSpec qualified as BuildSpec
import Cardano.Tx.DiffSpec qualified as DiffSpec
import Cardano.Tx.InspectSpec qualified as InspectSpec
import Cardano.Tx.Rewrite.ApplySpec qualified as RewriteApplySpec
import Cardano.Tx.Rewrite.LoadSpec qualified as RewriteLoadSpec
import Cardano.Tx.Validate.LoadUtxoSpec qualified as LoadUtxoSpec
import Cardano.Tx.ValidateSpec qualified as ValidateSpec

main :: IO ()
main = hspec $ do
    DiffSpec.spec
    BuildSpec.spec
    InspectSpec.spec
    LoadUtxoSpec.spec
    RewriteApplySpec.spec
    RewriteLoadSpec.spec
    ValidateSpec.spec

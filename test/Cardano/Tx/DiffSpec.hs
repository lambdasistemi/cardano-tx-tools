module Cardano.Tx.DiffSpec (spec) where

import Test.Hspec

import Cardano.Tx.BlueprintSpec qualified as BlueprintSpec
import Cardano.Tx.Diff.CliSpec qualified as CliSpec
import Cardano.Tx.Diff.ConwaySpec qualified as ConwaySpec
import Cardano.Tx.Diff.CoreSpec qualified as CoreSpec
import Cardano.Tx.Diff.ResolverSpec qualified as ResolverSpec
import Cardano.Tx.Diff.Web2Spec qualified as Web2Spec

spec :: Spec
spec =
    describe "TxDiff structural traversal" $ do
        BlueprintSpec.spec
        CliSpec.spec
        CoreSpec.spec
        ConwaySpec.spec
        ResolverSpec.spec
        Web2Spec.spec

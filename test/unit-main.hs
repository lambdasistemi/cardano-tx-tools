module Main (main) where

import Test.Hspec (hspec)

import Cardano.Tx.BuildSpec qualified as BuildSpec
import Cardano.Tx.DiffSpec qualified as DiffSpec
import Cardano.Tx.Graph.EmitSmokeSpec qualified as GraphEmitSmokeSpec
import Cardano.Tx.Graph.Rules.LoadEntitiesSpec qualified as GraphRulesLoadEntitiesSpec
import Cardano.Tx.Graph.Rules.LoadExeSpec qualified as GraphRulesLoadExeSpec
import Cardano.Tx.Graph.Rules.LoadGoldenSpec qualified as GraphRulesLoadGoldenSpec
import Cardano.Tx.Graph.Rules.LoadImportsSpec qualified as GraphRulesLoadImportsSpec
import Cardano.Tx.Graph.Rules.LoadSmokeSpec qualified as GraphRulesLoadSmokeSpec
import Cardano.Tx.Graph.Rules.LoadTurtleSpec qualified as GraphRulesLoadTurtleSpec
import Cardano.Tx.Graph.Rules.LoadValidationSpec qualified as GraphRulesLoadValidationSpec
import Cardano.Tx.Graph.Rules.LoadYamlSpec qualified as GraphRulesLoadYamlSpec
import Cardano.Tx.InspectSpec qualified as InspectSpec
import Cardano.Tx.Rewrite.ApplySpec qualified as RewriteApplySpec
import Cardano.Tx.Rewrite.LoadSpec qualified as RewriteLoadSpec
import Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec qualified as RewriteRedesignGoldenSpec
import Cardano.Tx.Validate.LoadUtxoSpec qualified as LoadUtxoSpec
import Cardano.Tx.ValidateSpec qualified as ValidateSpec

main :: IO ()
main = hspec $ do
    DiffSpec.spec
    BuildSpec.spec
    GraphEmitSmokeSpec.spec
    GraphRulesLoadEntitiesSpec.spec
    GraphRulesLoadExeSpec.spec
    GraphRulesLoadGoldenSpec.spec
    GraphRulesLoadImportsSpec.spec
    GraphRulesLoadSmokeSpec.spec
    GraphRulesLoadTurtleSpec.spec
    GraphRulesLoadValidationSpec.spec
    GraphRulesLoadYamlSpec.spec
    InspectSpec.spec
    LoadUtxoSpec.spec
    RewriteApplySpec.spec
    RewriteLoadSpec.spec
    RewriteRedesignGoldenSpec.spec
    ValidateSpec.spec

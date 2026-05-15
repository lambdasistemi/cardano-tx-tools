module Main (main) where

import Test.Hspec (hspec)

import Cardano.Tx.Generator.FanoutSpec qualified as FanoutSpec
import Cardano.Tx.Generator.PersistSpec qualified as PersistSpec
import Cardano.Tx.Generator.PopulationSpec qualified as PopulationSpec
import Cardano.Tx.Generator.SelectionSpec qualified as SelectionSpec
import Cardano.Tx.Generator.ServerSpec qualified as ServerSpec
import Cardano.Tx.Generator.SnapshotSpec qualified as SnapshotSpec

main :: IO ()
main = hspec $ do
    FanoutSpec.spec
    PersistSpec.spec
    PopulationSpec.spec
    SelectionSpec.spec
    ServerSpec.spec
    SnapshotSpec.spec

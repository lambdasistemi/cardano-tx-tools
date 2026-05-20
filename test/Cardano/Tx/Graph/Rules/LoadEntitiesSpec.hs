{- |
Module      : Cardano.Tx.Graph.Rules.LoadEntitiesSpec
Description : Surfaces the in-memory entity list on 'RulesLoadResult' (T001).
License     : Apache-2.0

Asserts that after loading a fixture's @rules.yaml@, the new
'Cardano.Tx.Graph.Rules.Load.rulesEntities' field on
'Cardano.Tx.Graph.Rules.Load.RulesLoadResult' carries the same
deduped @['EntityDecl']@ that the loader serialises into
@rulesOverlayTurtle@. This is the public-API surface the body
emitter (#58) builds its credential lookup table from without
re-parsing the overlay Turtle.

The fixture under exercise is
@test/fixtures/rewrite-redesign/02-alice-bob-ada@: two
@from-address:@ entities (@alice@, @bob@) in source order, each
yielding one 'EntityIdentifier'.
-}
module Cardano.Tx.Graph.Rules.LoadEntitiesSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    EntityDecl (..),
    RulesLoadResult (..),
    loadRulesFile,
 )

import System.FilePath ((</>))
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

fixturesRoot :: FilePath
fixturesRoot = "test/fixtures/rewrite-redesign"

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Rules.Load.rulesEntities (T001)" $
        it "surfaces alice + bob in source order with ≥1 identifier each" $ do
            let rulesPath =
                    fixturesRoot </> "02-alice-bob-ada" </> "rules.yaml"
            loadResult <- loadRulesFile rulesPath
            case loadResult of
                Left err ->
                    expectationFailure $
                        "loadRulesFile " <> rulesPath <> " failed: " <> show err
                Right result -> do
                    let entities = rulesEntities result
                    map entitySlug entities `shouldBe` ["alice", "bob"]
                    let identCounts =
                            [ (entitySlug e, length (entityIdentifiers e))
                            | e <- entities
                            ]
                    identCounts `shouldSatisfy` all ((>= 1) . snd)

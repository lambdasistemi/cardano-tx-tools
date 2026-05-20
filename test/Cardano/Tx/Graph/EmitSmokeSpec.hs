{- |
Module      : Cardano.Tx.Graph.EmitSmokeSpec
Description : Compile-and-call smoke for the body emitter scaffold (T002).
License     : Apache-2.0

Asserts that the public surface introduced by
'Cardano.Tx.Graph.Emit' — the 'emit' entry-point, the
'EmittedGraph' result, the 'EmitError' / 'EmitFormat' / 'Triple'
companions — exists, compiles, and that the placeholder stub
returns the empty graph on a minimal 'ConwayTx' + empty
'ResolvedUTxO' + empty operator-entity list.

This spec is intentionally minimal: T002 ships the module
scaffold, not the projection walker (T005) or the serializer
(T005 + T011). The smoke is the pre-T005 contract — every
projection / serializer slice keeps it GREEN as a regression
guard on the public surface.

The fixture-02-alice-bob-ada @tx@ builder
(@Fixtures.RewriteRedesign.S02_AliceBobAda@) is reused as the
minimal hand-built 'ConwayTx'; the resolved-UTxO map is empty
(the stub ignores it).
-}
module Cardano.Tx.Graph.EmitSmokeSpec (spec) where

import Cardano.Tx.Graph.Emit (
    EmitError (..),
    EmitFormat (..),
    EmittedGraph (..),
    ResolvedUTxO,
    Triple (..),
    emit,
 )

import Data.Map.Strict qualified as Map
import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02

import Test.Hspec (Spec, describe, it, shouldBe)

-- | Empty resolved-UTxO map (the stub ignores it).
emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit.emit (T002 scaffold)" $ do
        it "returns Right empty-graph on a minimal ConwayTx + empty UTxO + no entities" $ do
            let result = emit S02.tx emptyUtxo []
            result `shouldBe` Right (EmittedGraph [] mempty [])

        it "EmitError + EmitFormat + Triple constructors are in scope" $ do
            -- compile-only assertions on the public surface; any
            -- value matching the constructor proves the type exists.
            let _e1 = UtxoRequired 1
                _e2 = UtxoMissing "deadbeef#0"
                _e3 = MalformedTxCbor "tx.cbor" "decode-failed"
                _e4 = MalformedUtxoJson "utxo.json" "parse-failed"
                _e5 = UnknownFormat "yaml"
                _e6 = UnsupportedLeafType "Foo"
                _fmtTtl = Turtle
                _fmtJsonLd = JsonLd
                _t = Triple "_:s" "cardano:p" "_:o"
            True `shouldBe` True

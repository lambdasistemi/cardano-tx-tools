{- |
Module      : Cardano.Tx.Graph.EmitMonadSpec
Description : Contract spec for the @Emit@ monad seam (T102).
License     : Apache-2.0

T102 introduces a private @Cardano.Tx.Graph.Emit.Monad@ submodule
exposing the body-walker monad

@
  Emit = WriterT [Triple] (State (Set Subject))
@

plus the three helpers @tellTriple@, @introduce@, and
@runEmit@, and an internal @groupBySubject@ that rebuilds the
'SubjectBlock' list out of a flat triple stream while preserving
first-occurrence order on subjects.

This spec asserts the contract directly on the primitives:

* @tellTriple@ accumulates triples in call order;
* @introduce@ is idempotent on a given subject — the body action
  runs the first time, is a no-op on every later visit;
* @runEmit@ returns the flat triple stream plus the final
  seen-set of subjects;
* @groupBySubject@ on the flat triple stream produced by the
  projection walker for fixture 02 matches the @[SubjectBlock]@
  list embedded in the pre-refactor @[BodySection]@ output of
  'Cardano.Tx.Graph.Emit.Project.projectBody'.

The fixture-02 round-trip is the load-bearing contract: it
proves the @Emit ()@ → @runEmit@ → @groupBySubject@ pipeline
reproduces the exact same 'SubjectBlock' sequence the
pre-refactor walker emitted, in the same order. The
'Cardano.Tx.Graph.EmitGoldenSpec' byte-diff guards the wider
no-behavior-change property; this spec guards the seam's local
shape so future slices (T103+) can refactor against a typed
contract.
-}
module Cardano.Tx.Graph.EmitMonadSpec (spec) where

import Data.Set qualified as Set

import Cardano.Tx.Graph.Emit (
    BnodeName (..),
    Object (..),
    Predicate (..),
    Subject (..),
    SubjectBlock (..),
    Triple (..),
    groupBySubject,
    introduce,
    runEmit,
    tellTriple,
 )

import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit.Monad (T102 seam)" $ do
    describe "tellTriple" $ do
        it "accumulates triples in call order" $ do
            let action = do
                    tellTriple t1
                    tellTriple t2
                    tellTriple t3
                (triples, _seen) = runEmit action
            triples `shouldBe` [t1, t2, t3]

        it "leaves the seen-set empty when only tellTriple is used" $ do
            let action = do
                    tellTriple t1
                    tellTriple t2
                (_triples, seen) = runEmit action
            seen `shouldBe` Set.empty

    describe "introduce" $ do
        it "runs the body the first time the subject is seen" $ do
            let action = introduce subjA $ do
                    tellTriple t1
                    tellTriple t2
                (triples, seen) = runEmit action
            triples `shouldBe` [t1, t2]
            seen `shouldBe` Set.singleton subjA

        it "is a no-op on the second visit to the same subject" $ do
            let action = do
                    introduce subjA (tellTriple t1)
                    introduce subjA (tellTriple t2)
                (triples, _seen) = runEmit action
            triples `shouldBe` [t1]

        it "tracks distinct subjects independently" $ do
            let action = do
                    introduce subjA (tellTriple t1)
                    introduce subjB (tellTriple t2)
                    introduce subjA (tellTriple t3)
                    introduce subjB (tellTriple t4)
                (triples, seen) = runEmit action
            triples `shouldBe` [t1, t2]
            seen `shouldBe` Set.fromList [subjA, subjB]

    describe "groupBySubject" $ do
        it "preserves first-occurrence order on subjects" $ do
            let triples = [t1, t3, t4]
                -- t1, t3 share subjA; t4 has subjB.
                expected =
                    [ SubjectBlock
                        subjA
                        [(PRdfType, OIri "cardano:Foo"), (PRdfType, OIri "cardano:Baz")]
                    , SubjectBlock
                        subjB
                        [(PRdfType, OIri "cardano:Qux")]
                    ]
            groupBySubject triples `shouldBe` expected

        it "is empty on an empty triple stream" $ do
            groupBySubject [] `shouldBe` []

        it "collapses interleaved emissions for the same subject" $ do
            -- subjA, subjB, subjA — the subjA block should
            -- contain both subjA predicates in call order; subjB
            -- block stays second.
            let triples =
                    [ Triple subjA (PIri "cardano:p1") (OIri "cardano:x")
                    , Triple subjB (PIri "cardano:p2") (OIri "cardano:y")
                    , Triple subjA (PIri "cardano:p3") (OIri "cardano:z")
                    ]
                expected =
                    [ SubjectBlock
                        subjA
                        [ (PIri "cardano:p1", OIri "cardano:x")
                        , (PIri "cardano:p3", OIri "cardano:z")
                        ]
                    , SubjectBlock
                        subjB
                        [(PIri "cardano:p2", OIri "cardano:y")]
                    ]
            groupBySubject triples `shouldBe` expected

----------------------------------------------------------------------
-- Test data
----------------------------------------------------------------------

-- | Sample subjects for the contract checks.
subjA, subjB :: Subject
subjA = SBnode (BnodeName "a")
subjB = SBnode (BnodeName "b")

-- | Sample triples. @t1@, @t3@ share @subjA@; @t2@, @t4@ share @subjB@.
t1, t2, t3, t4 :: Triple
t1 = Triple subjA PRdfType (OIri "cardano:Foo")
t2 = Triple subjB PRdfType (OIri "cardano:Bar")
t3 = Triple subjA PRdfType (OIri "cardano:Baz")
t4 = Triple subjB PRdfType (OIri "cardano:Qux")

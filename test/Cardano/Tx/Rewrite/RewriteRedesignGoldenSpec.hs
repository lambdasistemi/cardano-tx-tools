{- |
Module      : Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec
Description : Goldens suite scaffolding for harness #45 / specs/033-rewrite-redesign-harness.
License     : Apache-2.0

Empty fixture registry in this slice. Subsequent slices (S3 blueprints,
S5..S14 per-fixture) populate the suite. The B-side @expected.ttl@ files
(S15..S24) land post-kmaps#53 Phase A signal.

See @specs/033-rewrite-redesign-harness/contracts/goldens-suite.md@ for the
behavioural contract.

The inner @helpers@ block carries one structural Hspec item exercising
'mkTx', 'defTxBuilder', 'baseShape', and 'assertShape' end-to-end against
a synthetic 'StoryId' @"smoke"@ 'FixturePaths'. The per-fixture iteration
block lands later, populated from a @fixtureRegistry@ list that this slice
intentionally leaves empty.
-}
module Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec (spec) where

import Test.Hspec (Spec, describe, it)

import Fixtures.RewriteRedesign.Helpers (
    StoryId (..),
    assertShape,
    baseShape,
    defTxBuilder,
    mkFixturePaths,
    mkTx,
 )

spec :: Spec
spec = describe "RewriteRedesignGoldens" $ do
    describe "helpers" $ do
        it "mkTx defTxBuilder satisfies baseShape" $
            assertShape
                (mkTx defTxBuilder)
                baseShape
                (mkFixturePaths (StoryId "smoke"))

{- |
Module      : Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec
Description : Goldens suite scaffolding for harness #45 / specs/033-rewrite-redesign-harness.
License     : Apache-2.0

Empty fixture registry in this slice (S1). Subsequent slices (S2 helpers,
S3 blueprints, S5..S14 per-fixture) populate the suite. The B-side
expected.ttl files (S15..S24) land post-kmaps#53 Phase A signal.

See @specs/033-rewrite-redesign-harness/contracts/goldens-suite.md@ for the
behavioural contract.
-}
module Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec (spec) where

import Test.Hspec (Spec, describe)

spec :: Spec
spec = describe "RewriteRedesignGoldens" $ pure ()

{- |
Module      : Cardano.Tx.Rewrite.ApplySpec
Description : Pure-function tests for the rewriting-rules application
              layer (slice S2 — collapse-only).
License     : Apache-2.0

Drives 'Cardano.Tx.Rewrite.applyCollapseFromRewriteRules' through the
load-bearing pure-function shape required by slice S2 of
@specs\/032-tx-inspect@:

* a hand-crafted 'RewriteRules' with a non-empty 'CollapseRules' value
  sets 'humanCollapseRules' to @Just (rewriteCollapse rr)@ verbatim,
* 'defaultRewriteRules' (empty collapse list) still produces a non-Nothing
  'humanCollapseRules' carrying the empty rule list — the renderer
  treats this the same as 'Nothing' but the helper's job is to be
  faithful to the rewriting-rules value,
* the operation is idempotent: applying twice equals applying once.

Render-level effects (the actual collapse application inside
'Cardano.Tx.Diff.renderConwayTxHuman') are covered by the golden tests
in 'Cardano.Tx.InspectSpec' and by the @gate.sh@ smoke; this spec
covers only the plumbing.
-}
module Cardano.Tx.Rewrite.ApplySpec (spec) where

import Test.Hspec

import Cardano.Tx.Diff (
    CollapseRawView (..),
    CollapseRule (..),
    CollapseRules (..),
    DiffPath (..),
    HumanRenderOptions (..),
    RewriteRules (..),
    defaultHumanRenderOptions,
    defaultRewriteRules,
 )
import Cardano.Tx.Rewrite (applyCollapseFromRewriteRules)

spec :: Spec
spec =
    describe "Cardano.Tx.Rewrite.applyCollapseFromRewriteRules" $ do
        it "sets humanCollapseRules to Just (rewriteCollapse rr) for a non-empty rule list" $ do
            let rules = sampleRewriteRules
                opts =
                    applyCollapseFromRewriteRules
                        rules
                        defaultHumanRenderOptions
            humanCollapseRules opts `shouldBe` Just (rewriteCollapse rules)

        it
            "fills humanCollapseRules with the rewrite's collapse value\
            \ even when the rule list is empty"
            $ do
                let opts =
                        applyCollapseFromRewriteRules
                            defaultRewriteRules
                            defaultHumanRenderOptions
                humanCollapseRules opts
                    `shouldBe` Just (rewriteCollapse defaultRewriteRules)

        it "leaves every other field of HumanRenderOptions unchanged" $ do
            let opts =
                    applyCollapseFromRewriteRules
                        sampleRewriteRules
                        defaultHumanRenderOptions
            humanRenderShape opts
                `shouldBe` humanRenderShape defaultHumanRenderOptions
            humanTreeArt opts
                `shouldBe` humanTreeArt defaultHumanRenderOptions
            humanRenameRules opts
                `shouldBe` humanRenameRules defaultHumanRenderOptions

        it "is idempotent — applying twice equals applying once" $ do
            let once =
                    applyCollapseFromRewriteRules
                        sampleRewriteRules
                        defaultHumanRenderOptions
                twice =
                    applyCollapseFromRewriteRules
                        sampleRewriteRules
                        once
            twice `shouldBe` once

sampleRewriteRules :: RewriteRules
sampleRewriteRules =
    defaultRewriteRules
        { rewriteCollapse =
            CollapseRules
                { collapseRawView = CollapseRawHide
                , collapseRules =
                    [ CollapseRule
                        { collapseRuleName = "Output"
                        , collapseRuleAt =
                            DiffPath ["body", "outputs"]
                        , collapseRuleRequired =
                            [ DiffPath ["address"]
                            , DiffPath ["coin"]
                            ]
                        }
                    ]
                }
        }

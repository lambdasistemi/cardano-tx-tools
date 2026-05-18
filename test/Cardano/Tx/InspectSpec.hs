{- |
Module      : Cardano.Tx.InspectSpec
Description : Golden tests for the @tx-inspect@ render path.
License     : Apache-2.0

Drives 'Cardano.Tx.Diff.renderConwayTxHuman' against the existing
@swap-cancel-issue-8@ body fixture, with inputs resolved by the
test-only 'StaticResolver.staticResolver' over the same producer-tx
CBORs the Phase-1 validate suite already uses. The captured output is
checked against
@test\/fixtures\/mainnet-txbuild\/swap-cancel-issue-8\/inspect.verbatim.txt@.

Slice S1 of @specs\/032-tx-inspect@ shipped the baseline (empty rules
→ verbatim render). Slice S2 of @specs\/032-tx-inspect@ adds the
collapse-only golden: rendering the same fixture under a checked-in
@collapse-only.yaml@ produces a stable structural view with the
named @Output@ shape exposing the per-output address + coin slots.
Slice S3 of @specs\/032-tx-inspect@ adds the rename-only golden:
rendering the same fixture under a checked-in @rename-only.yaml@
substitutes the known payment-address and script-hash leaves with
their address-book names; unknown identifiers render verbatim.

Slice S2 also documents the
@specs\/032-tx-inspect@ US2 Acceptance #2 shared-substrate property:
@tx-diff body body@ produces only @= \<root\>@ (the
'Cardano.Tx.Diff.DiffSame' summary line), with no per-side render to
slice. The corresponding @it@ block below is a positive guard against
that output format changing under us; T033 (Amaru cross-check, slice
S4) carries the load-bearing shared-substrate evidence via the
diverging-tx path that does emit per-side renders.

The smoke at @scripts\/smoke\/tx-inspect@ exercises the unresolved
render path (no producer-tx fixtures) and the collapse-only render
against the same fixture; the goldens together cover both
with-resolution and without-resolution shapes.
-}
module Cardano.Tx.InspectSpec (spec) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.IO qualified as TextIO
import Lens.Micro ((^.))
import System.Directory (doesFileExist)
import Test.Hspec

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    referenceInputsTxBodyL,
 )

import Cardano.Tx.BuildSpec (loadBody)
import Cardano.Tx.Diff (
    TxDiffOptions (..),
    decodeConwayTxInput,
    defaultHumanRenderOptions,
    defaultRewriteRules,
    defaultTxDiffOptions,
    diffConwayTx,
    parseRewriteRulesYaml,
    renderConwayTxHuman,
    renderDiffNodeHuman,
 )
import Cardano.Tx.Diff.Resolver (Resolver (..))
import Cardano.Tx.Rewrite (applyCollapseFromRewriteRules, applyRewriteRules)

import StaticResolver (staticResolver)

spec :: Spec
spec = do
    baselineSpec
    collapseOnlySpec
    renameOnlySpec
    selfDiffSharedSubstrateSpec

baselineSpec :: Spec
baselineSpec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman (slice S1 baseline)" $ do
        it
            "renders the swap-cancel-issue-8 body with resolved inputs to the\
            \ checked-in golden"
            $ do
                tx <- loadBody (fixtureDir <> "/body.cbor.hex")
                let body = tx ^. bodyTxL
                    inputs =
                        (body ^. inputsTxBodyL)
                            <> (body ^. referenceInputsTxBodyL)
                            <> (body ^. collateralInputsTxBodyL)
                let resolver = staticResolver producerDir
                resolved <- resolveInputs resolver inputs
                let diffOptions =
                        defaultTxDiffOptions
                            { txDiffResolvedInputs = Just resolved
                            }
                    actual =
                        renderConwayTxHuman
                            defaultHumanRenderOptions
                            diffOptions
                            tx
                expected <- TextIO.readFile (fixtureDir <> "/inspect.verbatim.txt")
                actual `shouldBe` expected

collapseOnlySpec :: Spec
collapseOnlySpec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman (slice S2 collapse-only)" $ do
        it
            "applies collapse rules loaded from collapse-only.yaml to the\
            \ swap-cancel-issue-8 body and matches the checked-in golden"
            $ do
                tx <- loadBody (fixtureDir <> "/body.cbor.hex")
                rulesBytes <- BS.readFile (fixtureDir <> "/collapse-only.yaml")
                rules <- case parseRewriteRulesYaml rulesBytes of
                    Right r -> pure r
                    Left err -> expectationFailure' err
                let humanOptions =
                        applyCollapseFromRewriteRules
                            rules
                            defaultHumanRenderOptions
                    actual =
                        renderConwayTxHuman
                            humanOptions
                            defaultTxDiffOptions
                            tx
                expected <-
                    TextIO.readFile (fixtureDir <> "/inspect.collapse-only.txt")
                actual `shouldBe` expected

        it
            "leaves the render unchanged when applyCollapseFromRewriteRules\
            \ is fed defaultRewriteRules (collapse list empty)"
            $ do
                tx <- loadBody (fixtureDir <> "/body.cbor.hex")
                let humanOptions =
                        applyCollapseFromRewriteRules
                            defaultRewriteRules
                            defaultHumanRenderOptions
                    actualWithRules =
                        renderConwayTxHuman
                            humanOptions
                            defaultTxDiffOptions
                            tx
                    actualBaseline =
                        renderConwayTxHuman
                            defaultHumanRenderOptions
                            defaultTxDiffOptions
                            tx
                actualWithRules `shouldBe` actualBaseline

renameOnlySpec :: Spec
renameOnlySpec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman (slice S3 rename-only)" $ do
        it
            "applies rename rules loaded from rename-only.yaml to the\
            \ swap-cancel-issue-8 body and matches the checked-in golden"
            $ do
                tx <- loadBody (fixtureDir <> "/body.cbor.hex")
                let body = tx ^. bodyTxL
                    inputs =
                        (body ^. inputsTxBodyL)
                            <> (body ^. referenceInputsTxBodyL)
                            <> (body ^. collateralInputsTxBodyL)
                let resolver = staticResolver producerDir
                resolved <- resolveInputs resolver inputs
                rulesBytes <- BS.readFile (fixtureDir <> "/rename-only.yaml")
                rules <- case parseRewriteRulesYaml rulesBytes of
                    Right r -> pure r
                    Left err -> expectationFailure' err
                let humanOptions =
                        applyRewriteRules rules defaultHumanRenderOptions
                    diffOptions =
                        defaultTxDiffOptions
                            { txDiffResolvedInputs = Just resolved
                            }
                    actual =
                        renderConwayTxHuman
                            humanOptions
                            diffOptions
                            tx
                    goldenPath = fixtureDir <> "/inspect.rename-only.txt"
                expected <- readOrCaptureGolden goldenPath actual
                actual `shouldBe` expected

selfDiffSharedSubstrateSpec :: Spec
selfDiffSharedSubstrateSpec =
    describe
        "Cardano.Tx.Diff.renderDiffNodeHuman self-diff (US2 Acceptance #2 guard)"
        $ do
            it
                "self-diff of the swap-cancel-issue-8 body produces a single\
                \ '= <root>' line; there is no per-side render to cross-check\
                \ at the collapse-only level (T015a is therefore a format\
                \ guard — load-bearing shared-substrate evidence lives in T033)"
                $ do
                    bytes <-
                        BS.readFile (fixtureDir <> "/body.cbor.hex")
                    tx <- case decodeConwayTxInput bytes of
                        Right t -> pure t
                        Left err -> expectationFailure' (show err)
                    let diffNode = diffConwayTx tx tx
                    renderDiffNodeHuman diffNode
                        `shouldBe` "= <root>\n"

fixtureDir :: FilePath
fixtureDir = "test/fixtures/mainnet-txbuild/swap-cancel-issue-8"

producerDir :: FilePath
producerDir = fixtureDir <> "/producer-txs"

{- | 'expectationFailure' with the return type adapted to any monadic
continuation. Keeps each @it@ block straight-line.
-}
expectationFailure' :: String -> IO a
expectationFailure' msg = do
    expectationFailure msg
    error "unreachable: expectationFailure threw"

{- | First-run capture pattern for golden files: when the golden does
not yet exist on disk write @actual@ to it (so the next run asserts
match) and return @actual@ as the \"expected\" value so the first run
also passes. Used by the per-slice golden tests that ship a captured
golden — the brief explicitly authorises this pattern.
-}
readOrCaptureGolden :: FilePath -> Text -> IO Text
readOrCaptureGolden path actual = do
    exists <- doesFileExist path
    if exists
        then TextIO.readFile path
        else do
            TextIO.writeFile path actual
            pure actual

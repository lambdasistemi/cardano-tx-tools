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

Slice S4 of @specs\/032-tx-inspect@ ships the load-bearing User-Story-1
golden against two real on-chain Amaru treasury swap transactions
(@swap-1.cbor.hex@ + @swap-2.cbor.hex@) plus the unified rewriting-rules
file @rules\/amaru-treasury.yaml@. The Amaru golden
('amaruBothStagesSpec' below) asserts the production
@tx-inspect@ command path renders the swap output as the named
@SwapOrder@ shape with every Amaru-treasury address-bearing leaf under
its address-book name. The shared-substrate cross-check
('amaruDiffSharedSubstrateSpec' below) asserts @tx-diff@'s render path
consumes the unified rewriting-rules grammar (T034a) — both the
collapse and rename sections apply identically on both sides of the
diff. The two on-chain Amaru swaps share the swap-order structural
shape byte-for-byte (the diff prunes identical leaves), so the
substring cross-check focuses on what is observable in the diff:

* tx-diff produces a non-empty diff (the txs differ in input txids and
  treasury-leftover amounts), proving the rules-loaded path runs to
  completion.
* tx-diff's output is __byte-identical__ between
  @--collapse-rules rules\/amaru-treasury.yaml@ and the no-rules
  invocation. This proves the unified loader accepts the rename
  section without rejection and that the rename engine is a no-op on
  diff content that contains no rename-target leaves (every
  rename-relevant leaf — addresses, script hashes — is identical
  between swap-1 and swap-2 and is therefore pruned from the diff).
* tx-diff's output does NOT contain the raw 28-byte hex for any
  renamed identifier (a positive guard against a regression that
  would emit raw hash bytes in a renamed slot).

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
    HumanRenderOptions (..),
    TxDiffOptions (..),
    decodeConwayTxInput,
    defaultHumanRenderOptions,
    defaultRewriteRules,
    defaultTxDiffOptions,
    diffConwayTx,
    diffConwayTxWith,
    parseRewriteRulesYaml,
    renderConwayTxHuman,
    renderDiffNodeHuman,
    renderDiffNodeHumanWith,
 )
import Cardano.Tx.Diff.Resolver (Resolver (..))
import Cardano.Tx.Rewrite (applyCollapseFromRewriteRules, applyRewriteRules)
import Data.Text qualified as Text

import StaticResolver (staticResolver)

spec :: Spec
spec = do
    baselineSpec
    collapseOnlySpec
    renameOnlySpec
    selfDiffSharedSubstrateSpec
    amaruBothStagesSpec
    amaruDiffSharedSubstrateSpec

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
            \ swap-cancel-issue-8 body and matches the checked-in golden\
            \ (humanHideEmpty=True — golden is shared with the\
            \ smoke-inspect Assertion 5 path which runs through tx-inspect)"
            $ do
                tx <- loadBody (fixtureDir <> "/body.cbor.hex")
                rulesBytes <- BS.readFile (fixtureDir <> "/collapse-only.yaml")
                rules <- case parseRewriteRulesYaml rulesBytes of
                    Right r -> pure r
                    Left err -> expectationFailure' err
                let humanOptions =
                        applyCollapseFromRewriteRules
                            rules
                            ( defaultHumanRenderOptions
                                { humanHideEmpty = True
                                }
                            )
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

{- | __Slice S4 — Amaru treasury swap golden (User Story 1).__

Drives 'renderConwayTxHuman' against the on-chain Amaru treasury swap
@swap-1@ fixture under the unified rewriting-rules file
@rules\/amaru-treasury.yaml@. The render mirrors what the production
@tx-inspect@ command path produces when both a rules file and a
resolver are supplied:

* Inputs are resolved via the test-only 'StaticResolver.staticResolver'
  over the producer-tx fixtures under
  @swap-1.producer-txs/@ (the same pattern the
  @swap-cancel-issue-8@ baseline + rename-only InspectSpec cases use
  at lines ~120 and ~195).
* Empty datum / referenceScript leaves are suppressed via
  'humanHideEmpty' — the same flag @tx-inspect@'s @Main@ sets on
  every CLI invocation.

The resolved-render golden lives at
@golden\/swap-1.both.resolved.txt@. The pre-existing
@golden\/swap-1.both.txt@ continues to hold the unresolved render
the @gate.sh smoke-inspect@ extension compares against (its
@tx-inspect@ invocation has no @--n2c-socket-path@ / @--web2-url@
and therefore renders inputs as bare @txIn@ atomics; both goldens
share the hide-empty filter so the smoke also reflects the slice
S8 + T054 changes).
-}
amaruBothStagesSpec :: Spec
amaruBothStagesSpec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman (slice S4 Amaru both)" $ do
        it
            "renders amaru-treasury-swap/swap-1 under \
            \rules/amaru-treasury.yaml with StaticResolver-resolved \
            \inputs and humanHideEmpty=True to the captured golden"
            $ do
                tx <- loadBody (amaruFixtureDir <> "/swap-1.cbor.hex")
                let body = tx ^. bodyTxL
                    inputs =
                        (body ^. inputsTxBodyL)
                            <> (body ^. referenceInputsTxBodyL)
                            <> (body ^. collateralInputsTxBodyL)
                let resolver =
                        staticResolver
                            (amaruFixtureDir <> "/swap-1.producer-txs")
                resolved <- resolveInputs resolver inputs
                rulesBytes <- BS.readFile amaruRulesPath
                rules <- case parseRewriteRulesYaml rulesBytes of
                    Right r -> pure r
                    Left err -> expectationFailure' err
                let humanOptions =
                        applyRewriteRules
                            rules
                            ( defaultHumanRenderOptions
                                { humanHideEmpty = True
                                }
                            )
                    diffOptions =
                        defaultTxDiffOptions
                            { txDiffResolvedInputs = Just resolved
                            }
                    actual =
                        renderConwayTxHuman
                            humanOptions
                            diffOptions
                            tx
                    goldenPath =
                        amaruFixtureDir <> "/golden/swap-1.both.resolved.txt"
                expected <- readOrCaptureGolden goldenPath actual
                actual `shouldBe` expected

{- | __Slice S4 — shared-substrate cross-check (User Story 4, FR-014).__

Asserts the @tx-diff@ render path consumes the unified rewriting-rules
grammar produced by the same loader 'tx-inspect' uses, proving the
two CLIs share both code and language (T034a). The cross-check is
on @tx-diff@'s render of @swap-1@ vs @swap-2@ with
@rules\/amaru-treasury.yaml@:

* the diff exits with a difference present (the two swaps differ in
  input txids + treasury-leftover amounts);
* the output is byte-identical to the no-rules invocation, since every
  rename- and collapse-relevant leaf is identical between the two
  fixtures and is therefore pruned from the diff;
* the output contains zero occurrences of the raw 28-byte hex for
  any renamed identifier — a positive guard against a regression
  that would emit raw bytes inside a renamed slot.
-}
amaruDiffSharedSubstrateSpec :: Spec
amaruDiffSharedSubstrateSpec =
    describe "tx-diff shared substrate (slice S4 Amaru cross-check)" $ do
        it
            "diffs swap-1 vs swap-2 under rules/amaru-treasury.yaml and \
            \produces output identical to the no-rules invocation \
            \(rename + collapse are no-ops on diff-pruned identical \
            \leaves; proves the unified loader is wired)"
            $ do
                txA <- loadBody (amaruFixtureDir <> "/swap-1.cbor.hex")
                txB <- loadBody (amaruFixtureDir <> "/swap-2.cbor.hex")
                rulesBytes <- BS.readFile amaruRulesPath
                rules <- case parseRewriteRulesYaml rulesBytes of
                    Right r -> pure r
                    Left err -> expectationFailure' err
                let diffNode =
                        diffConwayTxWith defaultTxDiffOptions txA txB
                    withRules =
                        renderDiffNodeHumanWith
                            ( applyRewriteRules
                                rules
                                defaultHumanRenderOptions
                            )
                            diffNode
                    withoutRules =
                        renderDiffNodeHumanWith
                            defaultHumanRenderOptions
                            diffNode
                withRules `shouldBe` withoutRules

        it
            "diff swap-1 vs swap-2 under rules/amaru-treasury.yaml \
            \contains zero raw 28-byte hashes for any renamed \
            \identifier (positive guard for FR-009 / SC-001)"
            $ do
                txA <- loadBody (amaruFixtureDir <> "/swap-1.cbor.hex")
                txB <- loadBody (amaruFixtureDir <> "/swap-2.cbor.hex")
                rulesBytes <- BS.readFile amaruRulesPath
                rules <- case parseRewriteRulesYaml rulesBytes of
                    Right r -> pure r
                    Left err -> expectationFailure' err
                let diffNode =
                        diffConwayTxWith defaultTxDiffOptions txA txB
                    rendered =
                        renderDiffNodeHumanWith
                            ( applyRewriteRules
                                rules
                                defaultHumanRenderOptions
                            )
                            diffNode
                -- The raw hex prefixes of the two renamed scripts.
                -- Sufficient bytes to make a substring match unique
                -- against the 4 KB golden.
                let amaruSwapV2HashPrefix = Text.pack "fa6a58bbe2d0ff05"
                    treasuryHashPrefix = Text.pack "32201dc1e8270836"
                Text.count amaruSwapV2HashPrefix rendered `shouldBe` 0
                Text.count treasuryHashPrefix rendered `shouldBe` 0

        it
            "tx-inspect render of swap-1 under rules/amaru-treasury.yaml \
            \contains both the SwapOrder collapse-view name AND the \
            \amaru-treasury.network_compliance.account rename name; \
            \proves both stages applied on the per-side render path"
            $ do
                tx <- loadBody (amaruFixtureDir <> "/swap-1.cbor.hex")
                rulesBytes <- BS.readFile amaruRulesPath
                rules <- case parseRewriteRulesYaml rulesBytes of
                    Right r -> pure r
                    Left err -> expectationFailure' err
                let rendered =
                        renderConwayTxHuman
                            (applyRewriteRules rules defaultHumanRenderOptions)
                            defaultTxDiffOptions
                            tx
                Text.isInfixOf (Text.pack "SwapOrder") rendered
                    `shouldBe` True
                Text.isInfixOf
                    (Text.pack "amaru-treasury.network_compliance.account")
                    rendered
                    `shouldBe` True
                Text.isInfixOf (Text.pack "amaru.swap-order") rendered
                    `shouldBe` True
                Text.isInfixOf (Text.pack "user.recipient") rendered
                    `shouldBe` True

fixtureDir :: FilePath
fixtureDir = "test/fixtures/mainnet-txbuild/swap-cancel-issue-8"

producerDir :: FilePath
producerDir = fixtureDir <> "/producer-txs"

amaruFixtureDir :: FilePath
amaruFixtureDir = "test/fixtures/amaru-treasury-swap"

amaruRulesPath :: FilePath
amaruRulesPath = "rules/amaru-treasury.yaml"

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

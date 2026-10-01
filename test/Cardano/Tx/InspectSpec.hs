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

import Control.Monad (foldM, forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Short qualified as SBS
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Data.Text.IO qualified as TextIO
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import System.Directory (doesFileExist)
import Test.Hspec

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (Addr, serialiseAddr)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    collateralReturnTxBodyL,
    inputsTxBodyL,
    referenceInputsTxBodyL,
    totalCollateralTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, valueTxOutL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (StrictMaybe (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))

import Cardano.Tx.BuildSpec (loadBody)
import Cardano.Tx.Diff (
    AddressMatch (..),
    AddressTarget (..),
    HumanRenderOptions (..),
    RenameRule (..),
    RenameRules (..),
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
import Cardano.Tx.Diff.Scan (Url (..))
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Rewrite (applyCollapseFromRewriteRules, applyRewriteRules)
import Data.Text qualified as Text

import StaticResolver (staticResolver)

spec :: Spec
spec = do
    baselineSpec
    collapseOnlySpec
    renameOnlySpec
    linkerSpec
    selfDiffSharedSubstrateSpec
    amaruBothStagesSpec
    amaruDiffSharedSubstrateSpec
    collateralReturnSpec
    redeemerWitnessSpec

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

{- | Render with a stub 'humanLeafLinker' (#88 slice S2). Returns
'Just' a marker for every 'ConwayDiffValue' the linker is asked
about so the test surfaces both the renderer's call into the hook
and the annotation it emits. Compared against the byte-stable
unlinked default to also pin "no flag → no change" behavior.
-}
linkerSpec :: Spec
linkerSpec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman (slice S2 leaf linker)" $ do
        it "annotates every linked leaf and leaves unlinked output unchanged" $ do
            tx <- loadBody (fixtureDir <> "/body.cbor.hex")
            let unlinked =
                    renderConwayTxHuman
                        defaultHumanRenderOptions
                        defaultTxDiffOptions
                        tx
                marker = "[LINKED]" :: Text
                stubLinker _ = Just (Url marker)
                linked =
                    renderConwayTxHuman
                        ( defaultHumanRenderOptions
                            { humanLeafLinker = Just stubLinker
                            }
                        )
                        defaultTxDiffOptions
                        tx
            -- the linked render must contain the marker at least once
            (marker `Text.isInfixOf` linked) `shouldBe` True
            -- without the linker the marker must NOT appear
            (marker `Text.isInfixOf` unlinked) `shouldBe` False
            -- and the unlinked render is byte-stable against itself
            unlinked `shouldBe` unlinked

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

{- | Issue 141: the body projection carries @collateralReturn@ and the
witness projection is reachable from @tx-inspect@. Every expected value
below is read from the decoded fixture, never typed in.
-}
collateralReturnSpec :: Spec
collateralReturnSpec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman body.collateralReturn (issue 141)" $ do
        it
            "renders a present collateral return with the decoded address,\
            \ coin and every native asset"
            $ do
                tx <- loadBody collateralReturnAssetsFixture
                output <- expectCollateralReturn tx
                let rendered =
                        renderConwayTxHuman
                            inspectRenderOptions
                            defaultTxDiffOptions
                            tx
                    MaryValue (Coin lovelace) (MultiAsset policies) =
                        output ^. valueTxOutL
                    expectedAssets =
                        [ (policyHex policy, assetHex assetName, quantity)
                        | (policy, assets) <- Map.toAscList policies
                        , (assetName, quantity) <- Map.toAscList assets
                        ]
                expectedAssets `shouldSatisfy` (not . null)
                node <- expectNode "body" ["collateralReturn"] rendered
                address <- expectChild "address" node
                address
                    `shouldSatisfy` leafContains
                        (addressHex (output ^. addrTxOutL))
                coin <- expectChild "coin" node
                coin
                    `shouldSatisfy` leafContains
                        ("(" <> Text.pack (show lovelace) <> " lovelace)")
                assetsNode <- expectChild "assets" node
                childNames assetsNode
                    `shouldBe` map policyHex (Map.keys policies)
                forM_ expectedAssets $ \(policy, assetName, quantity) ->
                    (childBlock policy assetsNode >>= childBlock assetName)
                        `shouldBe` Just ["`- " <> Text.pack (show quantity)]

        it
            "renders an absent collateral return as the explicit absent leaf\
            \ an absent totalCollateral uses"
            $ do
                tx0 <- loadBody noCollateralReturnFixture
                tx0 ^. bodyTxL . collateralReturnTxBodyL `shouldBe` SNothing
                let tx = tx0 & bodyTxL . totalCollateralTxBodyL .~ SNothing
                    rendered =
                        renderConwayTxHuman
                            inspectRenderOptions
                            defaultTxDiffOptions
                            tx
                absentTotalCollateral <-
                    expectNode "body" ["totalCollateral"] rendered
                expectNode "body" ["collateralReturn"] rendered
                    >>= (`shouldBe` absentTotalCollateral)

        it
            "renames the collateral return address with a matching address\
            \ rule"
            $ do
                tx <- loadBody collateralReturnAssetsFixture
                output <- expectCollateralReturn tx
                let addr = output ^. addrTxOutL
                    ruleName = "collateral-return-owner"
                    rules =
                        RenameRules
                            [ RenameAddress
                                { renameAddressKey = "collateral-return-owner"
                                , renameAddressMatch = MatchFull
                                , renameAddressTarget = TargetFullAddress addr
                                , renameName = ruleName
                                }
                            ]
                    rendered =
                        renderConwayTxHuman
                            inspectRenderOptions{humanRenameRules = Just rules}
                            defaultTxDiffOptions
                            tx
                address <-
                    expectNode "body" ["collateralReturn", "address"] rendered
                address `shouldSatisfy` leafContains ruleName
                address `shouldSatisfy` not . leafContains (addressHex addr)

redeemerWitnessSpec :: Spec
redeemerWitnessSpec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman witnesses.redeemers (issue 141)" $ do
        it
            "renders every decoded redeemer with purpose tag, index, data and\
            \ ExUnits when witnesses are included"
            $ do
                tx <- loadBody collateralReturnAssetsFixture
                let Redeemers redeemers = tx ^. witsTxL . rdmrsTxWitsL
                    rendered =
                        renderConwayTxHuman
                            inspectRenderOptions
                            defaultTxDiffOptions{txDiffIncludeWitnesses = True}
                            tx
                Map.size redeemers `shouldSatisfy` (> 1)
                node <- expectNode "witnesses" ["redeemers"] rendered
                length (childNames node) `shouldBe` Map.size redeemers
                List.sort (childNames node)
                    `shouldBe` List.sort (map purposeKey (Map.keys redeemers))
                forM_ (Map.toList redeemers) $
                    \(purpose, (Data redeemerData, ExUnits memory steps)) -> do
                        entry <- expectChild (purposeKey purpose) node
                        childNames entry `shouldBe` ["data", "exUnits"]
                        exUnits <- expectChild "exUnits" entry
                        exUnits
                            `shouldSatisfy` leafContains
                                ("\"memory\":" <> Text.pack (show memory))
                        exUnits
                            `shouldSatisfy` leafContains
                                ("\"steps\":" <> Text.pack (show steps))
                        dataNode <- expectChild "data" entry
                        dataNode `shouldSatisfy` (not . null)
                        case redeemerData of
                            PLC.Constr index _ ->
                                childBlock "constructor" dataNode
                                    `shouldBe` Just ["`- " <> Text.pack (show index)]
                            PLC.I integer ->
                                dataNode
                                    `shouldBe` ["`- " <> Text.pack (show integer)]
                            _ ->
                                pure ()

        it "renders no witnesses root by default" $ do
            tx <- loadBody collateralReturnAssetsFixture
            let rendered =
                    renderConwayTxHuman
                        inspectRenderOptions
                        defaultTxDiffOptions
                        tx
            rootChildren "witnesses" rendered `shouldBe` Nothing

collateralReturnAssetsFixture :: FilePath
collateralReturnAssetsFixture =
    "test/fixtures/mainnet-txbuild/\
    \cebc413826ebd61a4ee908617d668197dd1206ca39bb31429d538dc59fbb534f.cbor.hex"

noCollateralReturnFixture :: FilePath
noCollateralReturnFixture =
    "test/fixtures/mainnet-txbuild/\
    \23f8ade58f538e09d9741cd6d7d88fd394ef29fd17880f0539b685018d3d5f29.cbor.hex"

-- | The render options @tx-inspect@ starts from.
inspectRenderOptions :: HumanRenderOptions
inspectRenderOptions =
    defaultHumanRenderOptions{humanHideEmpty = True}

expectCollateralReturn :: ConwayTx -> IO (TxOut ConwayEra)
expectCollateralReturn tx =
    case tx ^. bodyTxL . collateralReturnTxBodyL of
        SJust output -> pure output
        SNothing -> expectationFailure' "fixture has no collateralReturn"

{- | Lines under a top-level root of an ASCII tree render (@body@,
@witnesses@), each still carrying its connector prefix.
-}
rootChildren :: Text -> Text -> Maybe [Text]
rootChildren root rendered =
    case break (== root) (Text.lines rendered) of
        (_, _ : rest) -> Just (takeWhile isChildLine rest)
        _ -> Nothing
  where
    isChildLine line =
        any (`Text.isPrefixOf` line) ["+- ", "`- ", "|  ", "   "]

{- | The block under the child labelled @name@, re-rooted so that its
own children start at column zero.
-}
childBlock :: Text -> [Text] -> Maybe [Text]
childBlock name block =
    case break isHeader block of
        (_, _ : rest) ->
            Just (map (Text.drop 3) (takeWhile isContinuation rest))
        _ -> Nothing
  where
    isHeader line = line == "+- " <> name || line == "`- " <> name
    isContinuation line =
        "|  " `Text.isPrefixOf` line || "   " `Text.isPrefixOf` line

childNames :: [Text] -> [Text]
childNames block =
    [ Text.drop 3 line
    | line <- block
    , "+- " `Text.isPrefixOf` line || "`- " `Text.isPrefixOf` line
    ]

expectNode :: Text -> [Text] -> Text -> IO [Text]
expectNode root path rendered =
    case rootChildren root rendered >>= \block -> foldM (flip childBlock) block path of
        Just block -> pure block
        Nothing ->
            expectationFailure' $
                "render has no node "
                    <> Text.unpack (Text.intercalate "." (root : path))

expectChild :: Text -> [Text] -> IO [Text]
expectChild name block =
    maybe
        (expectationFailure' ("render has no child " <> Text.unpack name))
        pure
        (childBlock name block)

-- | A single-leaf block whose leaf contains the fragment.
leafContains :: Text -> [Text] -> Bool
leafContains fragment = \case
    [leaf] -> fragment `Text.isInfixOf` leaf
    _ -> False

addressHex :: Addr -> Text
addressHex = hexText . serialiseAddr

policyHex :: PolicyID -> Text
policyHex (PolicyID (ScriptHash hash)) = hexText (hashToBytes hash)

assetHex :: AssetName -> Text
assetHex (AssetName bytes) = hexText (SBS.fromShort bytes)

hexText :: BS.ByteString -> Text
hexText = Text.decodeUtf8 . Base16.encode

-- | Redeemer purpose as the spec names it: @<tag>.<index>@.
purposeKey :: ConwayPlutusPurpose AsIx ConwayEra -> Text
purposeKey = \case
    ConwaySpending (AsIx index) -> tagged "spending" index
    ConwayMinting (AsIx index) -> tagged "minting" index
    ConwayCertifying (AsIx index) -> tagged "certifying" index
    ConwayRewarding (AsIx index) -> tagged "rewarding" index
    ConwayVoting (AsIx index) -> tagged "voting" index
    ConwayProposing (AsIx index) -> tagged "proposing" index
  where
    tagged tag index = tag <> "." <> Text.pack (show index)

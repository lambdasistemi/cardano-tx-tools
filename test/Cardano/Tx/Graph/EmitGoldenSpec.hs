{- |
Module      : Cardano.Tx.Graph.EmitGoldenSpec
Description : Byte-diff golden spec for the joint Turtle output (T005).
License     : Apache-2.0

Per-fixture byte-equality check: the Turtle bytes 'emit' produces
for a fixture's @(ConwayTx, ResolvedUTxO, [EntityDecl])@ tuple
must equal the committed @expected.ttl@.

T005 enabled fixture 02; T006-T010 grew coverage one slice at a
time; T010 closes the final three (01 collateral + multi-input,
10 TreasuryWithdrawal proposal, 11 collateral on the real-shape
mirror). All 11 fixtures are GREEN at end of T010 — SC-001 closed.
-}
module Cardano.Tx.Graph.EmitGoldenSpec (spec) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    EmittedGraph (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl,
    RulesLoadResult (..),
    loadRulesFile,
    rulesEntities,
 )

import Data.ByteString (ByteString)

import Fixtures.RewriteRedesign.S01_AmaruTreasurySwap qualified as S01
import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02
import Fixtures.RewriteRedesign.S03_MultiAssetTransfer qualified as S03
import Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap qualified as S04
import Fixtures.RewriteRedesign.S05_WithdrawalScriptStake qualified as S05
import Fixtures.RewriteRedesign.S06_StakePoolDelegation qualified as S06
import Fixtures.RewriteRedesign.S07_VoteDelegation qualified as S07
import Fixtures.RewriteRedesign.S08_ContingencyDisburse qualified as S08
import Fixtures.RewriteRedesign.S09_MpfsFactsRequest qualified as S09
import Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal qualified as S10
import Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal qualified as S11

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit joint Turtle goldens (T005)" $ do
    -- ---- fixture 02: enabled since T005 ----
    do
        let slug = "02-alice-bob-ada"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S02.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 03: enabled in T006 ----
    do
        let slug = "03-multi-asset-transfer"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S03.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 04: enabled in T007 ----
    do
        let slug = "04-mint-spend-script-overlap"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S04.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 05: enabled in T007 ----
    do
        let slug = "05-withdrawal-script-stake"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S05.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 08: enabled in T007 (regen-only) ----
    do
        let slug = "08-contingency-disburse"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S08.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 06: enabled in T008 ----
    do
        let slug = "06-stake-pool-delegation"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S06.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 07: enabled in T008 ----
    do
        let slug = "07-vote-delegation"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S07.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 09: enabled in T009 (regen-only) ----
    do
        let slug = "09-mpfs-facts-request"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S09.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 01: enabled in T010 ----
    do
        let slug = "01-amaru-treasury-swap"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S01.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 10: enabled in T010 ----
    do
        let slug = "10-governance-treasury-withdrawal"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S10.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"
    -- ---- fixture 11: enabled in T010 ----
    do
        let slug = "11-amaru-treasury-swap-real"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
            expectedPath = dir </> "expected.ttl"
        (entities, overlay) <-
            runIO (loadEntitiesAndOverlay rulesPath)
        expected <- runIO (BS.readFile expectedPath)
        it (slug <> " — emit + serialize matches expected.ttl") $ do
            case emit S11.tx emptyUtxo entities of
                Left err ->
                    expectationFailure $
                        "emit returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = overlay}
                        actual = serialize Turtle slug joint
                     in if actual == expected
                            then pure ()
                            else
                                expectationFailure $
                                    "byte-diff: emit("
                                        <> slug
                                        <> ") /= "
                                        <> expectedPath
                                        <> " (lengths "
                                        <> show (BS.length actual)
                                        <> " vs "
                                        <> show (BS.length expected)
                                        <> ")"

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

loadEntitiesAndOverlay ::
    FilePath -> IO ([EntityDecl], ByteString)
loadEntitiesAndOverlay path = do
    result <- loadRulesFile path
    case result of
        Right res@RulesLoadResult{rulesOverlayTurtle} ->
            pure (rulesEntities res, rulesOverlayTurtle)
        Left err ->
            fail $
                "EmitGoldenSpec.loadEntitiesAndOverlay: "
                    <> path
                    <> ": "
                    <> show err

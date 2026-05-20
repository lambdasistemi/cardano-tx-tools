{- |
Module      : Cardano.Tx.Graph.EmitGoldenSpec
Description : Byte-diff golden spec for the joint Turtle output (T005).
License     : Apache-2.0

Per-fixture byte-equality check: the Turtle bytes 'emit' produces
for a fixture's @(ConwayTx, ResolvedUTxO, [EntityDecl])@ tuple
must equal the committed @expected.ttl@.

T005 enables fixture 02 only; the other 10 entries are
'pendingWith' messages naming the future slice that activates each
one (T006 mint, T007 datum/redeemer, T008 cert, T009 governance,
T010 collateral / leftovers).
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

import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02
import Fixtures.RewriteRedesign.S03_MultiAssetTransfer qualified as S03
import Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap qualified as S04
import Fixtures.RewriteRedesign.S05_WithdrawalScriptStake qualified as S05
import Fixtures.RewriteRedesign.S08_ContingencyDisburse qualified as S08

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    pendingWith,
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
    -- ---- pending entries ----
    pendingFixture
        "01-amaru-treasury-swap"
        "T010: collateral input + multi-input (33 swap orders)"
    pendingFixture
        "06-stake-pool-delegation"
        "T008: stake-delegation certificate + PoolId leaf"
    pendingFixture
        "07-vote-delegation"
        "T008: vote-delegation certificate + DRep leaf"
    pendingFixture
        "09-mpfs-facts-request"
        "T009: 10-output structural-only (regen)"
    pendingFixture
        "10-governance-treasury-withdrawal"
        "T009: proposal + treasury withdrawal action"
    pendingFixture
        "11-amaru-treasury-swap-real"
        "T010: real-bytes mainnet mirror; collateral + inline datum"

pendingFixture :: FilePath -> String -> Spec
pendingFixture slug reason =
    it (slug <> " — emit + serialize matches expected.ttl") $
        pendingWith reason

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

{- |
Module      : Cardano.Tx.View.AssetFlowSpec
Description : tx-view --view asset-flow projection spec (slice S2 of #51).
License     : Apache-2.0

S2 slice of #51 (T200-T206 in @specs\/051-sparql-views\/tasks.md@).

Asserts the @asset-flow@ packaged view over the Amaru swap canonical
Turtle graph (fixture @01-amaru-treasury-swap@):

* exits 0 with empty stderr;
* renders non-empty stdout;
* names the moved asset class @ada@ (the only asset class the swap
  fixture carries — no @cardano:hasAssetValue@ or @cardano:hasMint@);
* names the per-output quantities @1500000@ and @850000@;
* names the destination as the @addr_test1@ bech32 the outputs are
  paid to;
* names the source as the honest @\<unknown\>@ placeholder, since the
  canonical graph for this fixture has no UTxO resolution and the
  inputs only carry @cardano:fromTxOutRef@.

Also asserts the FR-008 empty-result invariant: a Turtle graph with
no @cardano:Transaction@ subject produces an exit-0 empty stdout for
@--view asset-flow@.

The binary is located by 'locateTxView' (same lookup as
'Cardano.Tx.View.CliTreeGoldenSpec'): prefer @TX_VIEW_EXE@ then fall
back to @PATH@ via @System.Directory.findExecutable@.
-}
module Cardano.Tx.View.AssetFlowSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (
    CreateProcess (..),
    StdStream (..),
    proc,
    waitForProcess,
    withCreateProcess,
 )
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
    shouldSatisfy,
 )

----------------------------------------------------------------------
-- Spec entry point
----------------------------------------------------------------------

spec :: Spec
spec =
    describe "Cardano.Tx.View — asset-flow projection (slice S2 of #51)" $ do
        mExe <- runIO locateTxView
        case mExe of
            Nothing ->
                it "tx-view executable is on PATH or pointed at by TX_VIEW_EXE" $
                    expectationFailure $
                        "tx-view is neither on PATH (via cabal's "
                            <> "build-tool-depends) nor pointed at by "
                            <> "TX_VIEW_EXE. The asset-flow slice cannot "
                            <> "run without the executable in the sandbox."
            Just exe -> do
                amaruSwapCase exe
                emptyGraphCase exe

----------------------------------------------------------------------
-- Amaru swap fixture — deterministic asset-flow row content
----------------------------------------------------------------------

{- | The Amaru swap canonical graph must produce non-empty, deterministic
asset-flow rows naming the moved asset class, the per-output
quantities, the destination address, and the honest unknown-source
placeholder.
-}
amaruSwapCase :: FilePath -> Spec
amaruSwapCase exe =
    describe "01-amaru-treasury-swap" $ do
        let graphPath =
                "test/fixtures/rewrite-redesign"
                    </> "01-amaru-treasury-swap"
                    </> "expected.ttl"
            runIt =
                runExe
                    exe
                    [ "--graph"
                    , graphPath
                    , "--view"
                    , "asset-flow"
                    ]
            destBech32 =
                BS8.pack
                    "addr_test1vqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqd9tg5t"

        it "exits 0 with empty stderr" $ do
            (code, _, err) <- runIt
            err `shouldBe` BS.empty
            code `shouldBe` ExitSuccess

        it "emits a non-empty asset-flow projection" $ do
            (_, out, _) <- runIt
            out `shouldSatisfy` (not . BS.null)

        it "names the moved asset class (ada)" $ do
            (_, out, _) <- runIt
            out `shouldSatisfy` containsBS (BS8.pack "ada")

        it "names the per-output quantities (1500000 and 850000)" $ do
            (_, out, _) <- runIt
            out `shouldSatisfy` containsBS (BS8.pack "1500000")
            out `shouldSatisfy` containsBS (BS8.pack "850000")

        it "names the destination output address" $ do
            (_, out, _) <- runIt
            out `shouldSatisfy` containsBS destBech32

        it "honestly marks the source as <unknown>" $ do
            (_, out, _) <- runIt
            out `shouldSatisfy` containsBS (BS8.pack "<unknown>")

----------------------------------------------------------------------
-- Empty-result invariant — FR-008
----------------------------------------------------------------------

{- | A Turtle graph with no @cardano:Transaction@ subject produces an
exit-0 empty stdout for @--view asset-flow@.
-}
emptyGraphCase :: FilePath -> Spec
emptyGraphCase exe =
    it "empty graph (no Transaction subject) — exit 0, empty stdout" $
        withSystemTempDirectory "tx-view-asset-flow-empty" $ \dir -> do
            let graphPath = dir </> "empty.ttl"
            BS.writeFile
                graphPath
                ( BS8.pack
                    ( "@prefix cardano: "
                        <> "<https://lambdasistemi.github.io/"
                        <> "cardano-knowledge-maps/vocab/cardano#> .\n"
                    )
                )
            (code, out, err) <-
                runExe
                    exe
                    [ "--graph"
                    , graphPath
                    , "--view"
                    , "asset-flow"
                    ]
            err `shouldBe` BS.empty
            code `shouldBe` ExitSuccess
            out `shouldBe` BS.empty

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{- | Locate the tx-view binary. Prefers @TX_VIEW_EXE@ when set (the
nix flake check sandbox path); falls back to @findExecutable@ on
@PATH@ (the @cabal test@ path, where cabal places the binary on
@PATH@ via @build-tool-depends@).
-}
locateTxView :: IO (Maybe FilePath)
locateTxView = do
    mEnv <- lookupEnv "TX_VIEW_EXE"
    case mEnv of
        Just p | not (null p) -> pure (Just p)
        _ -> findExecutable "tx-view"

-- | Spawn an external program, capture stdout + stderr, return exit code.
runExe :: FilePath -> [String] -> IO (ExitCode, ByteString, ByteString)
runExe prog args = do
    let cp =
            (proc prog args)
                { std_in = NoStream
                , std_out = CreatePipe
                , std_err = CreatePipe
                }
    withCreateProcess cp $ \_mIn mOut mErr ph ->
        case (mOut, mErr) of
            (Just hOut, Just hErr) -> do
                out <- BS.hGetContents hOut
                err <- BS.hGetContents hErr
                hClose hOut
                hClose hErr
                code <- waitForProcess ph
                pure (code, out, err)
            _ ->
                fail $
                    "runExe: stdout/stderr pipes not created for " <> prog

-- | True when @needle@ occurs as a substring of @haystack@.
containsBS :: ByteString -> ByteString -> Bool
containsBS needle haystack = needle `BS.isInfixOf` haystack

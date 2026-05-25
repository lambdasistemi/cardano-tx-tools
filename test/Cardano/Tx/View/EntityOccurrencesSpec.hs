{- |
Module      : Cardano.Tx.View.EntityOccurrencesSpec
Description : tx-view --view entity-occurrences projection spec (slice S3 of #51).
License     : Apache-2.0

S3 slice of #51 (T300-T306 in @specs\/051-sparql-views\/tasks.md@).

Asserts the @entity-occurrences@ packaged view over the Amaru swap
canonical Turtle graph (fixture @01-amaru-treasury-swap@):

* exits 0 with empty stderr;
* renders one deterministic tab-separated row per operator-declared
  entity;
* counts the entity leaf-site references carried by that fixture;
* is structurally distinct from @asset-flow@ output.

Expected row format:

@
\<entityLabel\>\\t\<leafSiteCount\>\\n
@

The binary is located by 'locateTxView' (same lookup as
'Cardano.Tx.View.CliTreeGoldenSpec'): prefer @TX_VIEW_EXE@ then fall
back to @PATH@ via @System.Directory.findExecutable@.
-}
module Cardano.Tx.View.EntityOccurrencesSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hClose)
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
    shouldNotBe,
 )

----------------------------------------------------------------------
-- Spec entry point
----------------------------------------------------------------------

spec :: Spec
spec =
    describe "Cardano.Tx.View - entity-occurrences projection (slice S3 of #51)" $ do
        mExe <- runIO locateTxView
        case mExe of
            Nothing ->
                it "tx-view executable is on PATH or pointed at by TX_VIEW_EXE" $
                    expectationFailure $
                        "tx-view is neither on PATH (via cabal's "
                            <> "build-tool-depends) nor pointed at by "
                            <> "TX_VIEW_EXE. The entity-occurrences slice "
                            <> "cannot run without the executable in the "
                            <> "sandbox."
            Just exe ->
                amaruSwapCase exe

----------------------------------------------------------------------
-- Amaru swap fixture - deterministic entity occurrence rows
----------------------------------------------------------------------

amaruSwapCase :: FilePath -> Spec
amaruSwapCase exe =
    describe "01-amaru-treasury-swap" $
        it "renders per-entity counts distinct from asset-flow" $ do
            let graphPath =
                    "test/fixtures/rewrite-redesign"
                        </> "01-amaru-treasury-swap"
                        </> "expected.ttl"
                runView viewName =
                    runExe
                        exe
                        [ "--graph"
                        , graphPath
                        , "--view"
                        , viewName
                        ]

            (entityCode, entityOut, entityErr) <- runView "entity-occurrences"
            entityErr `shouldBe` BS.empty
            entityCode `shouldBe` ExitSuccess
            entityOut `shouldBe` expectedEntityOccurrences

            (assetCode, assetOut, assetErr) <- runView "asset-flow"
            assetErr `shouldBe` BS.empty
            assetCode `shouldBe` ExitSuccess
            entityOut `shouldNotBe` assetOut

expectedEntityOccurrences :: ByteString
expectedEntityOccurrences =
    BS8.pack $
        unlines
            [ "amaru-treasury.network_compliance\t2"
            , "amaru.swap-order\t2"
            , "amaru.swap.v2\t1"
            , "amaru.network-wallet\t2"
            , "usdm\t1"
            ]

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

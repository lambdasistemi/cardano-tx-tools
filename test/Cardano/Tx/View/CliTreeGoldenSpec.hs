{- |
Module      : Cardano.Tx.View.CliTreeGoldenSpec
Description : tx-view executable + cli-tree projection byte-equivalence spec.
License     : Apache-2.0

Cli-tree slice of #51. For each of the ten mandatory rewrite-redesign
stub fixtures (per Q-001 -> A-001), spawn the @tx-view@ binary as a
subprocess against the fixture's canonical Turtle graph
(@expected.ttl@) and assert the @--view cli-tree@ stdout
byte-equals the view-side golden under
@test\/fixtures\/views\/\<slug\>\/cli-tree.txt@.

The view-side goldens reflect the @cli-tree@ projection over the data
the canonical graph actually carries today (stub all-zero credential
bytes, raw policy hashes, undecoded datum bytes); 044 byte-equivalence
to @expected.txt@ is deferred to the fixture-bridging follow-on filed
as issue #98.

The binary is located by 'locateTxView', which prefers the
@TX_VIEW_EXE@ environment variable and falls back to
'System.Directory.findExecutable' on @PATH@:

* @nix flake check@ unit gate — @flake.nix@ wraps the base unit
  script with an @export TX_VIEW_EXE=…@ line pointing at
  @components.exes.tx-view@.
* @just unit@ / @cabal test@ — the test-suite stanza declares
  @build-tool-depends: cardano-tx-tools:tx-view@, so @cabal@ places
  the binary on @PATH@ for the test process. 'findExecutable'
  then finds it.

If neither path resolves, the test fails (the slice has not wired
the executable into the sandbox).

The CLI surface under test is locked at:

@
tx-view --graph FILE --view NAME [--out FILE]
@

with @--view@ defaulting to @cli-tree@ and @--out@ defaulting to
stdout.
-}
module Cardano.Tx.View.CliTreeGoldenSpec (spec) where

import Control.Monad (unless)
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
-- Mandatory cli-tree corpus
----------------------------------------------------------------------

{- | The ten rewrite-redesign fixtures the cli-tree slice covers.
Per Q-001 -> A-001, fixtures 11+ are deferred to the fixture-bridging
follow-on (issue #98).
-}
mandatoryFixtures :: [String]
mandatoryFixtures =
    [ "01-amaru-treasury-swap"
    , "02-alice-bob-ada"
    , "03-multi-asset-transfer"
    , "04-mint-spend-script-overlap"
    , "05-withdrawal-script-stake"
    , "06-stake-pool-delegation"
    , "07-vote-delegation"
    , "08-contingency-disburse"
    , "09-mpfs-facts-request"
    , "10-governance-treasury-withdrawal"
    ]

----------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec = describe "Cardano.Tx.View — tx-view executable + cli-tree projection" $ do
    mExe <- runIO locateTxView
    case mExe of
        Nothing ->
            it "tx-view executable is on PATH or pointed at by TX_VIEW_EXE" $
                expectationFailure $
                    "tx-view is neither on PATH (via cabal's "
                        <> "build-tool-depends) nor pointed at by "
                        <> "TX_VIEW_EXE (set by the flake.nix unit "
                        <> "check). The cli-tree slice has not wired "
                        <> "the executable into the test sandbox."
        Just exe -> do
            describe "cli-tree byte-equivalence with view-side goldens" $
                mapM_ (cliTreeFixtureCase exe) mandatoryFixtures
            describe "CLI surface" $ do
                emptyGraphCase exe
                defaultsToCliTreeCase exe
                outFileCase exe
                unknownViewCase exe
                missingGraphCase exe

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

----------------------------------------------------------------------
-- Per-fixture cli-tree golden cases
----------------------------------------------------------------------

{- | One per-fixture byte-equivalence check. The view-side golden
@test\/fixtures\/views\/\<slug\>\/cli-tree.txt@ is the
graph-derivable cli-tree projection of the fixture's canonical
Turtle graph.
-}
cliTreeFixtureCase :: FilePath -> String -> Spec
cliTreeFixtureCase exe slug =
    it (slug <> " — tx-view --view cli-tree matches cli-tree.txt") $ do
        let graphPath =
                "test/fixtures/rewrite-redesign" </> slug </> "expected.ttl"
            goldenPath =
                "test/fixtures/views" </> slug </> "cli-tree.txt"
        expected <- BS.readFile goldenPath
        (code, out, err) <-
            runExe
                exe
                [ "--graph"
                , graphPath
                , "--view"
                , "cli-tree"
                ]
        err `shouldBe` BS.empty
        code `shouldBe` ExitSuccess
        unless (out == expected) $
            expectationFailure $
                "cli-tree output mismatch for "
                    <> slug
                    <> " (golden: "
                    <> goldenPath
                    <> ")"

----------------------------------------------------------------------
-- CLI-surface cases
----------------------------------------------------------------------

{- | Empty-match invariant (spec edge case + FR-008): a graph with no
@cardano:Transaction@ triples produces an empty result and exits 0.
-}
emptyGraphCase :: FilePath -> Spec
emptyGraphCase exe =
    it "empty graph (no Transaction subject) — exit 0, empty stdout" $
        withSystemTempDirectory "tx-view-empty" $ \dir -> do
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
                    , "cli-tree"
                    ]
            err `shouldBe` BS.empty
            code `shouldBe` ExitSuccess
            out `shouldBe` BS.empty

{- | @--view@ defaults to @cli-tree@ when omitted (spec FR-002 + edge
case): running @tx-view --graph FILE@ produces the same output as
@tx-view --graph FILE --view cli-tree@.
-}
defaultsToCliTreeCase :: FilePath -> Spec
defaultsToCliTreeCase exe =
    it "--view defaults to cli-tree" $ do
        let graphPath =
                "test/fixtures/rewrite-redesign"
                    </> "02-alice-bob-ada"
                    </> "expected.ttl"
        (codeDefault, outDefault, _) <-
            runExe exe ["--graph", graphPath]
        (codeExplicit, outExplicit, _) <-
            runExe
                exe
                [ "--graph"
                , graphPath
                , "--view"
                , "cli-tree"
                ]
        codeDefault `shouldBe` ExitSuccess
        codeExplicit `shouldBe` ExitSuccess
        outDefault `shouldBe` outExplicit

{- | @--out FILE@ writes the rendered view to @FILE@ and leaves stdout
empty (spec FR-002 + edge case).
-}
outFileCase :: FilePath -> Spec
outFileCase exe =
    it "--out FILE writes to file, stdout empty" $
        withSystemTempDirectory "tx-view-out" $ \dir -> do
            let graphPath =
                    "test/fixtures/rewrite-redesign"
                        </> "02-alice-bob-ada"
                        </> "expected.ttl"
                outPath = dir </> "cli-tree.txt"
            (code, stdoutBytes, _) <-
                runExe
                    exe
                    [ "--graph"
                    , graphPath
                    , "--view"
                    , "cli-tree"
                    , "--out"
                    , outPath
                    ]
            code `shouldBe` ExitSuccess
            stdoutBytes `shouldBe` BS.empty
            written <- BS.readFile outPath
            written `shouldSatisfy` (not . BS.null)

{- | Unknown @--view@ name fails non-zero with a usage-level error
on stderr (spec edge case).
-}
unknownViewCase :: FilePath -> Spec
unknownViewCase exe =
    it "unknown --view name — non-zero exit, stderr non-empty" $ do
        let graphPath =
                "test/fixtures/rewrite-redesign"
                    </> "02-alice-bob-ada"
                    </> "expected.ttl"
        (code, _, err) <-
            runExe
                exe
                [ "--graph"
                , graphPath
                , "--view"
                , "no-such-view"
                ]
        code `shouldSatisfy` isFailure
        err `shouldSatisfy` (not . BS.null)

{- | Missing @--graph@ file fails non-zero with a clear stderr line
(spec edge case).
-}
missingGraphCase :: FilePath -> Spec
missingGraphCase exe =
    it "missing --graph file — non-zero exit, stderr non-empty" $
        withSystemTempDirectory "tx-view-missing" $ \dir -> do
            let graphPath = dir </> "does-not-exist.ttl"
            (code, _, err) <-
                runExe
                    exe
                    [ "--graph"
                    , graphPath
                    , "--view"
                    , "cli-tree"
                    ]
            code `shouldSatisfy` isFailure
            err `shouldSatisfy` (not . BS.null)

----------------------------------------------------------------------
-- Subprocess helpers
----------------------------------------------------------------------

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

-- | Non-zero exit detector.
isFailure :: ExitCode -> Bool
isFailure ExitSuccess = False
isFailure (ExitFailure _) = True

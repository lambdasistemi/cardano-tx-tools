{- |
Module      : Cardano.Tx.Graph.Rules.LoadExeSpec
Description : End-to-end tests for the @tx-graph@ executable surface (T011).
License     : Apache-2.0

Drives the freshly-built @tx-graph@ binary as a subprocess to exercise
the three CLI surfaces called out by US7:

* @tx-graph --rules \<fixture\>/rules.yaml@ on a basic fixture produces
  exit 0, an empty stderr, and a stdout byte-stream that equals the
  fixture's @expected.entities.ttl@.
* @tx-graph --rules \<cycle\>@ on a rules graph with an import cycle
  produces a non-zero exit and a stderr line containing the
  @RulesImportCycle@ tag from
  'Cardano.Tx.Graph.Rules.Load.renderRulesLoadError'.
* @tx-graph@ with no arguments produces a non-zero exit and a stderr
  payload that mentions @--rules@ — the @optparse-applicative@
  default usage message.

The binary is located via @cabal list-bin@ inside an @hspec@
@beforeAll_@ hook so the spec is self-locating regardless of GHC
version or build profile. The gate script (./gate.sh) runs
@just build@ before @just unit@, so the binary is always present
when this spec runs.
-}
module Cardano.Tx.Graph.Rules.LoadExeSpec (spec) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.List (isInfixOf)
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
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec = describe "tx-graph executable (T011, US7)" $ do
    txGraphPath <- runIO locateTxGraph
    it
        ( "--rules <fixture-02>/rules.yaml — exit 0, stdout byte-equals"
            <> " expected.entities.ttl, stderr empty"
        )
        $ do
            let rulesPath =
                    "test/fixtures/rewrite-redesign"
                        </> "02-alice-bob-ada"
                        </> "rules.yaml"
                expectedPath =
                    "test/fixtures/rewrite-redesign"
                        </> "02-alice-bob-ada"
                        </> "expected.entities.ttl"
            expected <- BS.readFile expectedPath
            (code, out, err) <-
                runExe txGraphPath ["--rules", rulesPath]
            err `shouldBe` BS.empty
            unless (out == expected) $
                expectationFailure $
                    unlines
                        [ "tx-graph stdout did not match "
                            <> expectedPath
                        , "--- expected (first 400 bytes):"
                        , take 400 (showBytes expected)
                        , "--- actual (first 400 bytes):"
                        , take 400 (showBytes out)
                        ]
            code `shouldBe` ExitSuccess

    it
        ( "--rules <cycle.yaml> — non-zero exit, stderr contains"
            <> " RulesImportCycle"
        )
        $ do
            withSystemTempDirectory "tx-graph-cycle" $ \dir -> do
                let aPath = dir </> "a.yaml"
                    bPath = dir </> "b.yaml"
                BS.writeFile aPath $
                    "imports:\n  - b.yaml\nentities:\n"
                        <> "  - name: a_ent\n"
                        <> "    script: "
                        <> hex28A
                        <> "\n"
                BS.writeFile bPath $
                    "imports:\n  - a.yaml\nentities:\n"
                        <> "  - name: b_ent\n"
                        <> "    script: "
                        <> hex28B
                        <> "\n"
                (code, _out, err) <-
                    runExe txGraphPath ["--rules", aPath]
                code `shouldSatisfy` isFailure
                BS8.unpack err
                    `shouldSatisfy` ("RulesImportCycle" `isInfixOf`)

    it "no arguments — non-zero exit, stderr usage mentions --rules" $ do
        (code, _out, err) <- runExe txGraphPath []
        code `shouldSatisfy` isFailure
        BS8.unpack err
            `shouldSatisfy` ("--rules" `isInfixOf`)

----------------------------------------------------------------------
-- Subprocess helpers
----------------------------------------------------------------------

{- | Locate the freshly-built @tx-graph@ binary via @cabal list-bin@.
The gate script builds the executable before the unit suite runs, so
the binary is always present in @dist-newstyle@. Fails loudly with
the captured @cabal@ stderr if the binary cannot be located so a
regression in the cabal stanza surfaces as an actionable test
failure rather than a confusing @no such file@ from
'runExe'.
-}
locateTxGraph :: IO FilePath
locateTxGraph = do
    (code, out, err) <-
        runExe
            "cabal"
            [ "list-bin"
            , "-O0"
            , "exe:tx-graph"
            ]
    case code of
        ExitSuccess ->
            pure (trimTrailingNewline (BS8.unpack out))
        _ ->
            fail $
                "cabal list-bin exe:tx-graph failed: " <> BS8.unpack err

-- | Spawn an external program, capture stdout + stderr, return exit code.
runExe :: FilePath -> [String] -> IO (ExitCode, ByteString, ByteString)
runExe prog args = do
    let cp =
            (proc prog args)
                { std_in = NoStream
                , std_out = CreatePipe
                , std_err = CreatePipe
                }
    withCreateProcess cp $ \_mStdin mStdout mStderr ph ->
        case (mStdout, mStderr) of
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

-- | Strip a single trailing newline from a 'String'.
trimTrailingNewline :: String -> String
trimTrailingNewline s = case reverse s of
    '\n' : rest -> reverse rest
    _ -> s

-- | Render a 'ByteString' as a Latin-1 'String' for diff dumps.
showBytes :: ByteString -> String
showBytes = map (toEnum . fromEnum) . BS.unpack

----------------------------------------------------------------------
-- Fixture bytes (cycle test)
----------------------------------------------------------------------

{- | Two distinct 28-byte hex blobs the cycle test uses for the
@script:@ fields of @a_ent@ / @b_ent@. Each starts with an
alphabetic nibble so YAML decodes the value as a string, not as
a number.
-}
hex28A, hex28B :: ByteString
hex28A = "aa11111111111111111111111111111111111111111111111111111a"
hex28B = "bb22222222222222222222222222222222222222222222222222222b"

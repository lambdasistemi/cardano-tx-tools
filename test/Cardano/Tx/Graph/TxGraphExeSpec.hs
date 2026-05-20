{- |
Module      : Cardano.Tx.Graph.TxGraphExeSpec
Description : Exe-level smoke for the tx-graph @--tx@/@--utxo@/@--out@/@--format@ flags (T003).
License     : Apache-2.0

Drives the freshly-built @tx-graph@ binary as a subprocess to cover
the three dispatcher modes introduced by T003 (plan slice D8):

* overlay-only (@--rules@ alone) — the existing #48 contract, kept
  GREEN here as a regression guard alongside
  'Cardano.Tx.Graph.Rules.LoadExeSpec';
* body-only (@--tx@) and joint (@--rules@ + @--tx@ + @--utxo@) —
  pre-T005 short-circuit: every body-emitting mode exits non-zero
  with @NoSerializerYet@ on stderr until T005 wires the Turtle
  serializer;
* structured error rendering — a missing @--tx@ file surfaces a
  'Cardano.Tx.Graph.Emit.MalformedTxCbor' line; an unknown
  @--format@ argument surfaces 'Cardano.Tx.Graph.Emit.UnknownFormat'.

The binary is located via the @TX_GRAPH_EXE@ environment variable
(set by the @nix flake check@ sandbox and the @just unit@ recipe)
or @cabal list-bin -O0 exe:tx-graph@ as a dev-shell fallback —
identical to 'Cardano.Tx.Graph.Rules.LoadExeSpec'.

The fixture-02 @S02.tx@ builder
(@Fixtures.RewriteRedesign.S02_AliceBobAda@) is reused: each test
case writes a tmp @tx.cbor@ + @utxo.json@ to
'System.IO.Temp.withSystemTempDirectory' so no new on-disk
fixture is needed.
-}
module Cardano.Tx.Graph.TxGraphExeSpec (spec) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BSL
import Data.List (isInfixOf)
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
    pendingWith,
    runIO,
    shouldBe,
    shouldSatisfy,
 )

import Cardano.Ledger.Binary (serialize)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)

import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02

----------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec = describe "tx-graph executable (T003, body-emitter dispatcher)" $ do
    mEnvPath <- runIO (lookupEnv "TX_GRAPH_EXE")
    case mEnvPath of
        Nothing ->
            it "skipped — TX_GRAPH_EXE not set" $
                pendingWith
                    ( "TX_GRAPH_EXE not set; exe-level tests require the "
                        <> "nix flake check / just unit harness."
                    )
        Just "" ->
            it "skipped — TX_GRAPH_EXE empty" $
                pendingWith "TX_GRAPH_EXE is set but empty."
        Just txGraphPath -> do
            it
                ( "(1) overlay-only mode (--rules alone) — exit 0, stdout"
                    <> " byte-equals expected.entities.ttl"
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
                            "tx-graph overlay-only stdout mismatch ("
                                <> expectedPath
                                <> ")"
                    code `shouldBe` ExitSuccess

            it
                ( "(2) body-only mode (--tx only) — exit 0, stdout"
                    <> " carries the # Transaction body. section"
                )
                $ withSystemTempDirectory "tx-graph-body"
                $ \dir -> do
                    let txPath = dir </> "tx.cbor"
                    BS.writeFile txPath s02CborBytes
                    (code, out, _err) <-
                        runExe txGraphPath ["--tx", txPath]
                    code `shouldBe` ExitSuccess
                    BS8.unpack out
                        `shouldSatisfy` ("# Transaction body." `isInfixOf`)

            it
                ( "(3) joint mode (--rules + --tx + --utxo) — exit 0,"
                    <> " stdout carries both the entities overlay and the"
                    <> " transaction body"
                )
                $ withSystemTempDirectory "tx-graph-joint"
                $ \dir -> do
                    let txPath = dir </> "tx.cbor"
                        utxoPath = dir </> "utxo.json"
                        rulesPath =
                            "test/fixtures/rewrite-redesign"
                                </> "02-alice-bob-ada"
                                </> "rules.yaml"
                    BS.writeFile txPath s02CborBytes
                    BS.writeFile utxoPath "{}"
                    (code, out, _err) <-
                        runExe
                            txGraphPath
                            [ "--rules"
                            , rulesPath
                            , "--tx"
                            , txPath
                            , "--utxo"
                            , utxoPath
                            ]
                    code `shouldBe` ExitSuccess
                    BS8.unpack out
                        `shouldSatisfy` ( "Operator-declared entities"
                                            `isInfixOf`
                                        )
                    BS8.unpack out
                        `shouldSatisfy` ("# Transaction body." `isInfixOf`)

            it
                ( "(4) missing --tx file — non-zero exit, stderr contains"
                    <> " MalformedTxCbor"
                )
                $ withSystemTempDirectory "tx-graph-missing"
                $ \dir -> do
                    let rulesPath =
                            "test/fixtures/rewrite-redesign"
                                </> "02-alice-bob-ada"
                                </> "rules.yaml"
                        bogusTx = dir </> "does-not-exist.cbor"
                    (code, _out, err) <-
                        runExe
                            txGraphPath
                            [ "--rules"
                            , rulesPath
                            , "--tx"
                            , bogusTx
                            ]
                    code `shouldSatisfy` isFailure
                    BS8.unpack err
                        `shouldSatisfy` ("MalformedTxCbor" `isInfixOf`)

            it
                ( "(5) unknown --format value — non-zero exit, stderr"
                    <> " contains UnknownFormat"
                )
                $ withSystemTempDirectory "tx-graph-format"
                $ \dir -> do
                    let txPath = dir </> "tx.cbor"
                        rulesPath =
                            "test/fixtures/rewrite-redesign"
                                </> "02-alice-bob-ada"
                                </> "rules.yaml"
                    BS.writeFile txPath s02CborBytes
                    (code, _out, err) <-
                        runExe
                            txGraphPath
                            [ "--rules"
                            , rulesPath
                            , "--tx"
                            , txPath
                            , "--format"
                            , "yaml"
                            ]
                    code `shouldSatisfy` isFailure
                    BS8.unpack err
                        `shouldSatisfy` ("UnknownFormat" `isInfixOf`)

----------------------------------------------------------------------
-- Tx fixture bytes
----------------------------------------------------------------------

{- | Serialized ConwayEra CBOR of the fixture-02 @S02.tx@ builder.
Reuses the same @ConwayTx@ value that 'Cardano.Tx.Graph.EmitSmokeSpec'
exercises; we ship the bytes through a temp file so the executable
can read them via @--tx@ without a new on-disk fixture.
-}
s02CborBytes :: ByteString
s02CborBytes =
    BSL.toStrict (serialize (eraProtVerLow @ConwayEra) S02.tx)

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

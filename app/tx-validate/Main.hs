{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Main
Description : tx-validate executable entry point.
License     : Apache-2.0

Thin wrapper over @Cardano.Tx.Validate.Cli@. Opens the N2C
session, resolves the tx's UTxO via the existing
@cardano-tx-tools:n2c-resolver@ chain, calls
@validatePhase1@, and renders the verdict.
-}
module Main (main) where

import Control.Concurrent.Async (withAsync)
import Control.Monad (void)
import Data.Aeson.Encode.Pretty qualified as Aeson.Pretty
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.IO qualified as TextIO
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr, stdin, stdout)

import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Binary (
    Annotator,
    Decoder,
    decCBOR,
    decodeFullAnnotatorFromHexText,
    natVersion,
 )
import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.Provider (
    LedgerSnapshot (..),
    Provider (..),
 )
import Ouroboros.Network.Magic (NetworkMagic (..))

import Cardano.Tx.Build (mkPParamsBound)
import Cardano.Tx.Diff.Resolver (resolveChain, resolverName)
import Cardano.Tx.Diff.Resolver.N2C (n2cResolver)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Validate (validatePhase1)
import Cardano.Tx.Validate.Cli (
    InputSource (..),
    N2cConfig (..),
    OutputFormat (..),
    Session (..),
    TxValidateCliOptions (..),
    buildVerdict,
    collectInputs,
    exitCodeOf,
    mkSession,
    parseArgs,
    renderHuman,
    renderJson,
 )

main :: IO ()
main = do
    argv <- getArgs
    options <- parseArgs argv
    txBytes <- readInput (txValidateCliInput options)
    tx <- decodeOrDie txBytes
    withSession options $ \session ->
        runValidation session tx options

runValidation :: Session -> ConwayTx -> TxValidateCliOptions -> IO ()
runValidation session tx options = do
    let txIns = collectInputs tx
    (resolved, _unresolved) <-
        resolveChain (sessionUtxoResolvers session) txIns
    let resolverTag = case sessionUtxoResolvers session of
            (r : _) -> resolverName r
            [] -> "unknown"
        utxoSources = Map.map (const resolverTag) resolved
        utxo = Map.toList resolved
        result =
            validatePhase1
                (sessionNetwork session)
                (mkPParamsBound (sessionPParams session))
                utxo
                (sessionSlot session)
                tx
        verdict = buildVerdict session utxoSources result
    case txValidateCliOutput options of
        Human ->
            TextIO.putStr (renderHuman verdict)
        Json ->
            LBS.hPutStr stdout (Aeson.Pretty.encodePretty (renderJson verdict))
                >> putStrLn ""
    exitWith (exitCodeOf verdict)

withSession :: TxValidateCliOptions -> (Session -> IO a) -> IO a
withSession options k = do
    let cfg = txValidateCliN2c options
        magic = NetworkMagic (n2cMagic cfg)
        network = networkFromMagic magic
    lsqCh <- newLSQChannel 64
    ltxsCh <- newLTxSChannel 64
    withAsync
        ( void $
            runNodeClient
                magic
                (n2cSocket cfg)
                lsqCh
                ltxsCh
        )
        $ \_ -> do
            let provider = mkN2CProvider lsqCh
            pp <- queryProtocolParams provider
            snap <- queryLedgerSnapshot provider
            let session =
                    mkSession
                        network
                        pp
                        (ledgerTipSlot snap)
                        [n2cResolver provider]
            k session

networkFromMagic :: NetworkMagic -> Network
networkFromMagic (NetworkMagic 764824073) = Mainnet
networkFromMagic _ = Testnet

readInput :: InputSource -> IO BS.ByteString
readInput InputStdin = BS.hGetContents stdin
readInput (InputFile path) = BS.readFile path

decodeOrDie :: BS.ByteString -> IO ConwayTx
decodeOrDie bytes =
    case decodeFullAnnotatorFromHexText
        (natVersion @11)
        "tx-validate input"
        (decCBOR :: forall s. Decoder s (Annotator ConwayTx))
        (Text.strip (Text.decodeUtf8 bytes)) of
        Right tx -> pure tx
        Left err -> do
            hPutStrLn stderr ("tx-validate: failed to decode input: " <> show err)
            exitWith (ExitFailure 3)

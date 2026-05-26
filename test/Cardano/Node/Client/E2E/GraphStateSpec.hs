{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.Node.Client.E2E.GraphStateSpec (spec) where

import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent (threadDelay)
import Data.ByteString.Char8 qualified as BS8
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Void (Void)
import Lens.Micro ((^.))
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec

import Cardano.Crypto.DSIGN (
    Ed25519DSIGN,
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
 )
import Cardano.Ledger.Address (
    Addr,
    serialiseAddr,
 )
import Cardano.Ledger.Api.Tx (
    bodyTxL,
    txIdTx,
 )
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    coinTxOutL,
 )
import Cardano.Ledger.BaseTypes (Inject (..), Network (Testnet))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Keys (
    KeyHash,
    KeyRole (Guard),
    VKey (..),
    hashKey,
 )
import Cardano.Ledger.TxIn (
    TxIn,
    mkTxInPartial,
 )
import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    enterpriseAddr,
    genesisAddr,
    genesisSignKey,
    keyHashFromSignKey,
    mkSignKey,
    withDevnet,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (
    SubmitResult (..),
    Submitter (..),
 )
import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    build,
    mkPParamsBound,
    payTo,
    requireSignature,
    spend,
 )
import Cardano.Tx.Graph.Emit (
    EmitFormat (Turtle),
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

spec :: Spec
spec =
    around withEnv $
        describe "tx-graph state recomputation (E2E)" $
            it "recomputes a submitted address state with SPARQL" recomputesState

type Env =
    ( Provider IO
    , Submitter IO
    , PParams ConwayEra
    , [(TxIn, TxOut ConwayEra)]
    )

withEnv :: (Env -> IO ()) -> IO ()
withEnv action =
    withDevnet $ \lsq ltxs -> do
        let provider = mkN2CProvider lsq
            submitter = mkN2CSubmitter ltxs
        pp <- queryProtocolParams provider
        utxos <- queryUTxOs provider genesisAddr
        action (provider, submitter, pp, utxos)

data NoQ a

recomputesState :: Env -> IO ()
recomputesState (provider, submitter, pp, genesisUtxos) = do
    sparql <- requireExecutable "sparql"
    seed@(seedIn, _) <- case genesisUtxos of
        u : _ -> pure u
        [] -> expectationFailure "no genesis UTxOs" >> fail "no genesis UTxOs"

    let targetKey = mkSignKey (BS8.pack (replicate 32 'g'))
        sinkKey = mkSignKey (BS8.pack (replicate 32 's'))
        targetAddr =
            enterpriseAddr (keyHashFromSignKey targetKey)
        sinkAddr =
            enterpriseAddr (keyHashFromSignKey sinkKey)
        targetBech32 = encodeBech32 Testnet targetAddr
        targetCoin = Coin 20_000_000
        sinkCoin = Coin 5_000_000

    tx1 <-
        buildOrFail
            pp
            [seed]
            genesisAddr
            ( do
                _ <- spend seedIn
                _ <- payTo targetAddr (inject targetCoin)
                requireSignature (witnessKeyHashFromSignKey genesisSignKey)
            )
    let signed1 = addKeyWitness genesisSignKey tx1
        tx1Outs = toList (tx1 ^. bodyTxL . outputsTxBodyL)
    targetOut1 <- case tx1Outs of
        out : _ -> do
            out ^. coinTxOutL `shouldBe` targetCoin
            pure out
        [] -> expectationFailure "tx1 has no outputs" >> fail "tx1 has no outputs"
    submitOrFail submitter signed1

    let targetIn1 = mkTxInPartial (txIdTx tx1) 0
        targetUtxo1 = (targetIn1, targetOut1)
    _ <- waitForUtxo provider targetAddr (fstEq targetIn1) 30

    tx2 <-
        buildOrFail
            pp
            [targetUtxo1]
            targetAddr
            ( do
                _ <- spend targetIn1
                _ <- payTo sinkAddr (inject sinkCoin)
                requireSignature (witnessKeyHashFromSignKey targetKey)
            )
    submitOrFail submitter (addKeyWitness targetKey tx2)

    terminalLive <-
        waitForSpentAndLive
            provider
            targetAddr
            targetIn1
            30
    let liveCount = length terminalLive
        liveLovelace = sumLovelace terminalLive

    withSystemTempDirectory "tx-graph-state-e2e" $ \dir -> do
        let tx1Ttl = dir </> "tx1.ttl"
            tx2Ttl = dir </> "tx2.ttl"
            query = dir </> "terminal-state.rq"
        BS8.writeFile tx1Ttl =<< emitTurtle "tx1" tx1 (Map.fromList [seed])
        BS8.writeFile tx2Ttl =<< emitTurtle "tx2" tx2 (Map.fromList [targetUtxo1])
        BS8.writeFile query (terminalStateQuery targetBech32)

        (exitCode, stdout, stderr) <-
            readProcessWithExitCode
                sparql
                [ "--results=CSV"
                , "--data"
                , tx1Ttl
                , "--data"
                , tx2Ttl
                , "--query"
                , query
                ]
                ""
        case exitCode of
            ExitSuccess ->
                parseTerminalCsv stdout
                    `shouldBe` (liveCount, liveLovelace)
            ExitFailure code ->
                expectationFailure $
                    "sparql exited "
                        <> show code
                        <> "\nstdout:\n"
                        <> stdout
                        <> "\nstderr:\n"
                        <> stderr

buildOrFail ::
    PParams ConwayEra ->
    [(TxIn, TxOut ConwayEra)] ->
    Addr ->
    TxBuild NoQ Void () ->
    IO ConwayTx
buildOrFail pp inputUtxos changeAddr prog =
    build
        (mkPParamsBound pp)
        (InterpretIO $ \case {})
        (\_ -> pure Map.empty)
        inputUtxos
        []
        changeAddr
        prog
        >>= \case
            Left err -> expectationFailure (show err) >> fail (show err)
            Right tx -> pure tx

submitOrFail :: Submitter IO -> ConwayTx -> IO ()
submitOrFail submitter tx =
    submitTx submitter tx >>= \case
        Submitted _ -> pure ()
        Rejected reason ->
            expectationFailure $
                "submitTx rejected: " <> show reason

emitTurtle ::
    FilePath ->
    ConwayTx ->
    Map.Map TxIn (TxOut ConwayEra) ->
    IO BS8.ByteString
emitTurtle slug tx resolved =
    case emit tx resolved [] [] of
        Left err ->
            expectationFailure (show err) >> fail (show err)
        Right graph ->
            pure (serialize Turtle slug graph)

terminalStateQuery :: Text -> BS8.ByteString
terminalStateQuery targetBech32 =
    BS8.pack $
        Text.unpack $
            Text.unlines
                [ "PREFIX cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#>"
                , ""
                , "SELECT (COUNT(?out) AS ?utxos) (SUM(?coin) AS ?lovelace)"
                , "WHERE {"
                , "  ?tx cardano:hasTxId/cardano:bytesHex ?txId ;"
                , "      cardano:hasOutput ?out ."
                , "  ?out cardano:hasIndex ?ix ;"
                , "       cardano:atAddress/cardano:bech32 "
                    <> quote targetBech32
                    <> " ;"
                , "       cardano:lovelace ?coin ."
                , "  FILTER NOT EXISTS {"
                , "    ?spendingTx cardano:hasInput ?input ."
                , "    ?input cardano:fromTxOutRef ?ref ."
                , "    ?ref cardano:hasTxId/cardano:bytesHex ?txId ;"
                , "         cardano:hasIndex ?ix ."
                , "  }"
                , "}"
                ]
  where
    quote t = "\"" <> t <> "\""

parseTerminalCsv :: String -> (Int, Integer)
parseTerminalCsv csv =
    case lines csv of
        [_header, row] ->
            case splitComma row of
                [countText, lovelaceText] ->
                    (read countText, read lovelaceText)
                fields ->
                    error $ "unexpected SPARQL CSV fields: " <> show fields
        rows ->
            error $ "unexpected SPARQL CSV rows: " <> show rows

splitComma :: String -> [String]
splitComma [] = [""]
splitComma (',' : xs) = "" : splitComma xs
splitComma (x : xs) =
    case splitComma xs of
        [] -> [[x]]
        y : ys -> (x : y) : ys

waitForUtxo ::
    Provider IO ->
    Addr ->
    ((TxIn, TxOut ConwayEra) -> Bool) ->
    Int ->
    IO (TxIn, TxOut ConwayEra)
waitForUtxo provider addr predicate attempts
    | attempts <= 0 =
        expectationFailure "timed out waiting for UTxO"
            >> fail "timed out waiting for UTxO"
    | otherwise = do
        utxos <- queryUTxOs provider addr
        case filter predicate utxos of
            u : _ -> pure u
            [] -> do
                threadDelay 1_000_000
                waitForUtxo provider addr predicate (attempts - 1)

waitForSpentAndLive ::
    Provider IO ->
    Addr ->
    TxIn ->
    Int ->
    IO [(TxIn, TxOut ConwayEra)]
waitForSpentAndLive provider addr spent attempts
    | attempts <= 0 =
        expectationFailure "timed out waiting for terminal UTxO state"
            >> fail "timed out waiting for terminal UTxO state"
    | otherwise = do
        utxos <- queryUTxOs provider addr
        if (not . any (fstEq spent)) utxos && not (null utxos)
            then pure utxos
            else do
                threadDelay 1_000_000
                waitForSpentAndLive provider addr spent (attempts - 1)

fstEq :: (Eq a) => a -> (a, b) -> Bool
fstEq x = (== x) . fst

sumLovelace :: [(TxIn, TxOut ConwayEra)] -> Integer
sumLovelace =
    foldr
        ( \(_, out) acc ->
            let Coin c = out ^. coinTxOutL
             in c + acc
        )
        0

encodeBech32 :: Network -> Addr -> Text
encodeBech32 network addr =
    case Bech32.humanReadablePartFromText hrp of
        Right h ->
            Bech32.encodeLenient
                h
                (Bech32.dataPartFromBytes (serialiseAddr addr))
        Left err ->
            error ("invalid bech32 HRP: " <> show err)
  where
    hrp = case network of
        Testnet -> "addr_test"
        _ -> "addr"

witnessKeyHashFromSignKey ::
    SignKeyDSIGN Ed25519DSIGN ->
    KeyHash Guard
witnessKeyHashFromSignKey =
    hashKey
        . VKey
        . deriveVerKeyDSIGN

requireExecutable :: String -> IO FilePath
requireExecutable name =
    findExecutable name >>= \case
        Just path -> pure path
        Nothing ->
            expectationFailure
                (name <> " executable not found on PATH")
                >> fail (name <> " executable not found on PATH")

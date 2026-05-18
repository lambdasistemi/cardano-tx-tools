{- |
Module      : Main
Description : tx-inspect executable entry point
License     : Apache-2.0

@tx-inspect@ prints a human-readable view of a single resolved Conway
transaction. The renderer reuses the shared substrate
'Cardano.Tx.Diff.renderConwayTxHuman' (which walks the same
@conwayDiffProjection@ that 'Cardano.Tx.Diff.renderDiffNodeHumanWith'
walks on one side of a diff), so any future @tx-diff@ rule that lands
in 'Cardano.Tx.Rewrite' is automatically available here too.

Slice S3 of @specs\/032-tx-inspect@ ships the full two-stage path: the
@--rules@ file is loaded if supplied; both the collapse rules
('rewriteCollapse') and the rename rules ('rewriteRename') are plumbed
into 'HumanRenderOptions' via 'Cardano.Tx.Rewrite.applyRewriteRules',
which stamps both fields in one pass. The render-time stage order
(collapse first; rename second) is hard-wired by the shared render
core in 'Cardano.Tx.Diff'. A @{}@ rules file is the fast path tested by
the live-boundary smoke ('scripts\/smoke\/tx-inspect').

@main@ is wrapped in 'GitHub.Release.Check.withCli' so every run prints
the latest-release banner to stderr on exit (suppressed by the
@TX_INSPECT_NO_UPDATE_CHECK@ env var). @--version@ short-circuits via
@github-release-check:optparse@'s 'versionOption'.
-}
module Main (main) where

import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Tx.Diff (
    HumanRenderOptions (..),
    RenderShape (..),
    RewriteRules,
    TreeArt (..),
    TxDiffOptions (..),
    decodeConwayTxInput,
    defaultHumanRenderOptions,
    defaultRewriteRules,
    defaultTxDiffOptions,
    renderConwayTxHuman,
 )
import Cardano.Tx.Diff.Resolver (
    Resolver,
    resolveChain,
 )
import Cardano.Tx.Diff.Resolver.N2C (n2cResolver)
import Cardano.Tx.Diff.Resolver.Web2 (
    Web2Config (..),
    httpFetchTx,
    web2Resolver,
 )
import Cardano.Tx.Rewrite (
    applyRewriteRules,
    parseRewriteRulesYaml,
 )
import GitHub.Release.Check (
    CliBanner (..),
    RepoSlug (..),
    withCli,
 )
import GitHub.Release.Check.OptParse (versionOption)
import Options.Applicative qualified as O
import Paths_cardano_tx_tools (version)

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Hashes (extractHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Tx.Ledger (ConwayTx)

import Cardano.Crypto.Hash (hashToBytes)
import Control.Concurrent.Async (withAsync)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.IO qualified as TextIO
import Data.Word (Word32)
import Lens.Micro ((^.))
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Ouroboros.Network.Magic (NetworkMagic (..))
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = withCli banner id $ do
    argv <- getArgs
    cliOptions <- parseArgs argv
    runInspect cliOptions

{- | Update-check banner bundle handed to
'GitHub.Release.Check.withCli' and to the optparse version-option
short-circuit. The opt-out env var is @TX_INSPECT_NO_UPDATE_CHECK@;
set it to any value to silence the banner.
-}
banner :: CliBanner
banner =
    CliBanner
        { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
        , cliExe = "tx-inspect"
        , cliVersion = version
        , cliOptOutEnvVar = "TX_INSPECT_NO_UPDATE_CHECK"
        }

{- | Parsed-out @tx-inspect@ CLI surface, lifted from
'Cardano.Tx.Diff.Cli' but specialised to one positional transaction
and stripped of the diff-only @--blueprint@ flag (out of scope for
S1 — added in a follow-up if blueprint decoding is requested for
inspect).
-}
data InspectCliOptions = InspectCliOptions
    { inspectCliRulesPath :: Maybe FilePath
    , inspectCliRenderOptions :: HumanRenderOptions
    , inspectCliN2cResolver :: Maybe InspectCliN2cConfig
    , inspectCliWeb2Resolver :: Maybe InspectCliWeb2Config
    , inspectCliTxPath :: FilePath
    }
    deriving stock (Eq, Show)

data InspectCliN2cConfig = InspectCliN2cConfig
    { inspectCliN2cSocket :: FilePath
    , inspectCliN2cNetworkMagic :: Word32
    }
    deriving stock (Eq, Show)

data InspectCliWeb2Config = InspectCliWeb2Config
    { inspectCliWeb2Url :: Text
    , inspectCliWeb2ApiKeyFile :: Maybe FilePath
    -- ^ Path to a file whose contents (after stripping surrounding
    -- whitespace) are sent as the @project_id@ header. When 'Nothing',
    -- the executable falls back to the @TX_INSPECT_WEB2_API_KEY@
    -- environment variable; if that is also unset the request is sent
    -- without a key.
    }
    deriving stock (Eq, Show)

parseArgs :: [String] -> IO InspectCliOptions
parseArgs argv
    | "--version" `elem` argv = do
        () <-
            O.handleParseResult $
                O.execParserPure
                    O.defaultPrefs
                    ( O.info
                        (pure () O.<**> versionOption banner)
                        (O.fullDesc <> O.progDesc inspectCliUsage)
                    )
                    ["--version"]
        -- 'versionOption' short-circuits with ExitSuccess; the
        -- success branch is unreachable, but we must satisfy the
        -- return type.
        exitFailure
    | "--help" `elem` argv || "-h" `elem` argv = do
        putStrLn inspectCliUsage
        exitSuccess
    | otherwise =
        case parseInspectCliArgs argv of
            Right opts -> pure opts
            Left err -> do
                hPutStrLn stderr ("tx-inspect: " <> err)
                hPutStrLn stderr inspectCliUsage
                exitFailure

parseInspectCliArgs :: [String] -> Either String InspectCliOptions
parseInspectCliArgs args = do
    (acc, positional) <- go emptyAccumulator args
    case positional of
        [txPath] ->
            buildOptions acc txPath
        [] ->
            Left "expected TX positional argument"
        _ ->
            Left $
                "expected exactly one TX positional argument; got "
                    <> show (length positional)
  where
    go acc ("--rules" : path : rest) =
        go acc{accRulesPath = Just path} rest
    go _ ["--rules"] =
        Left "missing value for --rules"
    go acc ("--render" : value : rest) = do
        renderShape <- parseRenderShape value
        let renderOptions = accRenderOptions acc
        go
            acc{accRenderOptions = renderOptions{humanRenderShape = renderShape}}
            rest
    go _ ["--render"] =
        Left "missing value for --render"
    go acc ("--tree-art" : value : rest) = do
        treeArt <- parseTreeArt value
        let renderOptions = accRenderOptions acc
        go acc{accRenderOptions = renderOptions{humanTreeArt = treeArt}} rest
    go _ ["--tree-art"] =
        Left "missing value for --tree-art"
    go acc ("--n2c-socket-path" : path : rest) =
        go acc{accN2cSocket = Just path} rest
    go _ ["--n2c-socket-path"] =
        Left "missing value for --n2c-socket-path"
    go acc ("--network-magic" : value : rest) =
        case reads value of
            [(magic, "")] ->
                go acc{accNetworkMagic = Just magic} rest
            _ ->
                Left
                    ( "expected a non-negative integer for --network-magic, got: "
                        <> value
                    )
    go _ ["--network-magic"] =
        Left "missing value for --network-magic"
    go acc ("--web2-url" : url : rest) =
        go acc{accWeb2Url = Just (Text.pack url)} rest
    go _ ["--web2-url"] =
        Left "missing value for --web2-url"
    go acc ("--web2-api-key-file" : path : rest) =
        go acc{accWeb2ApiKeyFile = Just path} rest
    go _ ["--web2-api-key-file"] =
        Left "missing value for --web2-api-key-file"
    go acc rest =
        Right (acc, rest)

    buildOptions acc txPath = do
        n2c <- buildN2c acc
        web2 <- buildWeb2 acc
        Right
            InspectCliOptions
                { inspectCliRulesPath = accRulesPath acc
                , inspectCliRenderOptions = accRenderOptions acc
                , inspectCliN2cResolver = n2c
                , inspectCliWeb2Resolver = web2
                , inspectCliTxPath = txPath
                }

    buildN2c acc =
        case (accN2cSocket acc, accNetworkMagic acc) of
            (Nothing, Nothing) -> Right Nothing
            (Just socket, Just magic) ->
                Right (Just (InspectCliN2cConfig socket magic))
            (Just _, Nothing) ->
                Left "--n2c-socket-path also requires --network-magic"
            (Nothing, Just _) ->
                Left "--network-magic also requires --n2c-socket-path"

    buildWeb2 acc =
        case (accWeb2Url acc, accWeb2ApiKeyFile acc) of
            (Nothing, Nothing) -> Right Nothing
            (Just url, keyFile) ->
                Right (Just (InspectCliWeb2Config url keyFile))
            (Nothing, Just _) ->
                Left "--web2-api-key-file requires --web2-url"

data Accumulator = Accumulator
    { accRulesPath :: Maybe FilePath
    , accRenderOptions :: HumanRenderOptions
    , accN2cSocket :: Maybe FilePath
    , accNetworkMagic :: Maybe Word32
    , accWeb2Url :: Maybe Text
    , accWeb2ApiKeyFile :: Maybe FilePath
    }

emptyAccumulator :: Accumulator
emptyAccumulator =
    Accumulator
        { accRulesPath = Nothing
        , accRenderOptions = defaultHumanRenderOptions
        , accN2cSocket = Nothing
        , accNetworkMagic = Nothing
        , accWeb2Url = Nothing
        , accWeb2ApiKeyFile = Nothing
        }

parseRenderShape :: String -> Either String RenderShape
parseRenderShape "tree" = Right RenderTree
parseRenderShape "paths" = Right RenderPaths
parseRenderShape value =
    Left ("unsupported --render value: " <> value)

parseTreeArt :: String -> Either String TreeArt
parseTreeArt "ascii" = Right TreeArtAscii
parseTreeArt "unicode" = Right TreeArtUnicode
parseTreeArt value =
    Left ("unsupported --tree-art value: " <> value)

inspectCliUsage :: String
inspectCliUsage =
    "Usage: tx-inspect"
        <> " [--render tree|paths] [--tree-art ascii|unicode]"
        <> " [--rules FILE]"
        <> " [--n2c-socket-path SOCKET --network-magic N]"
        <> " [--web2-url URL [--web2-api-key-file PATH]]"
        <> " TX"

runInspect :: InspectCliOptions -> IO ()
runInspect cliOptions = do
    rewriteRules <-
        case inspectCliRulesPath cliOptions of
            Nothing -> pure defaultRewriteRules
            Just path -> loadRewriteRules path
    txBytes <- BS.readFile (inspectCliTxPath cliOptions)
    tx <- decodeOrDie txBytes
    let baseHumanOptions =
            applyRewriteRules
                rewriteRules
                (inspectCliRenderOptions cliOptions)
        inputs = collectInputs tx
    resolutionResult <-
        if anyResolverConfigured cliOptions
            then do
                (resolved, unresolved) <-
                    withResolverChain cliOptions $ \chain ->
                        resolveChain chain inputs
                reportUnresolved unresolved
                pure (Just resolved)
            else pure Nothing
    let diffOptions =
            defaultTxDiffOptions
                { txDiffResolvedInputs = resolutionResult
                }
    TextIO.putStr (renderConwayTxHuman baseHumanOptions diffOptions tx)
    exitSuccess

loadRewriteRules :: FilePath -> IO RewriteRules
loadRewriteRules path = do
    input <- BS.readFile path
    case parseRewriteRulesYaml input of
        Left err -> do
            hPutStrLn
                stderr
                ( "tx-inspect: failed to decode rewriting rules "
                    <> path
                    <> ": "
                    <> err
                )
            exitFailure
        Right rules ->
            pure rules

decodeOrDie :: BS.ByteString -> IO ConwayTx
decodeOrDie bytes =
    case decodeConwayTxInput bytes of
        Right tx -> pure tx
        Left err -> do
            hPutStrLn stderr ("tx-inspect: failed to decode tx input: " <> show err)
            exitFailure

collectInputs :: ConwayTx -> Set TxIn
collectInputs tx =
    let body = tx ^. bodyTxL
     in (body ^. inputsTxBodyL)
            <> (body ^. referenceInputsTxBodyL)
            <> (body ^. collateralInputsTxBodyL)

anyResolverConfigured :: InspectCliOptions -> Bool
anyResolverConfigured cli =
    case (inspectCliN2cResolver cli, inspectCliWeb2Resolver cli) of
        (Nothing, Nothing) -> False
        _ -> True

{- | Build the resolver chain that matches the CLI flags. N2C wins,
the web2 resolver fills the remainder. The continuation owns the
resolver lifecycle: if N2C is configured the underlying
mini-protocol thread is spawned with 'withAsync' and torn down when
the continuation returns.
-}
withResolverChain ::
    InspectCliOptions ->
    ([Resolver] -> IO a) ->
    IO a
withResolverChain cli k = do
    web2 <- traverse buildWeb2Resolver (inspectCliWeb2Resolver cli)
    case inspectCliN2cResolver cli of
        Nothing ->
            k (maybe [] pure web2)
        Just n2c ->
            withN2cResolver n2c $ \n2cR ->
                k (n2cR : maybe [] pure web2)

buildWeb2Resolver :: InspectCliWeb2Config -> IO Resolver
buildWeb2Resolver cfg = do
    apiKey <- loadWeb2ApiKey (inspectCliWeb2ApiKeyFile cfg)
    manager <- newManager tlsManagerSettings
    pure $
        web2Resolver
            Web2Config
                { web2ResolverName = "web2"
                , web2Fetch =
                    httpFetchTx
                        manager
                        (inspectCliWeb2Url cfg)
                        apiKey
                }

{- | Resolve the Blockfrost-style @project_id@ key.

Precedence:

1. @--web2-api-key-file PATH@ wins; surrounding whitespace is stripped.
2. Otherwise the @TX_INSPECT_WEB2_API_KEY@ environment variable is
   consulted.
3. With neither set, the request goes out without a key, which works
   against self-hosted Blockfrost-compatible endpoints.
-}
loadWeb2ApiKey :: Maybe FilePath -> IO (Maybe Text)
loadWeb2ApiKey (Just path) =
    Just . Text.strip . Text.decodeUtf8 <$> BS.readFile path
loadWeb2ApiKey Nothing = do
    envKey <- lookupEnv "TX_INSPECT_WEB2_API_KEY"
    pure (fmap (Text.strip . Text.pack) envKey)

withN2cResolver :: InspectCliN2cConfig -> (Resolver -> IO a) -> IO a
withN2cResolver InspectCliN2cConfig{inspectCliN2cSocket, inspectCliN2cNetworkMagic} k = do
    lsqCh <- newLSQChannel 64
    ltxsCh <- newLTxSChannel 64
    withAsync
        ( void $
            runNodeClient
                (NetworkMagic inspectCliN2cNetworkMagic)
                inspectCliN2cSocket
                lsqCh
                ltxsCh
        )
        $ \_ -> k (n2cResolver (mkN2CProvider lsqCh))

reportUnresolved :: Map TxIn [Text] -> IO ()
reportUnresolved unresolved
    | Map.null unresolved = pure ()
    | otherwise =
        mapM_ emit (Map.toAscList unresolved)
  where
    emit (TxIn (TxId safeHash) (TxIx ix), names) =
        hPutStrLn stderr $
            "tx-inspect: input "
                <> Text.unpack (Text.decodeUtf8 (Base16.encode (hashToBytes (extractHash safeHash))))
                <> "#"
                <> show ix
                <> " not resolved by "
                <> showNames names

    showNames [] = "[]"
    showNames ns = "[" <> Text.unpack (Text.intercalate ", " ns) <> "]"

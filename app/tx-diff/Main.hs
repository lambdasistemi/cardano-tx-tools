{- |
Module      : Main
Description : tx-diff executable entry point
License     : Apache-2.0

Thin CLI wrapper over 'Cardano.Tx.Diff'. It reads two encoded
Conway transaction inputs, optionally resolves their referenced UTxOs via
local N2C or a Blockfrost-compatible web2 endpoint, prints the human
renderer output, and exits with a non-zero status when differences are
present.

The @--rules@ flag accepts the unified rewriting-rules YAML
documented in @specs\/032-tx-inspect\/contracts\/rules-yaml-grammar.md@.
Both @collapse:@ (existing) and @rename:@ (new in slice S4 of
@specs\/032-tx-inspect@) sections are honoured — the per-side
projection feeds the shared substrate, so any rename or collapse rule
that lands in @tx-inspect@ is automatically available here too. The
loader is forward-compatible with collapse-only YAML files (legacy
compat verified by @Cardano.Tx.Rewrite.LoadSpec@).

@main@ is wrapped in 'GitHub.Release.Check.withCli' so every run prints
the latest-release banner to stderr on exit (suppressed by the
@TX_DIFF_NO_UPDATE_CHECK@ env var); @--version@ short-circuits via
@github-release-check:optparse@'s 'versionOption', plumbed through
'Cardano.Tx.Diff.Cli.parseArgs'.
-}
module Main (main) where

import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Tx.Blueprint (
    Blueprint,
    blueprintDataDecoder,
    parseBlueprintJSON,
 )
import Cardano.Tx.Diff (
    RewriteRules,
    TxDiffOptions (..),
    decodeConwayTxInput,
    defaultRewriteRules,
    defaultTxDiffOptions,
    diffConwayTxWith,
    diffNodeHasChanges,
    parseRewriteRulesYaml,
    renderDiffNodeHumanWith,
 )
import Cardano.Tx.Diff.Cli (
    TxDiffCliN2cConfig (..),
    TxDiffCliOptions (..),
    TxDiffCliWeb2Config (..),
    parseArgs,
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
import Cardano.Tx.Rewrite (applyRewriteRules)
import GitHub.Release.Check (
    CliBanner (..),
    RepoSlug (..),
    withCli,
 )
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
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.IO qualified as TextIO
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
    cliOptions <- parseArgs banner argv
    runDiff cliOptions

{- | Update-check banner bundle handed to
'GitHub.Release.Check.withCli' and to
'Cardano.Tx.Diff.Cli.parseArgs'. The opt-out env var is
@TX_DIFF_NO_UPDATE_CHECK@; set it to any value to silence the
banner.
-}
banner :: CliBanner
banner =
    CliBanner
        { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
        , cliExe = "tx-diff"
        , cliVersion = version
        , cliOptOutEnvVar = "TX_DIFF_NO_UPDATE_CHECK"
        }

runDiff :: TxDiffCliOptions -> IO ()
runDiff cliOptions = do
    blueprints <- traverse loadBlueprint (txDiffCliBlueprintPaths cliOptions)
    rewriteRules <-
        maybe
            (pure defaultRewriteRules)
            loadRewriteRules
            (txDiffCliCollapseRulesPath cliOptions)
    leftBytes <- BS.readFile (txDiffCliLeftPath cliOptions)
    rightBytes <- BS.readFile (txDiffCliRightPath cliOptions)
    leftTx <- decodeOrDie "left" leftBytes
    rightTx <- decodeOrDie "right" rightBytes
    let inputs = collectInputs leftTx <> collectInputs rightTx
    resolutionResult <-
        if anyResolverConfigured cliOptions
            then do
                (resolved, unresolved) <-
                    withResolverChain cliOptions $ \chain ->
                        resolveChain chain inputs
                reportUnresolved unresolved
                pure (Just resolved)
            else pure Nothing
    let options =
            defaultTxDiffOptions
                { txDiffDecodeData =
                    case blueprints of
                        [] ->
                            Nothing
                        _ ->
                            Just (blueprintDataDecoder blueprints)
                , txDiffResolvedInputs = resolutionResult
                }
        diff = diffConwayTxWith options leftTx rightTx
    TextIO.putStr $
        renderDiffNodeHumanWith
            ( applyRewriteRules
                rewriteRules
                (txDiffCliHumanRenderOptions cliOptions)
            )
            diff
    if diffNodeHasChanges diff
        then exitFailure
        else exitSuccess

decodeOrDie :: String -> BS.ByteString -> IO ConwayTx
decodeOrDie side bytes =
    case decodeConwayTxInput bytes of
        Right tx -> pure tx
        Left err -> do
            hPutStrLn stderr ("tx-diff: failed to decode " <> side <> " input: " <> show err)
            exitFailure

collectInputs :: ConwayTx -> Set TxIn
collectInputs tx =
    let body = tx ^. bodyTxL
     in (body ^. inputsTxBodyL)
            <> (body ^. referenceInputsTxBodyL)
            <> (body ^. collateralInputsTxBodyL)

anyResolverConfigured :: TxDiffCliOptions -> Bool
anyResolverConfigured cli =
    case (txDiffCliN2cResolver cli, txDiffCliWeb2Resolver cli) of
        (Nothing, Nothing) -> False
        _ -> True

{- | Build the resolver chain that matches the CLI flags. The N2C resolver
is tried first (cheap, local, no privacy cost); the web2 resolver fills
the remainder.

The continuation owns the resolver lifecycle: if N2C is configured, the
underlying mini-protocol thread is spawned with 'withAsync' and torn down
when the continuation returns.
-}
withResolverChain ::
    TxDiffCliOptions ->
    ([Resolver] -> IO a) ->
    IO a
withResolverChain cli k = do
    web2 <- traverse buildWeb2Resolver (txDiffCliWeb2Resolver cli)
    case txDiffCliN2cResolver cli of
        Nothing ->
            k (maybe [] pure web2)
        Just n2c ->
            withN2cResolver n2c $ \n2cR ->
                k (n2cR : maybe [] pure web2)

buildWeb2Resolver :: TxDiffCliWeb2Config -> IO Resolver
buildWeb2Resolver cfg = do
    apiKey <- loadWeb2ApiKey (txDiffCliWeb2ApiKeyFile cfg)
    manager <- newManager tlsManagerSettings
    pure $
        web2Resolver
            Web2Config
                { web2ResolverName = "web2"
                , web2Fetch =
                    httpFetchTx
                        manager
                        (txDiffCliWeb2Url cfg)
                        apiKey
                }

{- | Resolve the Blockfrost-style @project_id@ key.

Precedence:

1. @--web2-api-key-file PATH@ wins; surrounding whitespace is stripped.
2. Otherwise the @TX_DIFF_WEB2_API_KEY@ environment variable is consulted.
3. With neither set, the request goes out without a key, which works
   against self-hosted Blockfrost-compatible endpoints.

This keeps the secret out of @ps@ output and shell history, matching the
existing repo conventions used by @cardano-tx-generator@.
-}
loadWeb2ApiKey :: Maybe FilePath -> IO (Maybe Text)
loadWeb2ApiKey (Just path) =
    Just . Text.strip . Text.decodeUtf8 <$> BS.readFile path
loadWeb2ApiKey Nothing = do
    envKey <- lookupEnv "TX_DIFF_WEB2_API_KEY"
    pure (fmap (Text.strip . Text.pack) envKey)

withN2cResolver :: TxDiffCliN2cConfig -> (Resolver -> IO a) -> IO a
withN2cResolver TxDiffCliN2cConfig{txDiffCliN2cSocket, txDiffCliN2cNetworkMagic} k = do
    lsqCh <- newLSQChannel 64
    ltxsCh <- newLTxSChannel 64
    withAsync
        ( void $
            runNodeClient
                (NetworkMagic txDiffCliN2cNetworkMagic)
                txDiffCliN2cSocket
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
            "tx-diff: input "
                <> Text.unpack (Text.decodeUtf8 (Base16.encode (hashToBytes (extractHash safeHash))))
                <> "#"
                <> show ix
                <> " not resolved by "
                <> showNames names

    showNames [] = "[]"
    showNames ns = "[" <> Text.unpack (Text.intercalate ", " ns) <> "]"

loadBlueprint :: FilePath -> IO Blueprint
loadBlueprint blueprintPath = do
    input <- LBS.readFile blueprintPath
    case parseBlueprintJSON input of
        Left err -> do
            hPutStrLn
                stderr
                ("tx-diff: failed to decode blueprint " <> blueprintPath <> ": " <> err)
            exitFailure
        Right blueprint ->
            pure blueprint

{- | Load the unified rewriting-rules YAML the @--rules@ flag points at.

The CLI flag name is preserved as @--rules@ for backwards compatibility
(see 'Cardano.Tx.Diff.Cli.txDiffCliCollapseRulesPath'). The loader is
the unified 'parseRewriteRulesYaml' — a legacy collapse-only YAML file
(no @rename:@ section) parses through to a 'RewriteRules' value whose
'rewriteRename' field is empty, which 'applyRewriteRules' then plumbs
into 'HumanRenderOptions' as a no-op rename layer; the rendered output
is byte-identical to the pre-S4 collapse-only behaviour. See
@specs\/032-tx-inspect\/contracts\/rules-yaml-grammar.md@ for the
grammar.
-}
loadRewriteRules :: FilePath -> IO RewriteRules
loadRewriteRules rewriteRulesPath = do
    input <- BS.readFile rewriteRulesPath
    case parseRewriteRulesYaml input of
        Left err -> do
            hPutStrLn
                stderr
                ( "tx-diff: failed to decode rewriting rules "
                    <> rewriteRulesPath
                    <> ": "
                    <> err
                )
            exitFailure
        Right rules ->
            pure rules

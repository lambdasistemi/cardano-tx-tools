{- |
Module      : Main
Description : tx-fetch executable — closure-walking Conway CBOR fetcher.
License     : Apache-2.0

@tx-fetch@ is the holy txid-list closure fetcher in the post-#114
three-tool pipeline:

* @tx-fetch@ — seed txids + chain source -> @[cbor]@ (network I/O)
* @tx-graph@ — rules + @[cbor]@ -> @[ttl]@ (pure transformation)
* @tx-view@  — @[ttl]@ + view name -> projection bytes (pure)

Given a list of seed transaction ids and a Blockfrost-compatible
chain source, the fetcher walks each seed's spending / reference /
collateral inputs over @\/txs\/\<hash\>\/cbor@, recursing to
@--depth@. Every fetched CBOR is parsed, its @TxId@ is recomputed
from @hashAnnotated . bodyTxL@, and the result is rejected if the
computed id does not match the requested id (the chain source lied
or the file is corrupt). Verified CBORs land at
@\<out-dir\>\/cbor\/\<txid-hex\>.cbor@; the operator's seed list
is preserved verbatim at @\<out-dir\>\/seeds.txt@ so downstream
SPARQL can distinguish seeds from BFS-walked parents.

Sequential, single-threaded, resumable: existing
@cbor\/\<txid\>.cbor@ files are skipped, so re-running over an
already-fetched lattice is a no-op (plus the seeds.txt rewrite).

CLI:

@
tx-fetch
  --out-dir DIR                                  (required)
  [--network mainnet|preprod|preview]            (default: mainnet)
  [--depth N]                                    (default: 1)
  \<txid\>...
@

Env:

* @BLOCKFROST_PROJECT_ID@ — required.

Exit codes:

* 0 — closure fetched successfully.
* 1 — fetch / decode / hash-mismatch error on at least one tx.
* >=2 — usage error.
-}
module Main (main) where

import Control.Monad (unless, when)
import Data.ByteString qualified as BS
import Data.Char (isHexDigit)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (sort)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Options.Applicative (
    Parser,
    ParserInfo,
    argument,
    auto,
    eitherReader,
    execParser,
    fullDesc,
    header,
    help,
    helper,
    info,
    long,
    metavar,
    option,
    progDesc,
    showDefault,
    some,
    strOption,
    value,
    (<**>),
 )
import System.Directory (createDirectoryIfMissing, doesFileExist, listDirectory)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.Hashes (extractHash, hashAnnotated)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.ByteString.Base16 qualified as Base16
import Lens.Micro ((^.))
import Network.HTTP.Client.TLS (newTlsManager)

import Cardano.Tx.Diff (decodeConwayTxInput)
import Cardano.Tx.Diff.Resolver.Web2 (
    Web2FetchError (..),
    Web2FetchTx,
    httpFetchTx,
 )
import Cardano.Tx.Ledger (ConwayTx)

----------------------------------------------------------------------
-- CLI
----------------------------------------------------------------------

data Network = Mainnet | Preprod | Preview
    deriving stock (Eq, Show)

data Options = Options
    { optOutDir :: !FilePath
    , optNetwork :: !Network
    , optDepth :: !Int
    , optSeeds :: ![Text]
    }

optionsParser :: Parser Options
optionsParser =
    Options
        <$> strOption
            ( long "out-dir"
                <> metavar "DIR"
                <> help
                    ( "Output directory. Writes <DIR>/cbor/<txid>"
                        <> ".cbor for every tx in the closure, plus"
                        <> " <DIR>/seeds.txt preserving the seed"
                        <> " list verbatim."
                    )
            )
        <*> option
            readNetwork
            ( long "network"
                <> metavar "NETWORK"
                <> value Mainnet
                <> showDefault
                <> help
                    ( "Cardano network the seed txids belong to:"
                        <> " mainnet | preprod | preview."
                    )
            )
        <*> option
            auto
            ( long "depth"
                <> metavar "N"
                <> value (1 :: Int)
                <> showDefault
                <> help
                    ( "BFS depth. 0 = fetch only the seeds; 1 = fetch"
                        <> " seeds + their direct input parents; 2 ="
                        <> " add the parents' parents; and so on."
                    )
            )
        <*> some
            ( argument
                readTxIdHex
                ( metavar "TXID..."
                    <> help "Seed transaction ids (lowercase hex)."
                )
            )
  where
    readNetwork = eitherReader $ \case
        "mainnet" -> Right Mainnet
        "preprod" -> Right Preprod
        "preview" -> Right Preview
        other -> Left ("unknown network: " <> other)
    readTxIdHex = eitherReader $ \raw ->
        let lower = Text.toLower (Text.pack raw)
         in if Text.length lower == 64 && Text.all isHexDigit lower
                then Right lower
                else Left ("expected 64-hex-char txid, got: " <> raw)

optionsInfo :: ParserInfo Options
optionsInfo =
    info
        (optionsParser <**> helper)
        ( fullDesc
            <> header "tx-fetch — Conway closure CBOR fetcher"
            <> progDesc
                ( "tx-fetch — closure-walking Conway CBOR fetcher."
                    <> " Resolves seed txids over Blockfrost's"
                    <> " /txs/<hash>/cbor endpoint, walks parent"
                    <> " references to --depth, and writes one"
                    <> " <DIR>/cbor/<txid>.cbor per tx plus"
                    <> " <DIR>/seeds.txt with the operator's seed"
                    <> " list. BLOCKFROST_PROJECT_ID env required."
                )
        )

networkBaseUrl :: Network -> Text
networkBaseUrl = \case
    Mainnet -> "https://cardano-mainnet.blockfrost.io/api/v0"
    Preprod -> "https://cardano-preprod.blockfrost.io/api/v0"
    Preview -> "https://cardano-preview.blockfrost.io/api/v0"

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

main :: IO ()
main = do
    opts <- execParser optionsInfo
    apiKey <- requireEnv "BLOCKFROST_PROJECT_ID"
    manager <- newTlsManager
    let baseUrl = networkBaseUrl (optNetwork opts)
        fetcher = httpFetchTx manager baseUrl (Just apiKey)
        cborDir = optOutDir opts </> "cbor"
    createDirectoryIfMissing True cborDir
    runBfs fetcher cborDir (optDepth opts) (optSeeds opts)
    BS.writeFile
        (optOutDir opts </> "seeds.txt")
        (TextEncoding.encodeUtf8 (Text.unlines (optSeeds opts)))
    fetched <- countCbors cborDir
    hPutStrLn stderr $
        "tx-fetch: done. "
            <> show fetched
            <> " cbor(s) in closure (depth="
            <> show (optDepth opts)
            <> ") → "
            <> cborDir
            <> "/"

requireEnv :: String -> IO Text
requireEnv name = do
    val <- lookupEnv name
    case val of
        Just v | not (null v) -> pure (Text.pack v)
        _ -> do
            hPutStrLn stderr ("tx-fetch: " <> name <> " env required")
            exitWith (ExitFailure 2)

countCbors :: FilePath -> IO Int
countCbors dir = do
    entries <- listDirectory dir
    pure (length [e | e <- entries, ".cbor" `Text.isSuffixOf` Text.pack e])

----------------------------------------------------------------------
-- BFS
----------------------------------------------------------------------

runBfs ::
    Web2FetchTx ->
    FilePath ->
    Int ->
    [Text] ->
    IO ()
runBfs fetcher cborDir maxDepth seeds = do
    seenRef <- newIORef Set.empty
    queueRef <- newIORef [(s, 0 :: Int) | s <- seeds]
    let loop = do
            queue <- readIORef queueRef
            case queue of
                [] -> pure ()
                (txidHex, depth) : rest -> do
                    writeIORef queueRef rest
                    seen <- readIORef seenRef
                    if Set.member txidHex seen
                        then loop
                        else do
                            modifyIORef' seenRef (Set.insert txidHex)
                            tx <- fetchAndStore fetcher cborDir txidHex
                            when (depth < maxDepth) $ do
                                let parents = sort (Set.toList (collectParentIds tx))
                                let novel =
                                        [(p, depth + 1) | p <- parents, not (Set.member p seen)]
                                modifyIORef' queueRef (++ novel)
                            loop
    loop

{- | Fetch one tx's CBOR (or read it from disk if already cached),
write it to @\<dir\>\/\<txid\>.cbor@, hash-verify, and return the
decoded transaction. Exits non-zero on fetch / decode / hash failure.
-}
fetchAndStore ::
    Web2FetchTx ->
    FilePath ->
    Text ->
    IO ConwayTx
fetchAndStore fetcher cborDir txidHex = do
    let path = cborDir </> (Text.unpack txidHex <> ".cbor")
    cached <- doesFileExist path
    bytes <-
        if cached
            then BS.readFile path
            else do
                hPutStrLn stderr ("tx-fetch: fetch " <> Text.unpack txidHex)
                fetched <- fetcher txidHex
                case fetched of
                    Left (Web2FetchHttpError msg) -> die ("HTTP: " <> Text.unpack msg)
                    Left (Web2FetchDecodeError msg) -> die ("decode: " <> Text.unpack msg)
                    Right raw -> do
                        BS.writeFile path raw
                        pure raw
    case decodeConwayTxInput bytes of
        Left err ->
            die
                ( "could not parse cached CBOR for "
                    <> Text.unpack txidHex
                    <> ": "
                    <> show err
                )
        Right tx -> do
            let computed = txIdHexOf tx
            unless (computed == txidHex) $
                die
                    ( "hash mismatch for "
                        <> Text.unpack txidHex
                        <> " (computed "
                        <> Text.unpack computed
                        <> ")"
                    )
            pure tx
  where
    die :: String -> IO a
    die msg = do
        hPutStrLn stderr ("tx-fetch: " <> msg)
        exitWith (ExitFailure 1)

{- | Compute a transaction's 'TxId' as lowercase hex by hashing its
annotated body, matching the @hashAnnotated body@ pattern used in
the body emitter and in the @tx-graph@ in-memory lattice (#100,
#114).
-}
txIdHexOf :: ConwayTx -> Text
txIdHexOf tx =
    let TxId safeHash = TxId (hashAnnotated (tx ^. bodyTxL))
     in TextEncoding.decodeUtf8 (Base16.encode (hashToBytes (extractHash safeHash)))

-- | Hex-encoded txids of every parent referenced by a tx body.
collectParentIds :: ConwayTx -> Set Text
collectParentIds tx =
    let body = tx ^. bodyTxL
        inputs =
            (body ^. inputsTxBodyL)
                <> (body ^. referenceInputsTxBodyL)
                <> (body ^. collateralInputsTxBodyL)
     in Set.fromList [txIdToHex t | TxIn t _ <- Set.toList inputs]

txIdToHex :: TxId -> Text
txIdToHex (TxId safeHash) =
    TextEncoding.decodeUtf8 (Base16.encode (hashToBytes (extractHash safeHash)))

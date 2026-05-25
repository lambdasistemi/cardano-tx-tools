{- |
Module      : Main
Description : tx-view executable — packaged-view dispatcher over canonical Turtle graphs.
License     : Apache-2.0

Companion executable to @tx-graph@ / @tx-diff@ / @tx-inspect@ /
@tx-sign@ / @tx-validate@. Loads a canonical Turtle graph file and
projects it through a named packaged view, writing the rendered byte
stream to stdout or to a file.

CLI surface (#51, locked by spec FR-002):

* @--graph FILE@ — canonical Turtle graph (the kind @tx-graph@ emits).
* @--view NAME@ — one of @cli-tree@; defaults to @cli-tree@.
* @--out FILE@ — output destination; defaults to stdout.

Exit codes:

* 0 — view rendered successfully (empty result counts as success per FR-008).
* 1 — structured 'Cardano.Tx.View.ViewError': unknown view name or
  malformed Turtle.
* \>=2 — @optparse-applicative@ usage error (missing @--graph@, etc.)
  or an OS-level failure reading the graph or writing the output.
-}
module Main (main) where

import Control.Exception (IOException, try)
import Data.ByteString qualified as BS
import Data.Text qualified as Text
import Options.Applicative (
    Parser,
    ParserInfo,
    execParser,
    fullDesc,
    header,
    help,
    helper,
    info,
    long,
    metavar,
    optional,
    progDesc,
    showDefault,
    strOption,
    value,
    (<**>),
 )
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.IO (hPutStrLn, stderr, stdout)

import Cardano.Tx.View (
    ViewError (..),
    parseViewName,
    renderView,
    renderViewError,
 )

----------------------------------------------------------------------
-- Options
----------------------------------------------------------------------

data Options = Options
    { optGraph :: !FilePath
    , optView :: !String
    , optOut :: !(Maybe FilePath)
    }

optionsParser :: Parser Options
optionsParser =
    Options
        <$> strOption
            ( long "graph"
                <> metavar "FILE"
                <> help "Canonical Turtle graph file (from tx-graph)."
            )
        <*> strOption
            ( long "view"
                <> metavar "NAME"
                <> value "cli-tree"
                <> showDefault
                <> help "Packaged view name (currently: cli-tree)."
            )
        <*> optional
            ( strOption
                ( long "out"
                    <> metavar "FILE"
                    <> help "Output destination (default: stdout)."
                )
            )

optionsInfo :: ParserInfo Options
optionsInfo =
    info
        (optionsParser <**> helper)
        ( fullDesc
            <> header
                ( "tx-view — packaged-view dispatcher over canonical "
                    <> "Turtle graphs"
                )
            <> progDesc
                ( "Loads a canonical Turtle graph file (the kind "
                    <> "tx-graph emits) and projects it through a "
                    <> "named packaged view, writing the rendered "
                    <> "byte stream to stdout or to --out FILE."
                )
        )

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

main :: IO ()
main = do
    opts <- execParser optionsInfo
    view <- case parseViewName (optView opts) of
        Right v -> pure v
        Left err -> exitOnViewError err
    bs <- readGraphOrExit (optGraph opts)
    case renderView view bs of
        Left err -> exitOnViewError err
        Right out -> writeOutput (optOut opts) out

----------------------------------------------------------------------
-- IO helpers
----------------------------------------------------------------------

readGraphOrExit :: FilePath -> IO BS.ByteString
readGraphOrExit path = do
    res <- try (BS.readFile path) :: IO (Either IOException BS.ByteString)
    case res of
        Right bs -> pure bs
        Left ioErr -> do
            hPutStrLn stderr $
                "tx-view: failed to read --graph file "
                    <> show path
                    <> ": "
                    <> show ioErr
            exitWith (ExitFailure 1)

writeOutput :: Maybe FilePath -> BS.ByteString -> IO ()
writeOutput mPath bs = case mPath of
    Nothing -> do
        BS.hPut stdout bs
        exitSuccess
    Just p -> do
        res <- try (BS.writeFile p bs) :: IO (Either IOException ())
        case res of
            Right () -> exitSuccess
            Left ioErr -> do
                hPutStrLn stderr $
                    "tx-view: failed to write --out file "
                        <> show p
                        <> ": "
                        <> show ioErr
                exitWith (ExitFailure 1)

exitOnViewError :: ViewError -> IO a
exitOnViewError err = do
    hPutStrLn stderr (Text.unpack (renderViewError err))
    exitWith (ExitFailure 1)

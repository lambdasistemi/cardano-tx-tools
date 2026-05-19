{- |
Module      : Main
Description : tx-graph executable — produces the operator-entity overlay.
License     : Apache-2.0

Companion executable to @tx-diff@ / @tx-inspect@ / @tx-sign@ /
@tx-validate@. Loads an operator-authored rules file (Turtle or
YAML sugar) via 'Cardano.Tx.Graph.Rules.Load.loadRulesFile' and
writes the canonical Turtle entity overlay to stdout.

This release surfaces only the @--rules \<file\>@ flag; the
body-emitter flags (@--utxo@, @--out@, @--tx@, @--format@) are
deferred to issue #58 (the body emitter wave). The executable does
not declare those flags, so passing them today produces an
@optparse-applicative@ usage error on stderr.

Exit codes:

* 0 — overlay emitted to stdout; any non-fatal warnings printed to
  stderr.
* 1 — structured 'Cardano.Tx.Graph.Rules.Load.RulesLoadError'
  printed to stderr.
* 2 — @optparse-applicative@ usage error (missing @--rules@,
  unknown flag).
-}
module Main (main) where

import Cardano.Tx.Graph.Rules.Load (
    RulesLoadResult (..),
    loadRulesFile,
    renderRulesLoadError,
    renderRulesLoadWarning,
 )

import Data.ByteString qualified as BS
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
    progDesc,
    strOption,
    (<**>),
 )
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.IO (hPutStrLn, stderr, stdout)

{- | Command-line options. The body-emitter flags are intentionally
absent — they land with issue #58.
-}
newtype Options = Options
    { optRulesFile :: FilePath
    -- ^ Path to the operator-authored rules file.
    }

{- | The single required @--rules \<file\>@ flag. Missing the flag
triggers @optparse-applicative@'s default usage error path
(stderr, exit 2).
-}
optionsParser :: Parser Options
optionsParser =
    Options
        <$> strOption
            ( long "rules"
                <> metavar "FILE"
                <> help
                    ( "Path to an operator-authored rules file "
                        <> "(.yaml/.yml or .ttl)."
                    )
            )

-- | The @optparse-applicative@ 'ParserInfo' for @tx-graph@.
optionsInfo :: ParserInfo Options
optionsInfo =
    info
        (optionsParser <**> helper)
        ( fullDesc
            <> header "tx-graph — operator-entity overlay producer"
            <> progDesc
                ( "Loads operator-authored rules and emits the "
                    <> "canonical Turtle entity overlay on stdout. "
                    <> "Body-emitter flags (--utxo, --out, --tx, "
                    <> "--format) are deferred to issue #58."
                )
        )

-- | Entry point.
main :: IO ()
main = do
    Options{optRulesFile} <- execParser optionsInfo
    result <- loadRulesFile optRulesFile
    case result of
        Right RulesLoadResult{rulesOverlayTurtle, rulesWarnings} -> do
            mapM_ (hPutStrLn stderr . renderRulesLoadWarning) rulesWarnings
            BS.hPut stdout rulesOverlayTurtle
            exitSuccess
        Left err -> do
            hPutStrLn stderr (renderRulesLoadError err)
            exitWith (ExitFailure 1)

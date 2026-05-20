{- |
Module      : Main
Description : tx-graph executable — operator-entity overlay + body-emitter dispatcher.
License     : Apache-2.0

Companion executable to @tx-diff@ / @tx-inspect@ / @tx-sign@ /
@tx-validate@. Loads an operator-authored rules file (Turtle or
YAML sugar) via 'Cardano.Tx.Graph.Rules.Load.loadRulesFile' and,
in T003 + onwards, drives the joint-graph body emitter from
'Cardano.Tx.Graph.Emit'.

The CLI surface follows plan slice D8 — flag-presence dispatch
on @(--rules, --tx, --utxo)@:

* @--rules \<file\>@ alone — /overlay-only/ mode (the existing
  #48 contract). Emits the canonical Turtle entity overlay to
  stdout.
* @--tx \<file\>@ with or without @--rules@ / @--utxo@ —
  /body-emitting/ modes (body-only, body-with-empty-utxo,
  body-only-with-utxo, joint). T003 wires the dispatcher; the
  Turtle serializer lands in T005. Until then, body-emitting
  modes short-circuit on the transitional
  'Cardano.Tx.Graph.Emit.NoSerializerYet' variant and write the
  rendered error to stderr.
* no input flags — @optparse-applicative@ usage error (stderr,
  exit 2).

@--format turtle|json-ld@ is parsed (default @turtle@) and
@--out \<path\>@ is parsed (default stdout); both are inert
in T003 because every body-emitting mode short-circuits before
either is consulted. T005 wires the Turtle serializer to the
overlay-merging code path; T011 wires JSON-LD.

Exit codes:

* 0 — overlay emitted to stdout; any non-fatal warnings printed
  to stderr.
* 1 — structured 'Cardano.Tx.Graph.Rules.Load.RulesLoadError'
  or 'Cardano.Tx.Graph.Emit.EmitError' printed to stderr.
* 2 — @optparse-applicative@ usage error.
-}
module Main (main) where

import Cardano.Tx.Graph.Emit (
    EmitError (..),
    EmitFormat (..),
    EmittedGraph (..),
    ResolvedUTxO,
    emit,
    renderEmitError,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl,
    RulesLoadResult (..),
    loadRulesFile,
    renderRulesLoadError,
    renderRulesLoadWarning,
    rulesEntities,
 )

import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Map.Strict qualified as Map
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
    strOption,
    value,
    (<**>),
 )
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.IO (hPutStrLn, stderr, stdout)
import System.IO.Error (catchIOError)

import Cardano.Ledger.Binary (decodeFullAnnotator)
import Cardano.Ledger.Binary.Decoding (decCBOR)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)

import Cardano.Tx.Ledger (ConwayTx)

{- | Command-line options. The body-emitter flags
(@--tx@ / @--utxo@ / @--out@ / @--format@) were introduced in
T003 alongside the dispatcher.
-}
data Options = Options
    { optRulesFile :: !(Maybe FilePath)
    -- ^ Operator-authored rules file (overlay producer).
    , optTxFile :: !(Maybe FilePath)
    -- ^ Conway tx CBOR (binary, untagged ledger encoding).
    , optUtxoFile :: !(Maybe FilePath)
    -- ^ Resolved-UTxO JSON.
    , optOutFile :: !(Maybe FilePath)
    -- ^ Output destination; 'Nothing' means stdout.
    , optFormat :: !String
    -- ^ Output format ('turtle' / 'json-ld'); validated at
    -- dispatch time so unknown values map to
    -- 'Cardano.Tx.Graph.Emit.UnknownFormat'.
    }

{- | Parser for 'Options'. All flags are optional at the parser
level; missing-input enforcement lives in 'dispatch'.
-}
optionsParser :: Parser Options
optionsParser =
    Options
        <$> optional
            ( strOption
                ( long "rules"
                    <> metavar "FILE"
                    <> help
                        ( "Operator-authored rules file (.yaml/"
                            <> ".yml or .ttl). Overlay-only mode "
                            <> "when used alone."
                        )
                )
            )
        <*> optional
            ( strOption
                ( long "tx"
                    <> metavar "FILE"
                    <> help
                        ( "Conway tx CBOR (binary). Triggers the "
                            <> "body-emitting dispatcher."
                        )
                )
            )
        <*> optional
            ( strOption
                ( long "utxo"
                    <> metavar "FILE"
                    <> help
                        ( "Resolved-UTxO JSON for the tx's inputs "
                            <> "(joint mode)."
                        )
                )
            )
        <*> optional
            ( strOption
                ( long "out"
                    <> metavar "FILE"
                    <> help "Output destination (default: stdout)."
                )
            )
        <*> strOption
            ( long "format"
                <> metavar "FORMAT"
                <> value "turtle"
                <> help
                    ( "Output format: 'turtle' (default) or "
                        <> "'json-ld'. T005 wires Turtle; T011 "
                        <> "wires JSON-LD."
                    )
            )

-- | The @optparse-applicative@ 'ParserInfo' for @tx-graph@.
optionsInfo :: ParserInfo Options
optionsInfo =
    info
        (optionsParser <**> helper)
        ( fullDesc
            <> header "tx-graph — operator-entity overlay + body emitter"
            <> progDesc
                ( "Loads operator-authored rules (overlay-only "
                    <> "mode) or drives the joint-graph body "
                    <> "emitter on a Conway tx + resolved UTxO. "
                    <> "Output format defaults to Turtle."
                )
        )

-- | Entry point.
main :: IO ()
main = do
    opts <- execParser optionsInfo
    dispatch opts

{- | Flag-presence dispatcher (plan D8). Three top-level modes:

* @(--rules, _, _)@ with @--tx@ absent — overlay-only (the
  existing #48 path).
* @--tx@ present (regardless of @--rules@ / @--utxo@) —
  body-emitting; routes through the real serializer (T005).
* neither @--rules@ nor @--tx@ — usage error.
-}
dispatch :: Options -> IO ()
dispatch
    Options
        { optRulesFile
        , optTxFile
        , optUtxoFile
        , optOutFile
        , optFormat
        } =
        case (optRulesFile, optTxFile) of
            (Just rulesPath, Nothing) ->
                overlayOnly rulesPath
            (_, Just txPath) ->
                bodyEmit
                    optRulesFile
                    txPath
                    optUtxoFile
                    optOutFile
                    optFormat
            (Nothing, Nothing) -> do
                hPutStrLn
                    stderr
                    ( "tx-graph: missing input — pass --rules and/or "
                        <> "--tx (see --help)."
                    )
                exitWith (ExitFailure 2)

{- | Overlay-only mode (existing #48 contract). Loads the rules
file and writes the canonical Turtle entity overlay to stdout.
-}
overlayOnly :: FilePath -> IO ()
overlayOnly rulesPath = do
    result <- loadRulesFile rulesPath
    case result of
        Right RulesLoadResult{rulesOverlayTurtle, rulesWarnings} -> do
            mapM_ (hPutStrLn stderr . renderRulesLoadWarning) rulesWarnings
            BS.hPut stdout rulesOverlayTurtle
            exitSuccess
        Left err -> do
            hPutStrLn stderr (renderRulesLoadError err)
            exitWith (ExitFailure 1)

{- | Body-emitting modes (plan D8 rows 2–5). Decodes the tx +
optional UTxO + optional rules file, validates the @--format@
argument, and calls 'Cardano.Tx.Graph.Emit.emit' followed by
'serialize' for the chosen 'EmitFormat'.

When @--rules@ is present, the overlay bytes from the loader are
threaded into the emitted graph's @graphOverlayTurtle@ field so
the serializer produces the joint Turtle output (overlay +
body). When @--rules@ is absent, the body emits without an
overlay section — body-only / body-with-utxo modes.

The fixture slug used in the @\@prefix :@ declaration defaults
to @\"tx\"@; the operator-facing surface will grow a @--slug@
flag in a later slice when the executable picks up multi-fixture
batch emission.
-}
bodyEmit ::
    Maybe FilePath ->
    FilePath ->
    Maybe FilePath ->
    Maybe FilePath ->
    String ->
    IO ()
bodyEmit mRules txPath mUtxo mOut fmt = do
    fmtChecked <- exitOnEmitError (parseFormat fmt)
    tx <- exitOnEmitError =<< loadTxCbor txPath
    utxo <- case mUtxo of
        Nothing -> pure (Map.empty :: ResolvedUTxO)
        Just p -> exitOnEmitError =<< loadUtxoJson p
    (entities, overlay) <- case mRules of
        Nothing -> pure ([], BS.empty)
        Just p -> loadOverlayAndEntitiesOrExit p
    g <- exitOnEmitError (emit tx utxo entities)
    let joint = g{graphOverlayTurtle = overlay}
        rendered = serialize fmtChecked defaultSlug joint
    writeOutput mOut rendered

{- | Slug used in the @\@prefix :@ declaration when the
executable's body emitter doesn't otherwise know the fixture
name. T005 hardcodes it; a later operator-surface slice can
promote it to a @--slug@ flag.
-}
defaultSlug :: FilePath
defaultSlug = "tx"

{- | Write the serialized graph to @--out@ if set; otherwise to
stdout.
-}
writeOutput :: Maybe FilePath -> BS.ByteString -> IO ()
writeOutput mOut bytes = case mOut of
    Nothing -> BS.hPut stdout bytes
    Just p -> BS.writeFile p bytes

{- | Parse the @--format@ argument to an 'EmitFormat'. Unknown
values surface as 'UnknownFormat' (T003 enforces the contract;
the underlying serializers land in T005 / T011).
-}
parseFormat :: String -> Either EmitError EmitFormat
parseFormat = \case
    "turtle" -> Right Turtle
    "json-ld" -> Right JsonLd
    other -> Left (UnknownFormat (Text.pack other))

{- | Load and decode a Conway tx CBOR file (binary, untagged
ledger encoding). On any IO or decode failure surfaces a
'MalformedTxCbor' value.
-}
loadTxCbor :: FilePath -> IO (Either EmitError ConwayTx)
loadTxCbor path = do
    bsOrErr <- tryReadFile path
    pure $ case bsOrErr of
        Left ioMsg ->
            Left (MalformedTxCbor path (Text.pack ioMsg))
        Right bs ->
            case decodeFullAnnotator
                (eraProtVerLow @ConwayEra)
                "ConwayTx"
                decCBOR
                (BSL.fromStrict bs) of
                Right tx ->
                    Right tx
                Left decErr ->
                    Left
                        ( MalformedTxCbor
                            path
                            (Text.pack (show decErr))
                        )

{- | Load and decode a resolved-UTxO JSON file. T003 ships a
syntax-only validator: the file must parse as JSON, but the
emitter still receives an empty 'ResolvedUTxO' because the
body-emitter dispatcher short-circuits on 'NoSerializerYet'
before the map is consulted. T005 (or the slice that wires the
real projection walker) replaces this with a structural decoder
against the 'TxIn' / 'TxOut' shape; the @--utxo@ contract is
unchanged from the operator's perspective.
-}
loadUtxoJson :: FilePath -> IO (Either EmitError ResolvedUTxO)
loadUtxoJson path = do
    bsOrErr <- tryReadFile path
    pure $ case bsOrErr of
        Left ioMsg ->
            Left (MalformedUtxoJson path (Text.pack ioMsg))
        Right bs ->
            case Aeson.eitherDecodeStrict bs :: Either String Aeson.Value of
                Right _ -> Right Map.empty
                Left parseErr ->
                    Left
                        ( MalformedUtxoJson
                            path
                            (Text.pack parseErr)
                        )

{- | Load the operator-entity list AND the overlay Turtle bytes
from a rules file. The overlay bytes are inlined verbatim into
the joint Turtle output by the serializer; the entity list
drives the credential lookup.

A rules load failure exits with the loader's structured renderer
(exit 1) so the operator sees the same diagnostic the
overlay-only mode would print.
-}
loadOverlayAndEntitiesOrExit ::
    FilePath -> IO ([EntityDecl], BS.ByteString)
loadOverlayAndEntitiesOrExit path = do
    result <- loadRulesFile path
    case result of
        Right res@RulesLoadResult{rulesOverlayTurtle, rulesWarnings} -> do
            mapM_ (hPutStrLn stderr . renderRulesLoadWarning) rulesWarnings
            pure (rulesEntities res, rulesOverlayTurtle)
        Left err -> do
            hPutStrLn stderr (renderRulesLoadError err)
            exitWith (ExitFailure 1)

{- | Either project an 'EmitError' to a stderr line + exit 1,
or pass through a successful value.
-}
exitOnEmitError :: Either EmitError a -> IO a
exitOnEmitError = \case
    Right a -> pure a
    Left e -> do
        hPutStrLn stderr (renderEmitError e)
        exitWith (ExitFailure 1)

{- | Read a file, mapping any 'IOError' to a 'Left' with the
exception's 'show' rendering — used to feed 'MalformedTxCbor'
/ 'MalformedUtxoJson' without leaking an 'IOError' to the
operator.
-}
tryReadFile :: FilePath -> IO (Either String BS.ByteString)
tryReadFile path =
    catchIOError
        (Right <$> BS.readFile path)
        (pure . Left . show)

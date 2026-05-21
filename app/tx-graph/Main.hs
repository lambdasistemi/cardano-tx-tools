{- |
Module      : Main
Description : tx-graph executable — operator-entity overlay + body-emitter dispatcher.
License     : Apache-2.0

Companion executable to @tx-diff@ / @tx-inspect@ / @tx-sign@ /
@tx-validate@. Renders an operator-authored rules overlay,
a Conway transaction body, or both, as a canonical Turtle (or
JSON-LD) graph.

The CLI surface tracks the rest of the suite:

* @--tx PATH | -@ — Conway tx CBOR. @-@ reads from stdin. The
  decoder is the same polymorphic @decodeConwayTxInput@ used by
  @tx-diff@ and @tx-inspect@: accepts hex text envelope JSON, raw
  hex text, or untagged binary CBOR.
* @--utxo FILE@ — pre-resolved UTxO JSON for the tx's inputs. The
  T003-shipped decoder is a syntax-only validator; the structural
  decoder is tracked separately.
* @--n2c-socket-path SOCKET --network-magic N@ — live UTxO
  resolution via a local @cardano-node@ Node-to-Client socket,
  exactly the seam @tx-inspect@ and @tx-validate@ use.
* @--rules FILE@ — operator-authored rules (Turtle or YAML sugar);
  drives the entity overlay.
* @--out FILE@ — output destination (default stdout).
* @--format turtle|json-ld@ — output format (default @turtle@).

Modes (flag-presence dispatch):

* @--rules@ alone — overlay-only.
* @--tx@ present — body-emitting; if @--rules@ is also present the
  overlay is merged in (joint mode); if @--utxo@ or
  @--n2c-socket-path@ is supplied the UTxO map is populated, else
  body-only with an empty UTxO.
* No input flags — @optparse-applicative@ usage error to stderr.

Exit codes:

* 0 — overlay or graph emitted successfully.
* 1 — structured 'Cardano.Tx.Graph.Rules.Load.RulesLoadError' or
  'Cardano.Tx.Graph.Emit.EmitError'.
* >=2 — @optparse-applicative@ usage error or invalid flag
  combination.
-}
module Main (main) where

import Cardano.Tx.Blueprint (Blueprint)
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

import Cardano.Ledger.Hashes (ScriptHash)
import Data.Text (Text)

import Control.Concurrent.Async (withAsync)
import Control.Monad (void)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Text qualified as Text
import Data.Word (Word32)
import Options.Applicative (
    Parser,
    ParserInfo,
    ParserResult (Failure),
    auto,
    defaultPrefs,
    eitherReader,
    execParser,
    fullDesc,
    handleParseResult,
    header,
    help,
    helper,
    info,
    long,
    metavar,
    option,
    optional,
    parserFailure,
    progDesc,
    showDefault,
    strOption,
    value,
    (<**>),
 )
import Options.Applicative.Types (ParseError (ErrorMsg))
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.IO (hPutStrLn, stderr, stdin, stdout)
import System.IO.Error (catchIOError)

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.TxIn (TxIn)
import Lens.Micro ((^.))
import Ouroboros.Network.Magic (NetworkMagic (..))

import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Tx.Diff (decodeConwayTxInput)
import Cardano.Tx.Diff.Resolver (Resolver, resolveChain)
import Cardano.Tx.Diff.Resolver.N2C (n2cResolver)
import Cardano.Tx.Ledger (ConwayTx)

{- | Mainnet network magic. Default for @--network-magic@ — matches
@tx-validate@.
-}
mainnetMagic :: Word32
mainnetMagic = 764824073

{- | Command-line options. @--n2c-socket-path@ + @--network-magic@
mirror the surface @tx-inspect@ and @tx-validate@ already expose.
-}
data Options = Options
    { optRulesFile :: !(Maybe FilePath)
    , optTxFile :: !(Maybe TxInputSource)
    , optUtxoFile :: !(Maybe FilePath)
    , optN2cSocket :: !(Maybe FilePath)
    , optNetworkMagic :: !Word32
    , optOutFile :: !(Maybe FilePath)
    , optFormat :: !String
    }

{- | Where to read the Conway tx CBOR from. @-@ on the command
line maps to 'TxFromStdin'.
-}
data TxInputSource
    = TxFromFile FilePath
    | TxFromStdin
    deriving stock (Eq, Show)

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
            ( option
                readTxInput
                ( long "tx"
                    <> metavar "PATH | -"
                    <> help
                        ( "Conway tx CBOR (hex text envelope, raw "
                            <> "hex, or binary). '-' reads from "
                            <> "stdin. Triggers the body-emitting "
                            <> "dispatcher."
                        )
                )
            )
        <*> optional
            ( strOption
                ( long "utxo"
                    <> metavar "FILE"
                    <> help
                        ( "Resolved-UTxO JSON for the tx's inputs. "
                            <> "Mutually exclusive with "
                            <> "--n2c-socket-path."
                        )
                )
            )
        <*> optional
            ( strOption
                ( long "n2c-socket-path"
                    <> metavar "SOCKET"
                    <> help
                        ( "Local cardano-node Node-to-Client "
                            <> "socket. When supplied, the tx's "
                            <> "inputs are resolved live against "
                            <> "the node (requires --network-"
                            <> "magic)."
                        )
                )
            )
        <*> option
            auto
            ( long "network-magic"
                <> metavar "WORD32"
                <> value mainnetMagic
                <> showDefault
                <> help
                    ( "Network magic for the --n2c-socket-path "
                        <> "session. Defaults to mainnet."
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
                <> showDefault
                <> help "Output format: 'turtle' or 'json-ld'."
            )
  where
    readTxInput =
        eitherReader $ \case
            "-" -> Right TxFromStdin
            path -> Right (TxFromFile path)

optionsInfo :: ParserInfo Options
optionsInfo =
    info
        (optionsParser <**> helper)
        ( fullDesc
            <> header "tx-graph — operator-entity overlay + body emitter"
            <> progDesc
                ( "tx-graph — operator-entity overlay + body "
                    <> "emitter. Loads operator-authored rules "
                    <> "(overlay-only mode) or drives the joint-"
                    <> "graph body emitter on a Conway tx + "
                    <> "resolved UTxO. Output format defaults to "
                    <> "Turtle."
                )
        )

main :: IO ()
main = do
    opts <- execParser optionsInfo
    dispatch opts

{- | Flag-presence dispatcher. See the module header for the full
mode table.
-}
dispatch :: Options -> IO ()
dispatch opts =
    case (optRulesFile opts, optTxFile opts) of
        (Just rulesPath, Nothing) ->
            overlayOnly rulesPath
        (_, Just txSource) ->
            bodyEmit opts txSource
        (Nothing, Nothing) ->
            handleParseResult
                ( Failure
                    ( parserFailure
                        defaultPrefs
                        optionsInfo
                        ( ErrorMsg
                            ( "missing input: pass --rules "
                                <> "and/or --tx (see --help)."
                            )
                        )
                        []
                    )
                )

{- | Overlay-only mode. Loads the rules file and writes the
canonical Turtle entity overlay to stdout.
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

{- | Body-emitting modes. Decodes the tx, populates the UTxO map
from @--utxo@ or the live N2C resolver, optionally merges the
overlay in, and writes the serialized graph.

@--utxo@ and @--n2c-socket-path@ are mutually exclusive: passing
both is a configuration error.
-}
bodyEmit :: Options -> TxInputSource -> IO ()
bodyEmit opts txSource = do
    fmtChecked <- exitOnEmitError (parseFormat (optFormat opts))
    tx <- loadTxOrExit txSource
    (entities, blueprints, overlay) <- case optRulesFile opts of
        Nothing -> pure ([], [], BS.empty)
        Just p -> loadOverlayAndEntitiesOrExit p
    utxo <- resolveUtxoOrExit opts tx
    g <- exitOnEmitError (emit tx utxo entities blueprints)
    let joint = g{graphOverlayTurtle = overlay}
        rendered = serialize fmtChecked defaultSlug joint
    writeOutput (optOutFile opts) rendered

{- | Slug used in the @\@prefix :@ declaration when the executable
doesn't know the fixture name. Operator-surface @--slug@ flag
deferred.
-}
defaultSlug :: FilePath
defaultSlug = "tx"

{- | Write the serialized graph to @--out@ if set, otherwise to
stdout.
-}
writeOutput :: Maybe FilePath -> BS.ByteString -> IO ()
writeOutput mOut bytes = case mOut of
    Nothing -> BS.hPut stdout bytes
    Just p -> BS.writeFile p bytes

parseFormat :: String -> Either EmitError EmitFormat
parseFormat = \case
    "turtle" -> Right Turtle
    "json-ld" -> Right JsonLd
    other -> Left (UnknownFormat (Text.pack other))

{- | Read the Conway tx CBOR from @--tx@ (file or stdin), decode
it polymorphically, and exit with 'MalformedTxCbor' on failure.
-}
loadTxOrExit :: TxInputSource -> IO ConwayTx
loadTxOrExit src = do
    let label = case src of
            TxFromStdin -> "<stdin>"
            TxFromFile p -> p
    bsOrErr <- case src of
        TxFromStdin ->
            (Right <$> BS.hGetContents stdin)
                `catchIOError` (pure . Left . show)
        TxFromFile p ->
            (Right <$> BS.readFile p)
                `catchIOError` (pure . Left . show)
    case bsOrErr of
        Left ioMsg ->
            exitOnEmitError
                (Left (MalformedTxCbor label (Text.pack ioMsg)))
        Right bs ->
            case decodeConwayTxInput bs of
                Right tx ->
                    pure tx
                Left decErr ->
                    exitOnEmitError
                        ( Left
                            ( MalformedTxCbor
                                label
                                (Text.pack (show decErr))
                            )
                        )

{- | Resolve the tx's inputs to a 'ResolvedUTxO' using whichever
source the operator configured. @--utxo@ and @--n2c-socket-path@
are mutually exclusive.
-}
resolveUtxoOrExit :: Options -> ConwayTx -> IO ResolvedUTxO
resolveUtxoOrExit opts tx =
    case (optUtxoFile opts, optN2cSocket opts) of
        (Just _, Just _) -> do
            hPutStrLn
                stderr
                ( "tx-graph: --utxo and --n2c-socket-path are "
                    <> "mutually exclusive."
                )
            exitWith (ExitFailure 2)
        (Just utxoPath, Nothing) ->
            loadUtxoJsonOrExit utxoPath
        (Nothing, Just socketPath) ->
            resolveViaN2c socketPath (optNetworkMagic opts) tx
        (Nothing, Nothing) ->
            pure Map.empty

{- | Load and decode a resolved-UTxO JSON file. The T003 decoder
is a syntax-only validator; the structural decoder is tracked
separately.
-}
loadUtxoJsonOrExit :: FilePath -> IO ResolvedUTxO
loadUtxoJsonOrExit path = do
    bsOrErr <-
        (Right <$> BS.readFile path)
            `catchIOError` (pure . Left . show)
    case bsOrErr of
        Left ioMsg ->
            exitOnEmitError
                (Left (MalformedUtxoJson path (Text.pack ioMsg)))
        Right bs ->
            case Aeson.eitherDecodeStrict bs :: Either String Aeson.Value of
                Right _ -> pure Map.empty
                Left parseErr ->
                    exitOnEmitError
                        ( Left
                            ( MalformedUtxoJson
                                path
                                (Text.pack parseErr)
                            )
                        )

{- | Spin up an N2C session against the supplied socket and
resolve the tx's input set via the standard chain resolver. The
session is torn down when this function returns.
-}
resolveViaN2c :: FilePath -> Word32 -> ConwayTx -> IO ResolvedUTxO
resolveViaN2c socket magic tx =
    withN2cResolver socket magic $ \r -> do
        (resolved, _unresolved) <- resolveChain [r] (collectInputs tx)
        pure resolved

{- | Collect every 'TxIn' the body references: spending inputs,
reference inputs, collateral inputs. Mirrors the same helper in
@tx-inspect@ and @tx-validate@.
-}
collectInputs :: ConwayTx -> Set TxIn
collectInputs tx =
    let body = tx ^. bodyTxL
     in (body ^. inputsTxBodyL)
            <> (body ^. referenceInputsTxBodyL)
            <> (body ^. collateralInputsTxBodyL)

{- | Bracket an N2C resolver around a continuation. Mirrors
@tx-inspect@'s helper: spawn the mini-protocol thread, give the
caller a single 'Resolver', and tear the thread down when the
continuation returns.
-}
withN2cResolver :: FilePath -> Word32 -> (Resolver -> IO a) -> IO a
withN2cResolver socket magic k = do
    lsqCh <- newLSQChannel 64
    ltxsCh <- newLTxSChannel 64
    withAsync
        ( void $
            runNodeClient
                (NetworkMagic magic)
                socket
                lsqCh
                ltxsCh
        )
        $ \_ -> k (n2cResolver (mkN2CProvider lsqCh))

{- | Load the operator-entity list, the blueprint index, AND the
overlay Turtle bytes from a rules file. The overlay bytes are
inlined into the joint Turtle output; the entity list drives the
credential lookup; the blueprint index (#50) drives typed
emission for per-output inline datums, datum witnesses, and
per-purpose redeemers.
-}
loadOverlayAndEntitiesOrExit ::
    FilePath ->
    IO ([EntityDecl], [(ScriptHash, Blueprint, Text)], BS.ByteString)
loadOverlayAndEntitiesOrExit path = do
    result <- loadRulesFile path
    case result of
        Right
            res@RulesLoadResult
                { rulesOverlayTurtle
                , rulesBlueprints
                , rulesWarnings
                } -> do
                mapM_ (hPutStrLn stderr . renderRulesLoadWarning) rulesWarnings
                pure
                    ( rulesEntities res
                    , rulesBlueprints
                    , rulesOverlayTurtle
                    )
        Left err -> do
            hPutStrLn stderr (renderRulesLoadError err)
            exitWith (ExitFailure 1)

{- | Either project an 'EmitError' to a stderr line + exit 1, or
pass through a successful value.
-}
exitOnEmitError :: Either EmitError a -> IO a
exitOnEmitError = \case
    Right a -> pure a
    Left e -> do
        hPutStrLn stderr (renderEmitError e)
        exitWith (ExitFailure 1)

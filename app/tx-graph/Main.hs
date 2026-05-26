{- |
Module      : Main
Description : tx-graph executable — pure (rules + [cbor]) → ttl transformation.
License     : Apache-2.0

Companion executable to @tx-diff@ / @tx-inspect@ / @tx-sign@ /
@tx-validate@. Renders an operator-authored rules overlay and/or
one Turtle (or JSON-LD) graph per Conway transaction CBOR.

CLI surface (see issue #114 — operator-led role audit collapse):

* @--rules FILE@ — operator overlay + blueprints + attestations.
  Used alone, emits overlay-only Turtle to stdout. Combined with
  inputs, merged into the joint graph(s).
* @--in-dir DIR@ — directory of @*.cbor@ files; each file is one
  Conway transaction in the input lattice.
* Positional @CBOR …@ — one or more Conway transaction CBOR files.
* @-@ in the positional slot — read a single Conway tx from stdin.
* @--out-dir DIR@ — write one @\<txid-hex\>.ttl@ per input. If
  exactly one input is given and @--out-dir@ is absent, the graph
  goes to stdout (back-compat with the pre-#114 single-tx invocation).
* @--format turtle|json-ld@ — output format (default @turtle@).

Inside, every input CBOR is parsed and indexed by its computed
@TxId@ (@hashAnnotated . bodyTxL@). The resolver looks each
spending / reference / collateral input up in that map; when an
input's parent CBOR isn't in the lattice the resolver returns
@Nothing@ and the emitter falls back to raw-bytes (the operator's
bug to fix by widening the lattice, not a silent default).

What this replaces (all dropped in #114):

* @--utxo@ — was a syntax-only stub; the lattice resolves itself.
* @--closure-dir@ — the closure IS the input set; no disk handshake.
* @--n2c-socket-path@ / @--network-magic@ — wrong workflow for
  tx-graph (queries the live UTxO; on-chain inputs are already
  spent there).

Exit codes:

* 0 — overlay or graph(s) emitted successfully.
* 1 — structured 'Cardano.Tx.Graph.Rules.Load.RulesLoadError' or
  'Cardano.Tx.Graph.Emit.EmitError'.
* >=2 — @optparse-applicative@ usage error or invalid flag
  combination (e.g. multiple inputs without @--out-dir@).
-}
module Main (main) where

import Cardano.Tx.Blueprint (Blueprint)
import Cardano.Tx.Graph.Emit (
    BnodeName (..),
    BodySection (..),
    EmitError (..),
    EmitFormat (..),
    EmittedGraph (..),
    Object (..),
    Predicate (..),
    ResolvedUTxO,
    Subject (..),
    SubjectBlock (..),
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

import Cardano.Ledger.Hashes (ScriptHash, extractHash, hashAnnotated)
import Data.Text (Text)

import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Text qualified as Text
import Options.Applicative (
    Parser,
    ParserInfo,
    ParserResult (Failure),
    argument,
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
    many,
    metavar,
    optional,
    parserFailure,
    progDesc,
    showDefault,
    strOption,
    value,
    (<**>),
 )
import Options.Applicative.Types (ParseError (ErrorMsg))
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.FilePath (takeExtension, (</>))
import System.IO (hPutStrLn, stderr, stdin, stdout)
import System.IO.Error (catchIOError)

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    outputsTxBodyL,
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.ByteString.Base16 qualified as Base16
import Data.Foldable (toList)
import Data.List (sort)
import Data.Set qualified as Set
import Data.Text.Encoding qualified as TextEncoding
import Lens.Micro ((^.))

import Cardano.Tx.Diff (decodeConwayTxInput)
import Cardano.Tx.Diff.Resolver (Resolver (..), resolveChain)
import Cardano.Tx.Ledger (ConwayTx)

{- | Command-line options. Post-#114 collapse: @--rules@ + one of
@--in-dir@ / positional / stdin + @--out-dir@ + @--format@.
-}
data Options = Options
    { optRulesFile :: !(Maybe FilePath)
    , optInDir :: !(Maybe FilePath)
    , optPositional :: ![InputSource]
    , optOutDir :: !(Maybe FilePath)
    , optFormat :: !String
    }

{- | Where to read one Conway tx CBOR from. @-@ on the positional
slot maps to 'TxFromStdin'; every other positional argument is a
file path.
-}
data InputSource
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
                            <> ".yml or .ttl). Used alone, emits "
                            <> "overlay-only Turtle to stdout. "
                            <> "Combined with inputs, merged into "
                            <> "the joint graph(s)."
                        )
                )
            )
        <*> optional
            ( strOption
                ( long "in-dir"
                    <> metavar "DIR"
                    <> help
                        ( "Directory of *.cbor files; each is one "
                            <> "Conway transaction in the input "
                            <> "lattice. Mutually exclusive with "
                            <> "positional arguments."
                        )
                )
            )
        <*> many
            ( argument
                readInputSource
                ( metavar "CBOR..."
                    <> help
                        ( "Conway tx CBOR file paths. '-' reads "
                            <> "one tx from stdin. Mutually "
                            <> "exclusive with --in-dir."
                        )
                )
            )
        <*> optional
            ( strOption
                ( long "out-dir"
                    <> metavar "DIR"
                    <> help
                        ( "Write one <txid-hex>.ttl per input "
                            <> "into DIR. If absent and exactly "
                            <> "one input is given, emits to "
                            <> "stdout."
                        )
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
    readInputSource =
        eitherReader $ \case
            "-" -> Right TxFromStdin
            path -> Right (TxFromFile path)

optionsInfo :: ParserInfo Options
optionsInfo =
    info
        (optionsParser <**> helper)
        ( fullDesc
            <> header "tx-graph — pure (rules + [cbor]) → ttl transformation"
            <> progDesc
                ( "tx-graph — operator-entity overlay + body "
                    <> "emitter. Loads operator-authored rules "
                    <> "(overlay-only mode) or drives the joint-"
                    <> "graph body emitter on a lattice of Conway "
                    <> "transactions (--in-dir / positional / "
                    <> "stdin). The lattice resolves itself "
                    <> "internally — no node, no UTxO file, no "
                    <> "external chain source. Output format "
                    <> "defaults to Turtle."
                )
        )

main :: IO ()
main = do
    opts <- execParser optionsInfo
    dispatch opts

{- | Dispatch on input presence. Overlay-only when @--rules@ is the
sole input flag; joint emit when at least one CBOR source is
present.
-}
dispatch :: Options -> IO ()
dispatch opts = do
    inputs <- collectAllInputs opts
    case (optRulesFile opts, inputs) of
        (Just rulesPath, []) ->
            overlayOnly rulesPath
        (_, []) ->
            usageError
                ( "missing input: pass --rules (overlay-only), "
                    <> "--in-dir DIR, or one or more positional "
                    <> "CBOR files (see --help)."
                )
        (_, sources) ->
            latticeEmit opts sources

{- | Resolve the input sources into the final ordered list of
'InputSource' values to process. Rejects the @--in-dir DIR@ +
positional combo; expands @--in-dir@ to its @*.cbor@ contents in
sorted order; pass-through for positional + stdin.
-}
collectAllInputs :: Options -> IO [InputSource]
collectAllInputs opts =
    case (optInDir opts, optPositional opts) of
        (Just _, _ : _) -> do
            usageError
                ( "--in-dir and positional CBOR arguments are "
                    <> "mutually exclusive."
                )
            pure []
        (Just dir, []) ->
            expandInDir dir
        (Nothing, ps) ->
            pure ps

{- | List the @*.cbor@ children of @dir@ in sorted order and wrap
each as a 'TxFromFile' input source.
-}
expandInDir :: FilePath -> IO [InputSource]
expandInDir dir = do
    isDir <- doesDirectoryExist dir
    if not isDir
        then do
            hPutStrLn
                stderr
                ( "tx-graph: --in-dir: not a directory: " <> dir
                )
            exitWith (ExitFailure 2)
        else do
            entries <- listDirectory dir
            let cbors = sort [e | e <- entries, takeExtension e == ".cbor"]
            pure [TxFromFile (dir </> e) | e <- cbors]

{- | Pretty usage error: print one line on stderr and let
@optparse-applicative@ render help with exit code 2.
-}
usageError :: String -> IO ()
usageError msg =
    handleParseResult
        ( Failure
            ( parserFailure
                defaultPrefs
                optionsInfo
                (ErrorMsg msg)
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

{- | Body-emitting mode for an N-tx lattice. Parses every input,
indexes them by computed 'TxId', and emits one Turtle (or JSON-LD)
graph per input. Single-input + no @--out-dir@ goes to stdout;
multi-input requires @--out-dir@.
-}
latticeEmit :: Options -> [InputSource] -> IO ()
latticeEmit opts sources = do
    fmtChecked <- exitOnEmitError (parseFormat (optFormat opts))
    (entities, blueprints, overlay) <- case optRulesFile opts of
        Nothing -> pure ([], [], BS.empty)
        Just p -> loadOverlayAndEntitiesOrExit p
    txs <- traverse loadOne sources
    let lattice = Map.fromList [(txIdOf tx, tx) | (_, tx) <- txs]
    case (optOutDir opts, txs) of
        (Nothing, [entry]) -> do
            bytes <- renderOne fmtChecked entities blueprints overlay lattice entry
            BS.hPut stdout bytes
        (Nothing, _) -> do
            usageError
                ( "multiple inputs ("
                    <> show (length txs)
                    <> ") require --out-dir DIR."
                )
        (Just dir, _) -> do
            createDirectoryIfMissing True dir
            mapM_ (emitToDir fmtChecked entities blueprints overlay lattice dir) txs

{- | Decode one input source into @(label, ConwayTx)@. The label
is the file path (or @\<stdin\>@) and is used in error messages
only — the tx itself is keyed by its computed 'TxId' downstream.
-}
loadOne :: InputSource -> IO (String, ConwayTx)
loadOne src = do
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
                    pure (label, tx)
                Left decErr ->
                    exitOnEmitError
                        ( Left
                            ( MalformedTxCbor
                                label
                                (Text.pack (show decErr))
                            )
                        )

{- | Compute the 'TxId' for a Conway transaction by hashing its
annotated body, matching the @hashAnnotated body@ pattern used in
the body emitter (#100).
-}
txIdOf :: ConwayTx -> TxId
txIdOf tx = TxId (hashAnnotated (tx ^. bodyTxL))

{- | Lowercase hex of a 'TxId', suitable for use as the stem of an
emitted @\<txid-hex\>.ttl@ file.
-}
txIdHex :: TxId -> String
txIdHex (TxId safeHash) =
    Text.unpack
        ( TextEncoding.decodeUtf8
            (Base16.encode (hashToBytes (extractHash safeHash)))
        )

{- | Resolve one tx against the in-memory lattice, emit it, and
serialise the result. Pure-ish wrapper around 'emit' + 'serialize'
that also forwards blueprint-decode warnings to stderr.
-}
renderOne ::
    EmitFormat ->
    [EntityDecl] ->
    [(ScriptHash, Blueprint, Text)] ->
    BS.ByteString ->
    Map TxId ConwayTx ->
    (String, ConwayTx) ->
    IO BS.ByteString
renderOne fmt entities blueprints overlay lattice (label, tx) = do
    utxo <- resolveAgainstLattice lattice tx
    warnOnMissingParents label tx lattice
    g <- exitOnEmitError (emit tx utxo entities blueprints)
    mapM_ (hPutStrLn stderr) (decodeErrorWarnings g)
    let joint = g{graphOverlayTurtle = overlay}
    pure (serialize fmt defaultSlug joint)

-- | Emit one tx into @\<out-dir\>/\<txid-hex\>.ttl@.
emitToDir ::
    EmitFormat ->
    [EntityDecl] ->
    [(ScriptHash, Blueprint, Text)] ->
    BS.ByteString ->
    Map TxId ConwayTx ->
    FilePath ->
    (String, ConwayTx) ->
    IO ()
emitToDir fmt entities blueprints overlay lattice dir entry@(_, tx) = do
    let hex = txIdHex (txIdOf tx)
        outPath = dir </> (hex <> ".ttl")
    bytes <- renderOne fmt entities blueprints overlay lattice entry
    BS.writeFile outPath bytes

{- | Warn on stderr for every spending / reference / collateral
input whose parent tx isn't in the lattice. Per the role-audit
contract (#114): a missing parent is the operator's bug, surfaced
loudly; the emitter still produces raw-bytes fallback so the
graph remains well-formed.
-}
warnOnMissingParents :: String -> ConwayTx -> Map TxId ConwayTx -> IO ()
warnOnMissingParents label tx lattice = do
    let inputs = collectInputs tx
        missing =
            [ ip
            | ip@(TxIn parentTxId _) <- Set.toList inputs
            , not (Map.member parentTxId lattice)
            ]
    mapM_
        ( \(TxIn t (TxIx ix)) ->
            hPutStrLn
                stderr
                ( "warning: tx-graph: "
                    <> label
                    <> ": parent tx not in lattice for input "
                    <> txIdHex t
                    <> "#"
                    <> show ix
                )
        )
        missing

defaultSlug :: FilePath
defaultSlug = "tx"

parseFormat :: String -> Either EmitError EmitFormat
parseFormat = \case
    "turtle" -> Right Turtle
    "json-ld" -> Right JsonLd
    other -> Left (UnknownFormat (Text.pack other))

{- | Resolve the tx's inputs against the in-memory lattice via the
standard 'Resolver' chain. Missing entries fall through as
unresolved (same semantics the on-disk closure resolver had in
#112, now without the disk roundtrip).
-}
resolveAgainstLattice :: Map TxId ConwayTx -> ConwayTx -> IO ResolvedUTxO
resolveAgainstLattice lattice tx = do
    let r = inMemoryResolver lattice
    (resolved, _unresolved) <- resolveChain [r] (collectInputs tx)
    pure resolved

{- | A 'Resolver' that looks each input up in the in-memory
lattice keyed by 'TxId'. Out-of-range output indices and missing
parents are dropped, matching the resolver-chain contract.
-}
inMemoryResolver :: Map TxId ConwayTx -> Resolver
inMemoryResolver lattice =
    Resolver
        { resolverName = "in-memory-lattice"
        , resolveInputs = \inputs ->
            pure $
                Map.fromList
                    [ (txIn, output)
                    | txIn <- Set.toList inputs
                    , Just output <- [resolveOne lattice txIn]
                    ]
        }

{- | Resolve a single 'TxIn' against the in-memory lattice. Returns
'Nothing' if the parent tx isn't indexed or the index is out of
range.
-}
resolveOne :: Map TxId ConwayTx -> TxIn -> Maybe (TxOut ConwayEra)
resolveOne lattice (TxIn parentTxId (TxIx ix)) = do
    parentTx <- Map.lookup parentTxId lattice
    let outs = toList (parentTx ^. bodyTxL . outputsTxBodyL)
    indexOutputs outs (fromIntegral ix)

indexOutputs :: [a] -> Int -> Maybe a
indexOutputs xs n
    | n < 0 = Nothing
    | otherwise = go xs n
  where
    go [] _ = Nothing
    go (x : _) 0 = Just x
    go (_ : rest) k = go rest (k - 1)

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

{- | Walk the emitted graph's body sections and project each
@cardano:decodeError@ literal triple onto a single-line stderr
warning of the form
@warning: blueprint decode failed for \<subject\>: \<error\>@.
-}
decodeErrorWarnings :: EmittedGraph -> [String]
decodeErrorWarnings g =
    [ "warning: blueprint decode failed for "
        <> renderSubject (subjectBlockSubject block)
        <> ": "
        <> Text.unpack msg
    | section <- graphBody g
    , block <- sectionBlocks section
    , (PIri predIri, OStringLit msg) <- subjectBlockPredicates block
    , predIri == "cardano:decodeError"
    ]

-- | Render a 'Subject' in its native Turtle surface form.
renderSubject :: Subject -> String
renderSubject = \case
    SBnode (BnodeName name) -> "_:" <> Text.unpack name
    SIri iri -> Text.unpack iri

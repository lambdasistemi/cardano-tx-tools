{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Tx.Validate.Cli
Description : CLI surface for the tx-validate executable.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

CLI surface for the @tx-validate@ executable that wraps
'Cardano.Tx.Validate.validatePhase1'. This module is
deliberately Node-to-Client-free: the N2C glue lives in
@app/tx-validate/Main.hs@ + the existing @n2c-resolver@
sublibrary (constitution I — one-way dependency on
@cardano-node-clients@).

The 'Session' value collects the protocol parameters, the tip
slot, and the resolver chain the executable's @Main@ entry
acquires from an N2C bracket. Pure consumers (and unit tests)
build a 'Session' directly via 'mkSession' without opening any
socket.

The Blockfrost-side surface originally part of this module's
design is deferred to upstream issue
<https://github.com/lambdasistemi/cardano-tx-tools/issues/21>.
-}
module Cardano.Tx.Validate.Cli (
    -- * Option ADT
    TxValidateCliOptions (..),
    InputSource (..),
    OutputFormat (..),
    N2cConfig (..),
    parseArgs,
    usage,

    -- * Session
    Session (..),
    mkSession,

    -- * Verdict
    Verdict (..),
    VerdictStatus (..),
    buildVerdict,
    collectInputs,
    exitCodeOf,
    renderHuman,
    renderJson,
) where

import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Aeson.Key
import Data.ByteString.Base16 qualified as Base16
import Data.Foldable (toList)
import Data.List (partition)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Word (Word32)
import Lens.Micro ((^.))
import Options.Applicative qualified as O
import System.Exit (ExitCode (..))

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.BaseTypes (Network, SlotNo, TxIx (..))
import Cardano.Ledger.Conway (ApplyTxError (..), ConwayEra)
import Cardano.Ledger.Conway.Rules (ConwayLedgerPredFailure (..))
import Cardano.Ledger.Core (bodyTxL)
import Cardano.Ledger.Hashes (extractHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.Diff.Resolver (Resolver)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Validate (isWitnessCompletenessFailure)

-- * Option ADT

-- | The fully-parsed option record produced by the CLI parser.
data TxValidateCliOptions = TxValidateCliOptions
    { txValidateCliInput :: InputSource
    , txValidateCliN2c :: N2cConfig
    , txValidateCliOutput :: OutputFormat
    }
    deriving stock (Eq, Show)

-- | Where to read the candidate Conway transaction CBOR hex from.
data InputSource
    = InputFile FilePath
    | InputStdin
    deriving stock (Eq, Show)

-- | Verdict rendering target.
data OutputFormat
    = Human
    | Json
    deriving stock (Eq, Show)

-- | Node-to-Client (N2C) session configuration.
data N2cConfig = N2cConfig
    { n2cSocket :: FilePath
    , n2cMagic :: Word32
    }
    deriving stock (Eq, Show)

-- | Mainnet network magic. Default for @--network-magic@.
mainnetMagic :: Word32
mainnetMagic = 764824073

{- | Parse the raw @argv@ tail into 'TxValidateCliOptions'. Returns
the parsed options on success or hands off to @optparse-applicative@'s
default failure-rendering path on user error (missing flag, bad
value, @--help@).
-}
parseArgs :: [String] -> IO TxValidateCliOptions
parseArgs argv =
    O.handleParseResult $
        O.execParserPure
            O.defaultPrefs
            ( O.info
                (optionsParser O.<**> O.helper)
                (O.fullDesc <> O.progDesc usage)
            )
            argv

-- | Short usage description shown by @--help@.
usage :: String
usage =
    "tx-validate: Conway Phase-1 pre-flight against a local cardano-node "
        <> "(see <https://github.com/lambdasistemi/cardano-tx-tools>)"

optionsParser :: O.Parser TxValidateCliOptions
optionsParser =
    TxValidateCliOptions
        <$> inputParser
        <*> n2cParser
        <*> outputParser

inputParser :: O.Parser InputSource
inputParser =
    O.option
        readInput
        ( O.long "input"
            <> O.metavar "PATH | -"
            <> O.help "Conway tx CBOR hex file, or '-' for stdin"
        )
  where
    readInput =
        O.eitherReader $ \case
            "-" -> Right InputStdin
            path -> Right (InputFile path)

n2cParser :: O.Parser N2cConfig
n2cParser =
    N2cConfig
        <$> O.strOption
            ( O.long "n2c-socket"
                <> O.metavar "PATH"
                <> O.help "Local cardano-node Node-to-Client socket"
            )
        <*> O.option
            O.auto
            ( O.long "network-magic"
                <> O.metavar "WORD32"
                <> O.value mainnetMagic
                <> O.showDefault
                <> O.help "Network magic for the supplied socket"
            )

outputParser :: O.Parser OutputFormat
outputParser =
    O.option
        readOutput
        ( O.long "output"
            <> O.metavar "human|json"
            <> O.value Human
            <> O.showDefaultWith showOutput
            <> O.help "Verdict format"
        )
  where
    readOutput =
        O.eitherReader $ \case
            "human" -> Right Human
            "json" -> Right Json
            other -> Left ("unknown --output value: " <> other)
    showOutput Human = "human"
    showOutput Json = "json"

-- * Session

{- | Resolved session state for one tx-validate invocation. The
@Main@ entry's N2C bracket acquires the 'PParams' + tip slot
from a live @cardano-node@ and pairs them with the
'n2cResolver'-wrapped UTxO chain to build this record. Pure
consumers (and unit tests) construct a 'Session' directly via
'mkSession'.
-}
data Session = Session
    { sessionNetwork :: Network
    , sessionPParams :: PParams ConwayEra
    , sessionSlot :: SlotNo
    , sessionUtxoResolvers :: [Resolver]
    }

{- | Build a 'Session' from already-acquired primary-session
data and the resolver chain. Pure.
-}
mkSession ::
    Network ->
    PParams ConwayEra ->
    SlotNo ->
    [Resolver] ->
    Session
mkSession network pp slot resolvers =
    Session
        { sessionNetwork = network
        , sessionPParams = pp
        , sessionSlot = slot
        , sessionUtxoResolvers = resolvers
        }

-- * Verdict

{- | Coarse verdict status, mapped to a process exit code by
'exitCodeOf'.
-}
data VerdictStatus
    = StructurallyClean
    | StructuralFailure
    | MempoolShortCircuit
    deriving stock (Eq, Show)

{- | The typed verdict the executable builds before rendering.
'renderHuman' and (in T004) 'renderJson' consume the same value.
-}
data Verdict = Verdict
    { verdictStatus :: VerdictStatus
    , verdictStructuralFailures :: [ConwayLedgerPredFailure ConwayEra]
    , verdictWitnessNoiseCount :: Int
    , verdictPParamsSource :: Text
    , verdictSlotSource :: Text
    , verdictUtxoSources :: Map TxIn Text
    }

{- | Collect every 'TxIn' the body references: spending inputs,
reference inputs, collateral inputs.
-}
collectInputs :: ConwayTx -> Set TxIn
collectInputs tx =
    let body = tx ^. bodyTxL
     in (body ^. inputsTxBodyL)
            <> (body ^. referenceInputsTxBodyL)
            <> (body ^. collateralInputsTxBodyL)

{- | Build a 'Verdict' from the typed session data + the
ledger's response. Pure. The caller is responsible for:

* running 'validatePhase1' on @session@'s pparams + utxo + slot
  + the supplied tx, and
* tagging each resolved 'TxIn' with the name of the resolver
  that produced it (the @utxoSources@ argument).

Witness-completeness failures are filtered out via
'isWitnessCompletenessFailure'; what remains is the
@verdictStructuralFailures@ list.
-}
buildVerdict ::
    Session ->
    Map TxIn Text ->
    Either (ApplyTxError ConwayEra) () ->
    Verdict
buildVerdict _session utxoSources result =
    let allFailures = case result of
            Right () -> []
            Left (ConwayApplyTxError errs) -> toList errs
        (noise, structural) =
            partition isWitnessCompletenessFailure allFailures
        status
            | any isMempoolFailure structural = MempoolShortCircuit
            | null structural = StructurallyClean
            | otherwise = StructuralFailure
     in Verdict
            { verdictStatus = status
            , verdictStructuralFailures = structural
            , verdictWitnessNoiseCount = length noise
            , verdictPParamsSource = "n2c"
            , verdictSlotSource = "n2c"
            , verdictUtxoSources = utxoSources
            }
  where
    -- We surface the mempool short-circuit as its own status so
    -- the human / JSON renderers can flag a stale UTxO snapshot
    -- distinctly from genuine structural failures. The exit code
    -- is the same as a structural failure (per contract).
    isMempoolFailure (ConwayMempoolFailure _) = True
    isMempoolFailure _ = False

{- | Map 'Verdict' onto the process exit code per
@contracts/cli.md@.
-}
exitCodeOf :: Verdict -> ExitCode
exitCodeOf v = case verdictStatus v of
    StructurallyClean -> ExitSuccess
    StructuralFailure -> ExitFailure 1
    MempoolShortCircuit -> ExitFailure 1

{- | Render the verdict in the human format locked by
@contracts/cli.md "Standard output"@.
-}
renderHuman :: Verdict -> Text
renderHuman v =
    Text.unlines (verdictLine : failureLines)
  where
    verdictLine = case verdictStatus v of
        StructurallyClean ->
            "structurally clean: "
                <> tshow (verdictWitnessNoiseCount v)
                <> " witness-completeness failures filtered"
        StructuralFailure ->
            "structural failure: "
                <> tshow (length (verdictStructuralFailures v))
                <> " structural; "
                <> tshow (verdictWitnessNoiseCount v)
                <> " witness-completeness filtered"
        MempoolShortCircuit ->
            "mempool short-circuit: 0 of "
                <> tshow (Map.size (verdictUtxoSources v))
                <> " inputs resolved; treat as structural"
    failureLines =
        map renderFailure (verdictStructuralFailures v)

renderFailure :: ConwayLedgerPredFailure ConwayEra -> Text
renderFailure failure =
    "  "
        <> ruleName failure
        <> "."
        <> constructorName failure
        <> ": "
        <> renderDetail failure

ruleName :: ConwayLedgerPredFailure ConwayEra -> Text
ruleName = \case
    ConwayUtxowFailure _ -> "UTXOW"
    ConwayCertsFailure _ -> "CERTS"
    ConwayGovFailure _ -> "GOV"
    ConwayWdrlNotDelegatedToDRep _ -> "LEDGER.withdrawals"
    ConwayTreasuryValueMismatch _ -> "LEDGER.treasury"
    ConwayTxRefScriptsSizeTooBig _ -> "LEDGER.reference_scripts"
    ConwayMempoolFailure _ -> "MEMPOOL"
    ConwayWithdrawalsMissingAccounts _ -> "LEDGER.withdrawals"
    ConwayIncompleteWithdrawals _ -> "LEDGER.withdrawals"

constructorName :: ConwayLedgerPredFailure ConwayEra -> Text
constructorName failure =
    let s = Text.pack (show failure)
     in case Text.takeWhile (/= ' ') (dropPrefixes s) of
            "" -> "Failure"
            n -> n
  where
    dropPrefixes t =
        fromMaybe t (Text.stripPrefix "Conway" t)

{- | First line of the failure's @show@ output, used as a
one-line summary in human and JSON renderers. Subject to
ledger-version drift; not part of the contract.
-}
renderDetail :: ConwayLedgerPredFailure ConwayEra -> Text
renderDetail failure =
    Text.takeWhile (/= '\n') (Text.pack (show failure))

tshow :: (Show a) => a -> Text
tshow = Text.pack . show

{- | Render the verdict as the JSON envelope locked in
@contracts/json-output.md@.
-}
renderJson :: Verdict -> Aeson.Value
renderJson v =
    Aeson.object
        [ "status" .= statusText (verdictStatus v)
        , "exit_code" .= exitCodeInt (exitCodeOf v)
        , "structural_failures"
            .= map renderFailureJson (verdictStructuralFailures v)
        , "witness_completeness_count"
            .= verdictWitnessNoiseCount v
        , "pparams_source" .= verdictPParamsSource v
        , "slot_source" .= verdictSlotSource v
        , "utxo_sources"
            .= Aeson.object
                [ Aeson.Key.fromText (renderTxIn txIn) .= src
                | (txIn, src) <- Map.toAscList (verdictUtxoSources v)
                ]
        ]

statusText :: VerdictStatus -> Text
statusText StructurallyClean = "structurally_clean"
statusText StructuralFailure = "structural_failure"
statusText MempoolShortCircuit = "mempool_short_circuit"

exitCodeInt :: ExitCode -> Int
exitCodeInt ExitSuccess = 0
exitCodeInt (ExitFailure n) = n

renderFailureJson :: ConwayLedgerPredFailure ConwayEra -> Aeson.Value
renderFailureJson failure =
    Aeson.object
        [ "rule" .= ruleName failure
        , "constructor" .= constructorName failure
        , "detail" .= renderDetail failure
        ]

renderTxIn :: TxIn -> Text
renderTxIn (TxIn (TxId safeHash) (TxIx ix)) =
    Text.decodeUtf8 (Base16.encode (hashToBytes (extractHash safeHash)))
        <> "#"
        <> tshow ix

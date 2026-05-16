{- |
Module      : Cardano.Tx.Validate.CliSpec
Description : Coverage for tx-validate's driver (parser + verdict).
License     : Apache-2.0
-}
module Cardano.Tx.Validate.CliSpec (
    spec,
) where

import Control.Exception (ErrorCall (..), throwIO)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.TxBody (
    ScriptIntegrityHash,
    scriptIntegrityHashTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Body (vldtTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet),
    SlotNo (..),
    StrictMaybe (..),
    TxIx (..),
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Rules (ConwayLedgerPredFailure)
import Cardano.Ledger.Core (bodyTxL)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Provider (Provider (..))
import System.Exit (ExitCode (..))

import Cardano.Tx.Build (mkPParamsBound)
import Cardano.Tx.BuildSpec (loadBody, loadPParams)
import Cardano.Tx.Diff.Resolver (Resolver (..), resolveChain)
import Cardano.Tx.Diff.Resolver.N2C (n2cResolver)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Validate (validatePhase1)
import Cardano.Tx.Validate.Cli (
    InputSource (..),
    N2cConfig (..),
    OutputFormat (..),
    Session (..),
    TxValidateCliOptions (..),
    Verdict (..),
    VerdictStatus (..),
    buildVerdict,
    collectInputs,
    exitCodeOf,
    mkSession,
    parseArgs,
    renderHuman,
    renderJson,
 )

import Cardano.Tx.Validate.LoadUtxo (loadUtxo)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Aeson
import Data.Aeson.KeyMap qualified as Aeson.KeyMap

spec :: Spec
spec = describe "Cardano.Tx.Validate.Cli" $ do
    describe "mkSession" $ do
        it "packages caller-supplied PParams + slot + resolvers" $ do
            pp <- loadPParams ppPath
            utxos <- loadUtxo producerTxDir issue8TxIns
            let provider = stubProvider utxos
                resolvers = [n2cResolver provider]
                slot = SlotNo 187382499
                session = mkSession Mainnet pp slot resolvers
            sessionNetwork session `shouldBe` Mainnet
            sessionPParams session `shouldBe` pp
            sessionSlot session `shouldBe` slot
            map resolverName (sessionUtxoResolvers session) `shouldBe` ["n2c"]
            (resolved, _) <-
                resolveChain
                    (sessionUtxoResolvers session)
                    (Set.fromList issue8TxIns)
            Map.keysSet resolved `shouldBe` Set.fromList issue8TxIns

    describe "parseArgs" $ do
        it "accepts the happy-path argv" $ do
            options <-
                parseArgs
                    [ "--input"
                    , "tx.cbor.hex"
                    , "--n2c-socket"
                    , "/tmp/node.socket"
                    ]
            txValidateCliInput options
                `shouldBe` InputFile "tx.cbor.hex"
            txValidateCliN2c options
                `shouldBe` N2cConfig
                    { n2cSocket = "/tmp/node.socket"
                    , n2cMagic = 764824073
                    }
            txValidateCliOutput options `shouldBe` Human

        it "accepts --input - for stdin" $ do
            options <-
                parseArgs
                    [ "--input"
                    , "-"
                    , "--n2c-socket"
                    , "/tmp/node.socket"
                    ]
            txValidateCliInput options `shouldBe` InputStdin

    describe "end-to-end validation" $ do
        it
            ( "post-fix issue-#8 body validates structurally clean "
                <> "(verdict + exit code + human render)"
            )
            $ do
                pp <- loadPParams ppPath
                buggy <- loadBody bodyPath
                utxos <- loadUtxo producerTxDir issue8TxIns
                let tx = postFix buggy
                    provider = stubProvider utxos
                    session =
                        mkSession
                            Mainnet
                            pp
                            (inRangeSlot tx)
                            [n2cResolver provider]
                verdict <- driveVerdict session tx
                verdictStatus verdict `shouldBe` StructurallyClean
                verdictStructuralFailures verdict `shouldBe` []
                verdictWitnessNoiseCount verdict `shouldSatisfy` (> 0)
                exitCodeOf verdict `shouldBe` ExitSuccess
                renderHuman verdict
                    `shouldSatisfy` ("structurally clean" `Text.isInfixOf`)

        it
            ( "pre-fix issue-#8 body surfaces the integrity-hash "
                <> "structural failure (SC-003)"
            )
            $ do
                pp <- loadPParams ppPath
                tx <- loadBody bodyPath -- pre-fix as committed
                utxos <- loadUtxo producerTxDir issue8TxIns
                let provider = stubProvider utxos
                    session =
                        mkSession
                            Mainnet
                            pp
                            (inRangeSlot tx)
                            [n2cResolver provider]
                verdict <- driveVerdict session tx
                verdictStatus verdict `shouldBe` StructuralFailure
                exitCodeOf verdict `shouldBe` ExitFailure 1
                verdictStructuralFailures verdict
                    `shouldSatisfy` any isIntegrityHashMismatch
                let rendered = renderHuman verdict
                rendered `shouldSatisfy` ("structural failure" `Text.isInfixOf`)
                rendered
                    `shouldSatisfy` ( "PPViewHashesDontMatch"
                                        `Text.isInfixOf`
                                    )

    describe "renderJson" $ do
        it "emits the structurally-clean envelope per contract" $ do
            pp <- loadPParams ppPath
            buggy <- loadBody bodyPath
            utxos <- loadUtxo producerTxDir issue8TxIns
            let tx = postFix buggy
                provider = stubProvider utxos
                session =
                    mkSession
                        Mainnet
                        pp
                        (inRangeSlot tx)
                        [n2cResolver provider]
            verdict <- driveVerdict session tx
            let envelope = renderJson verdict
            jsonString envelope ["status"]
                `shouldBe` Just "structurally_clean"
            jsonInt envelope ["exit_code"] `shouldBe` Just 0
            jsonString envelope ["pparams_source"] `shouldBe` Just "n2c"
            jsonString envelope ["slot_source"] `shouldBe` Just "n2c"
            envelope `shouldSatisfy` hasStructuralFailuresEmpty

        it "emits the structural-failure envelope for the pre-fix body" $ do
            pp <- loadPParams ppPath
            tx <- loadBody bodyPath
            utxos <- loadUtxo producerTxDir issue8TxIns
            let provider = stubProvider utxos
                session =
                    mkSession
                        Mainnet
                        pp
                        (inRangeSlot tx)
                        [n2cResolver provider]
            verdict <- driveVerdict session tx
            let envelope = renderJson verdict
            jsonString envelope ["status"]
                `shouldBe` Just "structural_failure"
            jsonInt envelope ["exit_code"] `shouldBe` Just 1
            envelope `shouldSatisfy` hasIntegrityHashFailure

isIntegrityHashMismatch ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isIntegrityHashMismatch failure =
    let s = Text.pack (show failure)
     in "PPViewHashesDontMatch" `Text.isInfixOf` s
            || "ScriptIntegrityHashMismatch" `Text.isInfixOf` s

hasStructuralFailuresEmpty :: Aeson.Value -> Bool
hasStructuralFailuresEmpty (Aeson.Object o) =
    case Aeson.KeyMap.lookup "structural_failures" o of
        Just (Aeson.Array xs) -> null xs
        _ -> False
hasStructuralFailuresEmpty _ = False

{- | The envelope's @structural_failures@ array contains an entry
whose @constructor@ or @detail@ text mentions the integrity-hash
mismatch. We accept either field per
@contracts/json-output.md@'s stability note (constructor + rule
are stable; detail is best-effort).
-}
hasIntegrityHashFailure :: Aeson.Value -> Bool
hasIntegrityHashFailure (Aeson.Object o) = case Aeson.KeyMap.lookup "structural_failures" o of
    Just (Aeson.Array xs) -> any failureMatches xs
    _ -> False
hasIntegrityHashFailure _ = False

failureMatches :: Aeson.Value -> Bool
failureMatches (Aeson.Object o) =
    let c = case Aeson.KeyMap.lookup "constructor" o of
            Just (Aeson.String t) -> t
            _ -> ""
        d = case Aeson.KeyMap.lookup "detail" o of
            Just (Aeson.String t) -> t
            _ -> ""
     in mentionsIntegrity (c <> " " <> d)
failureMatches _ = False

mentionsIntegrity :: Text.Text -> Bool
mentionsIntegrity t =
    "PPViewHashesDontMatch" `Text.isInfixOf` t
        || "ScriptIntegrityHashMismatch" `Text.isInfixOf` t

jsonString :: Aeson.Value -> [Text.Text] -> Maybe Text.Text
jsonString val path = case (val, path) of
    (Aeson.String t, []) -> Just t
    (Aeson.Object o, k : rest) -> case Aeson.KeyMap.lookup (Aeson.fromText k) o of
        Just v -> jsonString v rest
        Nothing -> Nothing
    _ -> Nothing

jsonInt :: Aeson.Value -> [Text.Text] -> Maybe Int
jsonInt val path = case (val, path) of
    (Aeson.Number n, []) -> Just (round n)
    (Aeson.Object o, k : rest) -> case Aeson.KeyMap.lookup (Aeson.fromText k) o of
        Just v -> jsonInt v rest
        Nothing -> Nothing
    _ -> Nothing

{- | Drive the end-to-end validation pipeline as Main.hs does
but with the already-acquired session.
-}
driveVerdict :: Session -> ConwayTx -> IO Verdict
driveVerdict session tx = do
    let txIns = collectInputs tx
    (resolved, _unresolved) <-
        resolveChain (sessionUtxoResolvers session) txIns
    let utxoSources = Map.map (const "n2c") resolved
        utxo = Map.toList resolved
        result =
            validatePhase1
                (sessionNetwork session)
                (mkPParamsBound (sessionPParams session))
                utxo
                (sessionSlot session)
                tx
    pure (buildVerdict session utxoSources result)

ppPath :: FilePath
ppPath = "test/fixtures/pparams.json"

bodyPath :: FilePath
bodyPath =
    "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex"

producerTxDir :: FilePath
producerTxDir =
    "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs"

issue8TxIns :: [TxIn]
issue8TxIns =
    [ TxIn (txIdFromHex txId59e10) (TxIx 0)
    , TxIn (txIdFromHex txId59e10) (TxIx 2)
    , TxIn (txIdFromHex txIdF5f1b) (TxIx 0)
    ]

txId59e10 :: String
txId59e10 =
    "59e10ca5e03b8d243c699fc45e1e18a2a825e2a09c5efa6954aec820a4d64dfe"

txIdF5f1b :: String
txIdF5f1b =
    "f5f1bdfad3eb4d67d2fc36f36f47fc2938cf6f001689184ab320735a28642cf2"

txIdFromHex :: String -> TxId
txIdFromHex hex =
    TxId (unsafeMakeSafeHash (fromJust (hashFromStringAsHex hex)))

{- | Pick a slot inside the body's validity interval so the
validity-interval rule doesn't fail for an unrelated reason.
Lifted from @Cardano.Tx.ValidateSpec@.
-}
inRangeSlot :: ConwayTx -> SlotNo
inRangeSlot tx =
    let ValidityInterval lo _ = tx ^. bodyTxL . vldtTxBodyL
     in case lo of
            SJust s -> s
            SNothing -> SlotNo 0

{- | Derive the post-fix body by overwriting the committed
fixture's @script_integrity_hash@ to the value PR #9's fix now
emits. Same trick @Cardano.Tx.ValidateSpec.postFix@ uses.
-}
postFix :: ConwayTx -> ConwayTx
postFix tx =
    tx
        & bodyTxL
            . scriptIntegrityHashTxBodyL
            .~ SJust expectedIntegrityHash

expectedIntegrityHash :: ScriptIntegrityHash
expectedIntegrityHash =
    unsafeMakeSafeHash
        ( fromJust
            ( hashFromStringAsHex
                "41a7cd5798b8b6f081bfaee0f5f88dc02eea894b7ed888b2a8658b3784dcdcf9"
            )
        )

{- | A 'Provider IO' that serves only the 'queryUTxOByTxIn'
field the 'n2cResolver' touches. Every other field panics on
call.
-}
stubProvider ::
    [(TxIn, TxOut ConwayEra)] ->
    Provider IO
stubProvider utxos =
    Provider
        { withAcquired = \_ -> panicIO "withAcquired"
        , queryUTxOs = \_ -> panicIO "queryUTxOs"
        , queryUTxOByTxIn = \needed ->
            pure
                ( Map.fromList
                    [ entry
                    | entry@(txIn, _) <- utxos
                    , Set.member txIn needed
                    ]
                )
        , queryProtocolParams = panicIO "queryProtocolParams"
        , queryLedgerSnapshot = panicIO "queryLedgerSnapshot"
        , queryStakeRewards = \_ -> panicIO "queryStakeRewards"
        , queryRewardAccounts = \_ -> panicIO "queryRewardAccounts"
        , queryVoteDelegatees = \_ -> panicIO "queryVoteDelegatees"
        , queryTreasury = panicIO "queryTreasury"
        , queryGovernanceState = panicIO "queryGovernanceState"
        , evaluateTx = \_ -> panicIO "evaluateTx"
        , posixMsToSlot = \_ -> panicIO "posixMsToSlot"
        , posixMsCeilSlot = \_ -> panicIO "posixMsCeilSlot"
        , queryUpperBoundSlot = \_ -> panicIO "queryUpperBoundSlot"
        }
  where
    panicIO :: String -> IO a
    panicIO field =
        throwIO
            ( ErrorCall
                ("stubProvider." <> field <> " called by an unprepared test")
            )

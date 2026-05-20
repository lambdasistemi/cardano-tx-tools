{- |
Module      : Cardano.Tx.Validate.CliSpec
Description : Coverage for tx-validate's driver (parser + verdict).
License     : Apache-2.0
-}
module Cardano.Tx.Validate.CliSpec (
    spec,
) where

import Control.Exception (ErrorCall (..), throwIO)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Data.Version (makeVersion)
import GitHub.Release.Check (CliBanner (..), RepoSlug (..))
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Withdrawals (..),
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.TxBody (
    ScriptIntegrityHash,
    scriptIntegrityHashTxBodyL,
 )
import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Api.Tx.Body (
    outputsTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet),
    SlotNo (..),
    StrictMaybe (..),
    TxIx (..),
 )
import Cardano.Ledger.Binary (
    Annotator,
    Decoder,
    decCBOR,
    decodeFullAnnotatorFromHexText,
    natVersion,
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Rules (ConwayLedgerPredFailure)
import Cardano.Ledger.Core (bodyTxL)
import Cardano.Ledger.Credential (Credential (KeyHashObj))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (Staking))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Provider (Provider (..))
import System.Exit (ExitCode (..))

import Cardano.Tx.Build (mkPParamsBound)
import Cardano.Tx.Diff.Resolver (Resolver (..), resolveChain)
import Cardano.Tx.Diff.Resolver.N2C (n2cResolver)
import Cardano.Tx.Ledger (ConwayTx)
import Cardano.Tx.Validate (validatePhase1WithRewardAccounts)
import Cardano.Tx.Validate.Cli (
    InputSource (..),
    N2cConfig (..),
    OutputFormat (..),
    RewardAccountSource (..),
    Session (..),
    TxValidateCliOptions (..),
    Verdict (..),
    VerdictStatus (..),
    buildVerdict,
    collectInputs,
    collectWithdrawalAccounts,
    exitCodeOf,
    mkSession,
    mkSessionWithRewardAccounts,
    parseArgs,
    renderHuman,
    renderJson,
 )
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
                    fakeBanner
                    [ "--input"
                    , "tx.cbor.hex"
                    , "--n2c-socket-path"
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
                    fakeBanner
                    [ "--input"
                    , "-"
                    , "--n2c-socket-path"
                    , "/tmp/node.socket"
                    ]
            txValidateCliInput options `shouldBe` InputStdin

    describe "end-to-end validation" $ do
        it
            ( "registered withdrawal reward account from the provider "
                <> "suppresses WithdrawalsNotInRewardsCERTS"
            )
            $ do
                pp <- loadPParams ppPath
                buggy <- loadBody bodyPath
                utxos <- loadUtxo producerTxDir issue8TxIns
                calls <- newIORef []
                let tx = withWithdrawal (postFix buggy)
                    provider =
                        stubProviderWithRewardAccounts
                            utxos
                            (Map.singleton withdrawalRewardAccount (Coin 0))
                            calls
                verdict <- driveVerdictWithProvider pp provider tx
                readIORef calls
                    >>= (`shouldBe` [Set.singleton withdrawalRewardAccount])
                verdictStructuralFailures verdict
                    `shouldSatisfy` (not . any isWithdrawalsNotInRewardsFailure)

        it
            ( "unregistered withdrawal reward account still surfaces "
                <> "WithdrawalsNotInRewardsCERTS"
            )
            $ do
                pp <- loadPParams ppPath
                buggy <- loadBody bodyPath
                utxos <- loadUtxo producerTxDir issue8TxIns
                calls <- newIORef []
                let tx = withWithdrawal (postFix buggy)
                    provider =
                        stubProviderWithRewardAccounts
                            utxos
                            Map.empty
                            calls
                verdict <- driveVerdictWithProvider pp provider tx
                readIORef calls
                    >>= (`shouldBe` [Set.singleton withdrawalRewardAccount])
                verdictStructuralFailures verdict
                    `shouldSatisfy` any isWithdrawalsNotInRewardsFailure

        it
            ( "no-withdrawal transaction keeps the human render and "
                <> "does not query reward accounts"
            )
            $ do
                pp <- loadPParams ppPath
                buggy <- loadBody bodyPath
                utxos <- loadUtxo producerTxDir issue8TxIns
                calls <- newIORef []
                let tx = postFix buggy
                    provider =
                        stubProviderWithRewardAccounts
                            utxos
                            Map.empty
                            calls
                verdict <- driveVerdictWithProvider pp provider tx
                readIORef calls >>= (`shouldBe` [])
                renderHuman verdict
                    `shouldBe` Text.unlines
                        [ "structurally clean: "
                            <> Text.pack (show (verdictWitnessNoiseCount verdict))
                            <> " witness-completeness failures filtered"
                        ]

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
        it "emits reward account provenance for withdrawal lookup" $ do
            pp <- loadPParams ppPath
            buggy <- loadBody bodyPath
            utxos <- loadUtxo producerTxDir issue8TxIns
            calls <- newIORef []
            let tx = withWithdrawal (postFix buggy)
                provider =
                    stubProviderWithRewardAccounts
                        utxos
                        (Map.singleton withdrawalRewardAccount (Coin 0))
                        calls
            verdict <- driveVerdictWithProvider pp provider tx
            jsonString (renderJson verdict) ["reward_accounts_source"]
                `shouldBe` Just "n2c"

        it "emits not_required when no reward lookup was needed" $ do
            pp <- loadPParams ppPath
            buggy <- loadBody bodyPath
            utxos <- loadUtxo producerTxDir issue8TxIns
            calls <- newIORef []
            let tx = postFix buggy
                provider =
                    stubProviderWithRewardAccounts
                        utxos
                        Map.empty
                        calls
            verdict <- driveVerdictWithProvider pp provider tx
            jsonString (renderJson verdict) ["reward_accounts_source"]
                `shouldBe` Just "not_required"

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
            validatePhase1WithRewardAccounts
                (sessionNetwork session)
                (mkPParamsBound (sessionPParams session))
                utxo
                (sessionRewardAccounts session)
                (sessionSlot session)
                tx
    pure (buildVerdict session utxoSources result)

driveVerdictWithProvider ::
    PParams ConwayEra ->
    Provider IO ->
    ConwayTx ->
    IO Verdict
driveVerdictWithProvider pp provider tx = do
    let withdrawalAccounts = collectWithdrawalAccounts tx
    rewardAccounts <-
        if Set.null withdrawalAccounts
            then pure Map.empty
            else queryRewardAccounts provider withdrawalAccounts
    let rewardAccountsSource =
            if Set.null withdrawalAccounts
                then RewardAccountsNotRequired
                else RewardAccountsN2C
        session =
            mkSessionWithRewardAccounts
                Mainnet
                pp
                (inRangeSlot tx)
                [n2cResolver provider]
                rewardAccounts
                rewardAccountsSource
    sessionRewardAccounts session `shouldBe` rewardAccounts
    driveVerdict session tx

ppPath :: FilePath
ppPath = "test/fixtures/pparams.json"

{- | Load a Conway-era @PParams@ snapshot from a
@cardano-cli@-shaped JSON file.
-}
loadPParams :: FilePath -> IO (PParams ConwayEra)
loadPParams path = do
    r <- Aeson.eitherDecodeFileStrict path
    case r of
        Right pp -> pure pp
        Left err -> fail ("loadPParams " <> path <> ": " <> err)

{- | Load a Conway transaction from a @.cbor.hex@ file
used by the committed mainnet txbuild fixtures.
-}
loadBody :: FilePath -> IO ConwayTx
loadBody path = do
    hex <- Text.strip <$> TextIO.readFile path
    case decodeFullAnnotatorFromHexText
        (natVersion @11)
        (Text.pack ("swap-cancel body " <> path))
        (decCBOR :: forall s. Decoder s (Annotator ConwayTx))
        hex of
        Right tx -> pure tx
        Left err ->
            fail ("loadBody " <> path <> ": " <> show err)

bodyPath :: FilePath
bodyPath =
    "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex"

producerTxDir :: FilePath
producerTxDir =
    "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs"

loadUtxo ::
    FilePath ->
    [TxIn] ->
    IO [(TxIn, TxOut ConwayEra)]
loadUtxo dir txIns = do
    producers <-
        traverse
            ( \(txid, fileStem) -> do
                tx <- loadBody (producerPath fileStem)
                pure (txid, tx)
            )
            (Map.toList issue8ProducerFiles)
    let producerMap = Map.fromList producers
    pure (map (resolve producerMap) txIns)
  where
    producerPath fileStem =
        dir <> "/" <> fileStem <> ".cbor.hex"

    resolve ::
        Map.Map TxId ConwayTx ->
        TxIn ->
        (TxIn, TxOut ConwayEra)
    resolve producers txIn@(TxIn txid (TxIx ix)) =
        case Map.lookup txid producers of
            Nothing ->
                error ("CliSpec.loadUtxo: no producer tx for " <> show txid)
            Just producer ->
                let outs = producer ^. bodyTxL . outputsTxBodyL
                 in case StrictSeq.lookup (fromIntegral ix) outs of
                        Just out -> (txIn, out)
                        Nothing ->
                            error
                                ( "CliSpec.loadUtxo: TxIx "
                                    <> show ix
                                    <> " out of range for producer "
                                    <> show txid
                                )

issue8ProducerFiles :: Map.Map TxId String
issue8ProducerFiles =
    Map.fromList
        [ (txIdFromHex txId59e10, txId59e10)
        , (txIdFromHex txIdF5f1b, txIdF5f1b)
        ]

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

{- | A test-only 'CliBanner' the @--version@ flag would print
from; the values are irrelevant to the parser's logic, which only
needs the banner to plumb through the
@github-release-check:optparse@ helper.
-}
fakeBanner :: CliBanner
fakeBanner =
    CliBanner
        { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
        , cliExe = "tx-validate"
        , cliVersion = makeVersion [0, 0, 0]
        , cliOptOutEnvVar = "TX_VALIDATE_NO_UPDATE_CHECK"
        }

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

stubProviderWithRewardAccounts ::
    [(TxIn, TxOut ConwayEra)] ->
    Map.Map AccountAddress Coin ->
    IORef [Set.Set AccountAddress] ->
    Provider IO
stubProviderWithRewardAccounts utxos rewardAccounts calls =
    (stubProvider utxos)
        { queryRewardAccounts = \needed -> do
            modifyIORef' calls (<> [needed])
            pure (Map.restrictKeys rewardAccounts needed)
        }

withWithdrawal :: ConwayTx -> ConwayTx
withWithdrawal tx =
    tx
        & bodyTxL
            . withdrawalsTxBodyL
            .~ Withdrawals
                (Map.singleton withdrawalRewardAccount (Coin 0))

withdrawalRewardAccount :: AccountAddress
withdrawalRewardAccount = stubRewardAccount Mainnet 1

stubRewardAccount :: Network -> Int -> AccountAddress
stubRewardAccount network n =
    AccountAddress
        network
        (AccountId (KeyHashObj (KeyHash hash :: KeyHash Staking)))
  where
    hex = replicate 52 '0' ++ hexByte (n `div` 256) ++ hexByte (n `mod` 256)
    hexByte x = [d (x `div` 16), d (x `mod` 16)]
    d k = "0123456789abcdef" !! k
    hash = fromJust (hashFromStringAsHex hex)

isWithdrawalsNotInRewardsFailure ::
    ConwayLedgerPredFailure ConwayEra -> Bool
isWithdrawalsNotInRewardsFailure failure =
    "WithdrawalsNotInRewardsCERTS"
        `Text.isInfixOf` Text.pack (show failure)

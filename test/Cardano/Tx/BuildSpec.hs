{- |
Module      : Cardano.Tx.BuildSpec
Description : Scaffolding and golden tests for issue #8.
License     : Apache-2.0

Reproduces the mainnet @swap-cancel@
(tx @84b2bb78…0146f@) that surfaced the
@script_integrity_hash@ divergence from the ledger.
The on-disk fixtures are committed under
@test/fixtures/@; no socket access is performed at
test time (constitution VI — default-offline).
-}
module Cardano.Tx.BuildSpec (
    spec,

    -- * Fixture loaders
    loadPParams,
    loadBody,
) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Spec, describe, it, shouldBe, shouldContain, shouldSatisfy)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.Scripts (
    fromPlutusScript,
    mkPlutusScript,
 )
import Cardano.Ledger.Alonzo.TxBody (ScriptIntegrityHash)
import Cardano.Ledger.Alonzo.TxWits (TxDats (..))
import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Api.Tx (bodyTxL, estimateMinFeeTx, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    coinTxOutL,
    mkBasicTxOut,
    referenceScriptTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Binary (
    Annotator,
    Decoder,
    decCBOR,
    decodeFullAnnotatorFromHexText,
    natVersion,
    serialize',
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.TxBody (treasuryDonationTxBodyL)
import Cardano.Ledger.Conway.TxCert (
    ConwayDelegCert (..),
    ConwayTxCert (..),
 )
import Cardano.Ledger.Conway.UTxO (txNonDistinctRefScriptsSize)
import Cardano.Ledger.Core (Script, witsTxL)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (Payment, Staking))
import Cardano.Ledger.Mary.Value (
    MaryValue (..),
    MultiAsset (..),
 )
import Cardano.Ledger.Plutus.Language (
    Language (PlutusV2, PlutusV3),
    Plutus (..),
    PlutusBinary (..),
 )
import Cardano.Ledger.State (UTxO (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.Balance (BalanceResult (..), balanceFeeLoop, balanceTx, computeScriptIntegrity, languagesUsedInTx)
import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    build,
    donateToTreasury,
    draft,
    mkPParamsBound,
    registerStakeKey,
    registerStakeScript,
    spend,
 )
import Cardano.Tx.Ledger (ConwayTx)

-- | Test suite root.
spec :: Spec
spec = describe "Cardano.Tx.Build (issue #8 reproduction)" $ do
    swapCancelIntegrityHashSpec
    languagesUsedInTxSpec
    registerStakeSpec
    donationBalanceSpec
    donationInstructionSpec
    spentReferenceScriptFeeSpec

{- | The mainnet @swap-cancel@ regression: the fixture
body carries the @script_integrity_hash@ TxBuild
emitted at submission time
(@03e9d7ed…1941@); the ledger rejected the tx because
it recomputed @41a7cd57…dcf9@ from witnesses + cost
models.

This test asserts that 'computeScriptIntegrity', given
the redeemers from the fixture body and the committed
mainnet @PParams@ snapshot, produces the ledger's
expected value.

The failing tx is named @swap-cancel@ for a "Sundae
V3" order, but the *script* used to validate the
input is a 'PlutusV2' reference script — that is the
issue-#8 footgun. TxBuild hard-coded 'PlutusV3' for
the integrity-hash language argument, while the
ledger's recomputation correctly used 'PlutusV2' as
the script language. The fix derives the language
set from the body + reference UTxOs
(@languagesUsedInTx@); for this test we pin
@Set.singleton PlutusV2@ to mirror what
@languagesUsedInTx@ would produce, and verify the
hash matches the ledger's
@41a7cd57…dcf9@. T008's property test exercises
@languagesUsedInTx@ against the actual UTxO.
-}
swapCancelIntegrityHashSpec :: Spec
swapCancelIntegrityHashSpec =
    describe "swap-cancel reproduction" $ do
        it "computes the ledger's integrity hash" $ do
            pp <- loadPParams ppPath
            tx <- loadBody bodyPath
            let rdmrs = tx ^. witsTxL . rdmrsTxWitsL
                langs = Set.singleton PlutusV2
                dats = TxDats mempty
            computeScriptIntegrity langs pp rdmrs dats
                `shouldBe` SJust expectedIntegrityHash
  where
    ppPath = "test/fixtures/pparams.json"
    bodyPath =
        "test/fixtures/mainnet-txbuild/"
            <> "swap-cancel-issue-8/body.cbor.hex"

{- | Expected @script_integrity_hash@ for the fixture
body, taken from the ledger's rejection message at
submission time.
-}
expectedIntegrityHash :: ScriptIntegrityHash
expectedIntegrityHash =
    unsafeMakeSafeHash
        ( fromJust
            ( hashFromStringAsHex
                "41a7cd5798b8b6f081bfaee0f5f88dc02eea894b7ed888b2a8658b3784dcdcf9"
            )
        )

{- | End-to-end check that 'languagesUsedInTx' picks up
the Plutus language from a reference UTxO carrying a
ref-script — i.e. the fix is wired correctly through
TxBuild's data flow.

Two synthetic reference UTxOs are constructed: one
holding a 'PlutusV2' ref-script, the other a
'PlutusV3' ref-script. A minimal tx body references
both. The expected language set is @{V2, V3}@.

This is independent of the mainnet fixture (no
on-disk UTxO required); the swap-cancel reproduction
is covered by the golden hash test above.
-}
languagesUsedInTxSpec :: Spec
languagesUsedInTxSpec =
    describe "languagesUsedInTx" $ do
        it "picks up V2 and V3 from reference UTxOs" $ do
            let txin2 = stubTxIn 2
                txin3 = stubTxIn 3
                refUtxos =
                    [ (txin2, refTxOut alwaysTrueScriptV2)
                    , (txin3, refTxOut alwaysTrueScriptV3)
                    ]
                body =
                    mkBasicTxBody
                        & referenceInputsTxBodyL
                            .~ Set.fromList [txin2, txin3]
                tx = mkBasicTx body
            languagesUsedInTx tx refUtxos
                `shouldBe` Set.fromList [PlutusV2, PlutusV3]

stubTxIn :: Int -> TxIn
stubTxIn n =
    let hexStr =
            replicate 60 '0'
                ++ hexByte (n `div` 256)
                ++ hexByte (n `mod` 256)
        h = fromJust (hashFromStringAsHex hexStr)
     in TxIn (TxId (unsafeMakeSafeHash h)) (TxIx 0)
  where
    hexByte x =
        let s = "0123456789abcdef"
         in [s !! (x `div` 16), s !! (x `mod` 16)]

stubAddr :: Addr
stubAddr =
    let hexStr = replicate 56 '0'
        h = fromJust (hashFromStringAsHex hexStr)
     in Addr
            Testnet
            (KeyHashObj (KeyHash h :: KeyHash Payment))
            StakeRefNull

refTxOut :: Script ConwayEra -> TxOut ConwayEra
refTxOut script =
    mkBasicTxOut stubAddr zeroValue
        & referenceScriptTxOutL .~ SJust script
  where
    zeroValue = MaryValue (Coin 0) (MultiAsset mempty)

alwaysTrueScriptV2 :: Script ConwayEra
alwaysTrueScriptV2 = mkAlwaysTrue PlutusV2

alwaysTrueScriptV3 :: Script ConwayEra
alwaysTrueScriptV3 = mkAlwaysTrue PlutusV3

{- | Build an always-true Plutus script of the given
language. The script bytes are reused from
@ConwaySpec@'s fixture; they're a valid always-true
script that 'mkPlutusScript' accepts under both V2
and V3.
-}
mkAlwaysTrue :: Language -> Script ConwayEra
mkAlwaysTrue lang =
    let bytes =
            either error id $
                Base16.decode (BS8.filter (/= '\n') alwaysTrueHex)
        binary = PlutusBinary (SBS.toShort bytes)
     in case lang of
            PlutusV2 ->
                maybe (error "mkAlwaysTrue V2") fromPlutusScript $
                    mkPlutusScript (Plutus @PlutusV2 binary)
            PlutusV3 ->
                maybe (error "mkAlwaysTrue V3") fromPlutusScript $
                    mkPlutusScript (Plutus @PlutusV3 binary)
            other ->
                error ("mkAlwaysTrue: unsupported " <> show other)

alwaysTrueHex :: BS8.ByteString
alwaysTrueHex =
    "58d501010029800aba2aba1aab9eaab9dab9a48888966002646465\
    \300130053754003300700398038012444b30013370e9000001c4c\
    \9289bae300a3009375400915980099b874800800e2646644944c0\
    \2c004c02cc030004c024dd5002456600266e1d200400389925130\
    \0a3009375400915980099b874801800e2646644944dd698058009\
    \805980600098049baa0048acc004cdc3a40100071324a26014601\
    \26ea80122646644944dd698058009805980600098049baa004401\
    \c8039007200e401c3006300700130060013003375400d149a26ca\
    \c8009"

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
(one line of base-16 CBOR, optionally surrounded by
whitespace).

Matches the on-disk format used elsewhere in
@test/fixtures/mainnet-txbuild/@.
-}
loadBody :: FilePath -> IO ConwayTx
loadBody path = do
    hex <- Text.strip <$> Text.readFile path
    case decodeFullAnnotatorFromHexText
        (natVersion @11)
        (Text.pack ("swap-cancel body " <> path))
        (decCBOR :: forall s. Decoder s (Annotator ConwayTx))
        hex of
        Right tx -> pure tx
        Left err ->
            fail ("loadBody " <> path <> ": " <> show err)

-- | Uninhabited query context for programs that make no 'ctx' calls.
data NoCtx a

{- | Verify that 'registerStakeKey' and 'registerStakeScript' place
the expected 'ConwayRegCert' in the transaction body.
-}
registerStakeSpec :: Spec
registerStakeSpec =
    describe "registerStake helpers" $ do
        it "registerStakeKey adds a ConwayRegCert for a key credential" $ do
            pp <- loadPParams "test/fixtures/pparams.json"
            let seed =
                    ( stubTxIn 10
                    , mkBasicTxOut stubAddr (MaryValue (Coin 100_000_000) (MultiAsset mempty))
                    )
                prog :: TxBuild NoCtx String ()
                prog = do
                    _ <- spend (fst seed)
                    _ <- registerStakeKey stubStakingKeyHash
                    pure ()
            result <-
                build
                    (mkPParamsBound pp)
                    (InterpretIO (error "no ctx"))
                    (\_ -> pure Map.empty)
                    [seed]
                    []
                    stubAddr
                    prog
            case result of
                Left err -> fail (show err)
                Right tx ->
                    toList (tx ^. bodyTxL . certsTxBodyL)
                        `shouldContain` [ConwayTxCertDeleg (ConwayRegCert (KeyHashObj stubStakingKeyHash) SNothing)]

        it "registerStakeScript adds a ConwayRegCert for a script credential" $ do
            pp <- loadPParams "test/fixtures/pparams.json"
            let seed =
                    ( stubTxIn 11
                    , mkBasicTxOut stubAddr (MaryValue (Coin 100_000_000) (MultiAsset mempty))
                    )
                prog :: TxBuild NoCtx String ()
                prog = do
                    _ <- spend (fst seed)
                    _ <- registerStakeScript stubScriptHash
                    pure ()
            result <-
                build
                    (mkPParamsBound pp)
                    (InterpretIO (error "no ctx"))
                    (\_ -> pure Map.empty)
                    [seed]
                    []
                    stubAddr
                    prog
            case result of
                Left err -> fail (show err)
                Right tx ->
                    toList (tx ^. bodyTxL . certsTxBodyL)
                        `shouldContain` [ConwayTxCertDeleg (ConwayRegCert (ScriptHashObj stubScriptHash) SNothing)]

stubStakingKeyHash :: KeyHash Staking
stubStakingKeyHash =
    KeyHash
        (fromJust (hashFromStringAsHex (replicate 56 'a')))

stubScriptHash :: ScriptHash
stubScriptHash =
    ScriptHash
        (fromJust (hashFromStringAsHex (replicate 56 'b')))

-- | Treasury donations reduce change and remain part of the final fee calculation.
donationBalanceSpec :: Spec
donationBalanceSpec = describe "treasury donation balancing" $ do
    it "preserves ordinary build bytes captured before donation support" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        tx <- ordinaryBuild pp
        expected <- BS8.readFile "test/fixtures/mainnet-txbuild/no-donation-build.hex"
        Base16.encode (serialize' (natVersion @11) tx) `shouldBe` BS8.filter (/= '\n') expected
    mapM_
        ( \donation -> it ("conserves value with donation " <> show donation) $ do
            pp <- loadPParams "test/fixtures/pparams.json"
            let amount = 100_000_000
                seed = (stubTxIn 15, mkBasicTxOut stubAddr (MaryValue (Coin amount) mempty))
                template = mkBasicTx (mkBasicTxBody & treasuryDonationTxBodyL .~ Coin donation)
            result <- either (fail . show) pure (balanceTx pp [seed] [] stubAddr template)
            let tx = balancedTx result
                Coin fee = tx ^. bodyTxL . feeTxBodyL
                paid = sum [c | out <- toList (tx ^. bodyTxL . outputsTxBodyL), let Coin c = out ^. coinTxOutL]
            paid + fee + donation `shouldBe` amount
            tx ^. bodyTxL . treasuryDonationTxBodyL `shouldBe` Coin donation
            Coin fee `shouldSatisfy` (>= estimateMinFeeTx pp tx 1 0 0)
        )
        [0, 1_000_000, 15_000_000]
    it "refuses a donation larger than the available funds beside a funded control" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        let seed = (stubTxIn 15, mkBasicTxOut stubAddr (MaryValue (Coin 100_000_000) mempty))
            balancing donation =
                balanceTx
                    pp
                    [seed]
                    []
                    stubAddr
                    (mkBasicTx (mkBasicTxBody & treasuryDonationTxBodyL .~ Coin donation))
        case balancing 1_000_000 of
            Left err -> fail (show err)
            Right _ -> pure ()
        case balancing 100_000_001 of
            Left _ -> pure ()
            Right _ -> fail "the donation exceeded its funding"

ordinaryBuild :: PParams ConwayEra -> IO ConwayTx
ordinaryBuild pp = do
    let seed = (stubTxIn 15, mkBasicTxOut stubAddr (MaryValue (Coin 100_000_000) mempty))
        program :: TxBuild NoCtx String ()
        program = do
            _ <- spend (fst seed)
            pure ()
    result <-
        build
            (mkPParamsBound pp)
            (InterpretIO (error "no context"))
            (\_ -> pure Map.empty)
            [seed]
            []
            stubAddr
            program
    either (fail . show) pure result

-- | Donation is present at the evaluator boundary and remains funded after balancing.
donationInstructionSpec :: Spec
donationInstructionSpec = describe "treasury donation instruction" $ do
    mapM_
        ( \donation -> it ("evaluates and funds donation " <> show donation) $ do
            pp <- loadPParams "test/fixtures/pparams.json"
            tx <- buildDonation pp (Coin donation)
            let Coin fee = tx ^. bodyTxL . feeTxBodyL
                paid = sum [c | out <- toList (tx ^. bodyTxL . outputsTxBodyL), let Coin c = out ^. coinTxOutL]
            tx ^. bodyTxL . treasuryDonationTxBodyL `shouldBe` Coin donation
            paid + fee + donation `shouldBe` 100_000_000
            Coin fee `shouldSatisfy` (>= estimateMinFeeTx pp tx 1 0 0)
        )
        [0, 1_000_000, 15_000_000]
    it "uses the last donation instruction" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        let program :: TxBuild NoCtx String ()
            program = do
                donateToTreasury (Coin 1_000_000)
                donateToTreasury (Coin 3_000_000)
        draft pp program ^. bodyTxL . treasuryDonationTxBodyL `shouldBe` Coin 3_000_000
    it "preserves the bytes of a build with no instruction when zero is set" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        without <- ordinaryBuild pp
        withZero <- buildDonation pp (Coin 0)
        serialize' (natVersion @11) withZero `shouldBe` serialize' (natVersion @11) without

buildDonation :: PParams ConwayEra -> Coin -> IO ConwayTx
buildDonation pp donation = do
    let seed = (stubTxIn 15, mkBasicTxOut stubAddr (MaryValue (Coin 100_000_000) mempty))
        program :: TxBuild NoCtx String ()
        program = do
            _ <- spend (fst seed)
            donateToTreasury donation
        evaluator tx = do
            tx ^. bodyTxL . treasuryDonationTxBodyL `shouldBe` donation
            pure Map.empty
    result <-
        build
            (mkPParamsBound pp)
            (InterpretIO (error "no context"))
            evaluator
            [seed]
            []
            stubAddr
            program
    either (fail . show) pure result

{- | Issue #167: the ledger charges
@minFeeRefScriptCostPerByte@ for the reference
scripts carried by spent inputs, not only by
reference inputs. Each balancer must pay at least the
fee the ledger computes from its own reference-script
size over the resolved UTxO.
-}
spentReferenceScriptFeeSpec :: Spec
spentReferenceScriptFeeSpec = describe "reference script carried by a spent input" $ do
    let seed =
            ( stubTxIn 21
            , mkBasicTxOut stubAddr (MaryValue (Coin 100_000_000) mempty)
                & referenceScriptTxOutL .~ SJust alwaysTrueScriptV3
            )
        ledgerMinFee pp tx =
            estimateMinFeeTx
                pp
                tx
                1
                0
                (txNonDistinctRefScriptsSize (UTxO (Map.fromList [seed])) tx)
    it "the ledger charges the spent input's script" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        let tx = mkBasicTx (mkBasicTxBody & inputsTxBodyL .~ Set.singleton (fst seed))
        ledgerMinFee pp tx `shouldSatisfy` (> estimateMinFeeTx pp tx 1 0 0)
    it "build pays it" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        let program :: TxBuild NoCtx String ()
            program = do
                _ <- spend (fst seed)
                pure ()
        result <-
            build
                (mkPParamsBound pp)
                (InterpretIO (error "no context"))
                (\_ -> pure Map.empty)
                [seed]
                []
                stubAddr
                program
        tx <- either (fail . show) pure result
        tx ^. bodyTxL . feeTxBodyL `shouldSatisfy` (>= ledgerMinFee pp tx)
    it "balanceTx pays it" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        result <- either (fail . show) pure (balanceTx pp [seed] [] stubAddr (mkBasicTx mkBasicTxBody))
        let tx = balancedTx result
        tx ^. bodyTxL . feeTxBodyL `shouldSatisfy` (>= ledgerMinFee pp tx)
    it "balanceFeeLoop pays it" $ do
        pp <- loadPParams "test/fixtures/pparams.json"
        let template = mkBasicTx (mkBasicTxBody & inputsTxBodyL .~ Set.singleton (fst seed))
            mkOutputs (Coin fee) =
                Right (StrictSeq.singleton (mkBasicTxOut stubAddr (MaryValue (Coin (100_000_000 - fee)) mempty)))
        tx <- either (fail . show) pure (balanceFeeLoop pp mkOutputs 1 [seed] template)
        tx ^. bodyTxL . feeTxBodyL `shouldSatisfy` (>= ledgerMinFee pp tx)

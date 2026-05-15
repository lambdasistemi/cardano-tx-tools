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
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Lens.Micro ((&), (.~), (^.))
import Test.Hspec (Spec, describe, it, shouldBe)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.Scripts (
    fromPlutusScript,
    mkPlutusScript,
 )
import Cardano.Ledger.Alonzo.TxBody (ScriptIntegrityHash)
import Cardano.Ledger.Alonzo.TxWits (TxDats (..))
import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Api.Tx (mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (
    mkBasicTxBody,
    referenceInputsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    mkBasicTxOut,
    referenceScriptTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (
    Network (Testnet),
    StrictMaybe (SJust),
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
import Cardano.Ledger.Core (Script, witsTxL)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (Payment))
import Cardano.Ledger.Mary.Value (
    MaryValue (..),
    MultiAsset (..),
 )
import Cardano.Ledger.Plutus.Language (
    Language (PlutusV2, PlutusV3),
    Plutus (..),
    PlutusBinary (..),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.Balance (computeScriptIntegrity, languagesUsedInTx)
import Cardano.Tx.Ledger (ConwayTx)

-- | Test suite root.
spec :: Spec
spec = describe "Cardano.Tx.Build (issue #8 reproduction)" $ do
    swapCancelIntegrityHashSpec
    languagesUsedInTxSpec

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

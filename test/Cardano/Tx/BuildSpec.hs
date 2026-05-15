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
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Lens.Micro ((^.))
import Test.Hspec (Spec, describe, it, shouldBe)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Alonzo.TxBody (ScriptIntegrityHash)
import Cardano.Ledger.Alonzo.TxWits (TxDats (..))
import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (StrictMaybe (SJust))
import Cardano.Ledger.Binary (
    Annotator,
    Decoder,
    decCBOR,
    decodeFullAnnotatorFromHexText,
    natVersion,
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (witsTxL)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.Plutus.Language (Language (PlutusV2))

import Cardano.Tx.Balance (computeScriptIntegrity)
import Cardano.Tx.Ledger (ConwayTx)

-- | Test suite root.
spec :: Spec
spec = describe "Cardano.Tx.Build (issue #8 reproduction)" $ do
    swapCancelIntegrityHashSpec

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

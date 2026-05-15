{- |
Module      : Cardano.Tx.BuildSpec
Description : Scaffolding for the swap-cancel issue #8 reproduction.
License     : Apache-2.0

Fixture loaders for the @TxBuild self-validation@ work
(cardano-tx-tools#8). Loaders read on-disk fixtures captured from
mainnet; no socket access at test time
(constitution VI — default-offline).

The actual reproduction and self-validation tests are added
in the per-behavior commits that close the issue (see
@specs/008-txbuild-integrity-hash/tasks.md@ T006 onward).
This module's @spec@ is intentionally empty until then so
introducing it does not change test outcomes.
-}
module Cardano.Tx.BuildSpec (
    spec,
    -- * Fixture loaders
    loadPParams,
    loadBody,
) where

import Data.Aeson qualified as Aeson
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Test.Hspec (Spec)

import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.Binary (
    Annotator,
    Decoder,
    decCBOR,
    decodeFullAnnotatorFromHexText,
    natVersion,
 )
import Cardano.Ledger.Conway (ConwayEra)

import Cardano.Tx.Ledger (ConwayTx)

{- | Empty test spec. Per constitution VII (TDD vertical
bisect-safe commits), real tests land alongside the
behavior change that makes them GREEN (T006/T008/T009 in
the feature's @tasks.md@).
-}
spec :: Spec
spec = pure ()

{- | Load a Conway-era @PParams@ snapshot from a
@cardano-cli@-shaped JSON file.

The committed @test/fixtures/pparams.json@ is the
canonical mainnet snapshot used by the issue-#8
reproduction.
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

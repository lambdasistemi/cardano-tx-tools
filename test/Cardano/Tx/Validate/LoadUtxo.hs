{- |
Module      : Cardano.Tx.Validate.LoadUtxo
Description : Resolve fixture UTxO from producer-tx CBOR files.
License     : Apache-2.0

Test-only helper. Reads a directory of canonical producer-tx CBOR
hex files (one per producer 'TxId', filename
@<txIdHex>.cbor.hex@), decodes each via the ledger's annotator
decoder, and resolves an arbitrary list of 'TxIn's against those
producer transactions by indexing into each producer's outputs.

The producer-tx CBOR shape is the ledger-canonical evidence form;
it is the same shape
[@cardano-ledger-inspector@'s @Conway.Inspector.Context.ProducerTx@](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Context.hs)
consumes (we wrap it in typed Haskell instead of JSON). See
@specs/014-validate-phase1/research.md R4@ for the rationale.
-}
module Cardano.Tx.Validate.LoadUtxo (
    loadUtxo,
) where

import Data.ByteString.Base16 qualified as Base16
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Sequence.Strict qualified as StrictSeq
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Lens.Micro ((^.))
import System.FilePath ((<.>), (</>))

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (bodyTxL)
import Cardano.Ledger.Hashes (extractHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Tx.BuildSpec (loadBody)
import Cardano.Tx.Ledger (ConwayTx)

{- | Read every producer-tx CBOR file the supplied 'TxIn's reference
and resolve each 'TxIn' to the @(TxIn, TxOut)@ pair the ledger
needs.

The directory must contain one @<txIdHex>.cbor.hex@ file per
unique 'TxId' across @txIns@. The CBOR shape is the canonical
ledger-binary form produced by, e.g.,
@GET /txs/\<hash\>/cbor@ on Blockfrost or
@cardano-cli transaction view@'s raw-CBOR path; both round-trip
through the same decoder the node uses.

This function is intentionally simple: it fails loudly via
'error' if a producer-tx file is missing or a 'TxIx' is out of
range. The test suite is the only caller, and a missing fixture
is an author bug, not a runtime condition.

Example:

> loadUtxo
>     "test/fixtures/mainnet-txbuild/swap-cancel-issue-8/producer-txs"
>     [TxIn txid59e10 (TxIx 0), TxIn txid59e10 (TxIx 2), TxIn txidF5f1b (TxIx 0)]
-}
loadUtxo ::
    FilePath ->
    [TxIn] ->
    IO [(TxIn, TxOut ConwayEra)]
loadUtxo dir txIns = do
    let needed = List.nub (map (\(TxIn txid _) -> txid) txIns)
    decoded <- traverse (loadProducer dir) needed
    let producers = Map.fromList (zip needed decoded)
    pure (map (resolve producers) txIns)
  where
    loadProducer :: FilePath -> TxId -> IO ConwayTx
    loadProducer base txid =
        loadBody (base </> Text.unpack (txIdHex txid) <.> "cbor" <.> "hex")

    resolve ::
        Map.Map TxId ConwayTx ->
        TxIn ->
        (TxIn, TxOut ConwayEra)
    resolve producers txIn@(TxIn txid (TxIx ix)) =
        case Map.lookup txid producers of
            Nothing ->
                error
                    ( "LoadUtxo.loadUtxo: no producer tx for "
                        <> Text.unpack (txIdHex txid)
                    )
            Just producer ->
                let outs = producer ^. bodyTxL . outputsTxBodyL
                 in case StrictSeq.lookup (fromIntegral ix) outs of
                        Just out -> (txIn, out)
                        Nothing ->
                            error
                                ( "LoadUtxo.loadUtxo: TxIx "
                                    <> show ix
                                    <> " out of range for producer "
                                    <> Text.unpack (txIdHex txid)
                                )

-- | Hex render of the BLAKE2b-256 transaction-body hash a 'TxId' wraps.
txIdHex :: TxId -> Text.Text
txIdHex (TxId safeHash) =
    Text.decodeUtf8 (Base16.encode (hashToBytes (extractHash safeHash)))

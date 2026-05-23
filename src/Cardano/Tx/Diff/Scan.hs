{- |
Module      : Cardano.Tx.Diff.Scan
Description : Pure mapping from inspect-tree leaves to Cardanoscan URLs.
License     : Apache-2.0

The library-level contract for issue #88. Defines the
'InspectLeaf' ADT (one constructor per leaf class
@tx-inspect@ knows how to link), the supported 'Network' set
('Mainnet' / 'Preprod' / 'Preview'), and the total mapping
'cardanoscanUrl' that yields a typed 'Url' for any
@(Network, InspectLeaf)@ pair.

A small bridge layer ('classifyConwayLeaf', 'scanLinker') maps
the project's existing leaf substrate ('ConwayDiffValue') into
'InspectLeaf' values that the trie renderer can annotate. The
bridge is best-effort — it covers the leaf classes the
substrate exposes atomically. Adding new classes is additive
(extend 'classifyConwayLeaf'); it does not change the URL
shape.

This module is pure: no I/O, no orphans, no implicit network
assumptions. Callers either supply a 'Network' explicitly or
derive one via 'parseNetworkMagic'.
-}
module Cardano.Tx.Diff.Scan (
    -- * Networks
    Network (..),
    UnsupportedNetworkMagic (..),
    parseNetworkMagic,

    -- * Leaf identifiers
    InspectLeaf (..),

    -- * URLs

    -- (re-exported from "Cardano.Tx.Diff" so callers can build linkers
    -- without touching the renderer module directly)
    Url (..),
    LeafLinker,
    cardanoscanUrl,

    -- * Bridge from the inspect substrate
    classifyConwayLeaf,
    scanLinker,
) where

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (Addr, serialiseAddr)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Hashes (extractHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Text (Text)
import Data.Text.Encoding qualified as TextEncoding
import Data.Word (Word32, Word64)

import Cardano.Tx.Diff (ConwayDiffValue (..), LeafLinker, Url (..))

-- | The Cardanoscan-supported networks tx-inspect can link against.
data Network
    = Mainnet
    | Preprod
    | Preview
    deriving stock (Eq, Show)

{- | A 'Word32' magic that does not map to any supported 'Network'.
Carries the offending magic for operator-facing error messages.
-}
newtype UnsupportedNetworkMagic
    = UnsupportedNetworkMagic Word32
    deriving stock (Eq, Show)

{- | Map a Cardano network magic to a 'Network', or fail with the
typed error. The three magics encoded here are the canonical
mainnet / preprod / preview magics used by every IOG-published
network configuration.
-}
parseNetworkMagic :: Word32 -> Either UnsupportedNetworkMagic Network
parseNetworkMagic 764824073 = Right Mainnet
parseNetworkMagic 1 = Right Preprod
parseNetworkMagic 2 = Right Preview
parseNetworkMagic magic = Left (UnsupportedNetworkMagic magic)

-- | A leaf class that can be linked to a Cardanoscan page.
data InspectLeaf
    = -- | A 32-byte transaction hash, hex-encoded.
      InspectTxHash Text
    | -- | A tx-input reference: producer transaction hash (hex) plus
      -- output index. The link points at the producing transaction;
      -- index highlighting is intentionally out of scope.
      InspectTxIn Text Word64
    | -- | A bech32 payment address (@addr1...@ / @addr_test1...@).
      InspectPaymentAddress Text
    | -- | A bech32 stake address (@stake1...@ / @stake_test1...@).
      InspectStakeAddress Text
    | -- | A 28-byte minting policy id, hex-encoded.
      InspectPolicyId Text
    | -- | A CIP-14 asset fingerprint (@asset1...@).
      InspectAssetFingerprint Text
    deriving stock (Eq, Show)

{- | Total mapping from a leaf identifier to its Cardanoscan URL.

Mainnet uses @cardanoscan.io@; testnet uses
@\<network\>.cardanoscan.io@. Paths follow Cardanoscan's URL
scheme exactly:

* tx hash / tx-in producer → @/transaction/\<hash\>@
* payment address          → @/address/\<bech32\>@
* stake address            → @/stakekey/\<bech32\>@
* policy id                → @/tokenPolicy/\<policy-hex\>@
* asset fingerprint        → @/token/\<asset1...\>@

Every constructor maps to a URL on every network — no partiality.
-}
cardanoscanUrl :: Network -> InspectLeaf -> Url
cardanoscanUrl network leaf =
    Url (host network <> path leaf)
  where
    host n =
        "https://"
            <> case n of
                Mainnet -> "cardanoscan.io"
                Preprod -> "preprod.cardanoscan.io"
                Preview -> "preview.cardanoscan.io"
    path (InspectTxHash hash) = "/transaction/" <> hash
    path (InspectTxIn hash _ix) = "/transaction/" <> hash
    path (InspectPaymentAddress bech32) = "/address/" <> bech32
    path (InspectStakeAddress bech32) = "/stakekey/" <> bech32
    path (InspectPolicyId hex) = "/tokenPolicy/" <> hex
    path (InspectAssetFingerprint fp) = "/token/" <> fp

{- | Classify a single 'ConwayDiffValue' as an 'InspectLeaf' when its
shape uniquely identifies a Cardanoscan-linkable leaf class.

S1 covers the leaf classes that can be derived from a single
'ConwayDiffValue' atom:

* 'ConwayTxInValue' / 'ConwayTxInIdValue' → 'InspectTxIn'
* 'ConwayAddressValue' → 'InspectPaymentAddress'
  (bech32-encoded under the supplied 'Network')

Other variants in 'InspectLeaf' (stake address, policy id, asset
fingerprint) are reachable from substrate paths that compose
multiple leaves; classifying them is additive in a follow-up
slice and does not change the URL shape.
-}
classifyConwayLeaf :: Network -> ConwayDiffValue -> Maybe InspectLeaf
classifyConwayLeaf _ (ConwayTxInValue txIn) =
    Just (txInToLeaf txIn)
classifyConwayLeaf _ (ConwayTxInIdValue txIn) =
    Just (txInToLeaf txIn)
classifyConwayLeaf network (ConwayAddressValue addr) =
    Just (InspectPaymentAddress (encodeAddrBech32 network addr))
classifyConwayLeaf _ _ = Nothing

-- | Convenience: build a 'LeafLinker' for the given 'Network'.
scanLinker :: Network -> LeafLinker
scanLinker network = fmap (cardanoscanUrl network) . classifyConwayLeaf network

-- Internal helpers ----------------------------------------------------

txInToLeaf :: TxIn -> InspectLeaf
txInToLeaf (TxIn (TxId safeHash) (TxIx ix)) =
    InspectTxIn (hexText (hashToBytes (extractHash safeHash))) (fromIntegral ix)

hexText :: ByteString -> Text
hexText = TextEncoding.decodeUtf8 . Base16.encode

encodeAddrBech32 :: Network -> Addr -> Text
encodeAddrBech32 network addr =
    case Bech32.humanReadablePartFromText hrp of
        Right h ->
            Bech32.encodeLenient h (Bech32.dataPartFromBytes (serialiseAddr addr))
        Left _ ->
            -- The HRPs encoded here are static and known-valid; this
            -- branch is unreachable. Returning a marker makes any
            -- future typo loud in the rendered output.
            "<invalid-hrp:" <> hrp <> ">"
  where
    hrp = case network of
        Mainnet -> "addr"
        Preprod -> "addr_test"
        Preview -> "addr_test"

{- |
Module      : Cardano.Tx.Graph.Rules.Load.Bech32
Description : Bech32 address decomposition for the YAML compiler.
License     : Apache-2.0

Internal helper for the @entities: from-address: \<bech32\>@ shape.
Reuses 'Cardano.Tx.Diff.decodeBech32Address' (already in the
@cardano-tx-tools@ library's dep tree) to decode a bech32 string into a
'Cardano.Ledger.Address.Addr', then case-matches on the payment and
stake credentials to produce 1–2 'EntityIdentifier' values.

The mapping:

* Payment credential ('KeyHashObj' / 'ScriptHashObj') →
  ('PaymentKey' / 'PaymentScript') identifier with the 28-byte hash
  rendered as 56 lowercase hex characters.
* Stake credential ('StakeRefBase') → ('StakeKey' / 'StakeScript')
  identifier with the same byte rendering. Pointer references and
  enterprise (no-stake) addresses produce no stake identifier.
* Byron bootstrap addresses → 'Left BadBech32' (the constitution
  targets Conway-only).

The function is total over the @addr@/@addr_test@ bech32 surface; any
malformed input surfaces as 'BadBech32' with the operator-typed string
verbatim.
-}
module Cardano.Tx.Graph.Rules.Load.Bech32 (
    decomposeFromAddress,
    decodePoolBech32,
    decodeDrepCip129,
) where

import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteString qualified as BS

import Cardano.Tx.Diff (decodeBech32Address)
import Cardano.Tx.Graph.Rules.Load.Types (
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
 )

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefBase, StakeRefNull, StakeRefPtr),
 )
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..))
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Text (Text)
import Data.Text.Encoding qualified as TextEncoding

{- | Decompose a @from-address: \<bech32\>@ value into the entity's
@cardano:hasIdentifier@ leaves. The list is in @payment first, stake
second@ order; enterprise addresses produce a single-element list.

Pointer-style stake references are treated like enterprise: no stake
identifier is emitted (pointer addresses are deprecated and do not
appear in the 11 rewrite-redesign fixtures).

Byron bootstrap addresses are rejected.
-}
decomposeFromAddress ::
    FilePath ->
    Int ->
    Text ->
    Either RulesLoadError [EntityIdentifier]
decomposeFromAddress file line bech32 =
    case decodeBech32Address bech32 of
        Left _ ->
            Left (BadBech32 file line bech32)
        Right (AddrBootstrap _) ->
            Left (BadBech32 file line bech32)
        Right (Addr _network paymentCred stakeRef) ->
            Right (paymentIdentifier paymentCred : stakeIdentifiers stakeRef)

paymentIdentifier :: Credential payment -> EntityIdentifier
paymentIdentifier = \case
    KeyHashObj (KeyHash h) ->
        EntityIdentifier PaymentKey (hexHash (hashToBytes h))
    ScriptHashObj (ScriptHash h) ->
        EntityIdentifier PaymentScript (hexHash (hashToBytes h))

stakeIdentifiers :: StakeReference -> [EntityIdentifier]
stakeIdentifiers = \case
    StakeRefNull -> []
    StakeRefPtr _ -> []
    StakeRefBase (KeyHashObj (KeyHash h)) ->
        [EntityIdentifier StakeKey (hexHash (hashToBytes h))]
    StakeRefBase (ScriptHashObj (ScriptHash h)) ->
        [EntityIdentifier StakeScript (hexHash (hashToBytes h))]

hexHash :: ByteString -> Text
hexHash = TextEncoding.decodeUtf8 . Base16.encode

{- | Decode a @pool: \<bech32\>@ value into a single 'PoolId'
identifier. The bech32 string uses HRP @"pool"@ and the data part
is exactly 28 bytes (the pool key-hash). Returns 'BadBech32' on any
framing/decode failure or wrong byte length.
-}
decodePoolBech32 ::
    FilePath ->
    Int ->
    Text ->
    Either RulesLoadError [EntityIdentifier]
decodePoolBech32 file line bech32 =
    case Bech32.decodeLenient bech32 of
        Left _ -> Left (BadBech32 file line bech32)
        Right (_hrp, dataPart) ->
            case Bech32.dataPartToBytes dataPart of
                Nothing -> Left (BadBech32 file line bech32)
                Just bytes
                    | BS.length bytes == 28 ->
                        Right [EntityIdentifier PoolId (hexHash bytes)]
                    | otherwise -> Left (BadBech32 file line bech32)

{- | Decode a @drep: \<CIP-129 bech32\>@ value into a single
'DRepKey' or 'DRepScript' identifier. CIP-129 encodes the credential
discriminator in the first byte of the data part: @0x22@ for
@DRepKey@ and @0x23@ for @DRepScript@. The remaining 28 bytes are
the credential hash. The bech32 HRP is @"drep"@.

Any framing/decode failure, wrong total byte length, or unknown
discriminator byte surfaces as 'BadBech32'.
-}
decodeDrepCip129 ::
    FilePath ->
    Int ->
    Text ->
    Either RulesLoadError [EntityIdentifier]
decodeDrepCip129 file line bech32 =
    case Bech32.decodeLenient bech32 of
        Left _ -> Left (BadBech32 file line bech32)
        Right (_hrp, dataPart) ->
            case Bech32.dataPartToBytes dataPart of
                Nothing -> Left (BadBech32 file line bech32)
                Just bytes
                    | BS.length bytes == 29 ->
                        let prefix = BS.head bytes
                            hash28 = BS.drop 1 bytes
                            mkLeaf lt =
                                Right
                                    [ EntityIdentifier
                                        lt
                                        (hexHash hash28)
                                    ]
                         in case prefix of
                                0x22 -> mkLeaf DRepKey
                                0x23 -> mkLeaf DRepScript
                                _ -> Left (BadBech32 file line bech32)
                    | otherwise -> Left (BadBech32 file line bech32)

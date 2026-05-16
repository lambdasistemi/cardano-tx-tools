{- |
Module      : Cardano.Tx.Sign.Hex
Description : Hex / key-hash decode helpers shared by tx-sign modules
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Pure helpers reused across the witness and vault modules.
-}
module Cardano.Tx.Sign.Hex (
    decodeHexBytes,
    decodeHexBytesAny,
    parseWitnessKeyHashHex,
    mkHash28,
) where

import Cardano.Crypto.Hash.Class (
    Hash,
    HashAlgorithm,
    hashFromBytes,
 )
import Cardano.Ledger.Hashes (KeyHash (..))
import Cardano.Ledger.Keys (KeyRole (..))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE

-- | Decode hex with an exact byte-length expectation.
decodeHexBytes ::
    Int -> Text -> Either String ByteString
decodeHexBytes expected t =
    case B16.decode (TE.encodeUtf8 t) of
        Right bs
            | BS.length bs == expected -> Right bs
            | otherwise ->
                Left
                    ( "expected "
                        <> show expected
                        <> " bytes, got "
                        <> show (BS.length bs)
                    )
        Left e -> Left ("hex decode: " <> e)

-- | Decode hex without a byte-length expectation.
decodeHexBytesAny :: Text -> Either String ByteString
decodeHexBytesAny t =
    case B16.decode (TE.encodeUtf8 t) of
        Right bs -> Right bs
        Left e -> Left ("hex decode: " <> e)

{- | Parse a 28-byte hex into a 'KeyHash' under the 'Guard' role used
for transaction required signers.
-}
parseWitnessKeyHashHex ::
    Text -> Either String (KeyHash Guard)
parseWitnessKeyHashHex t = do
    bs <- decodeHexBytes 28 t
    Right (KeyHash (mkHash28 bs))

mkHash28 :: (HashAlgorithm h) => ByteString -> Hash h a
mkHash28 = fromJust . hashFromBytes

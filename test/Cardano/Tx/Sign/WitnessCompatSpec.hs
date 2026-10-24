{- |
Module      : Cardano.Tx.Sign.WitnessCompatSpec
Description : Characterization guard for existing CardanoCliSKey error text

Fence-expanded per the #181 upstream pure-signing-core parent ruling: this
spec is the first regression guard that has ever existed over
"Cardano.Tx.Sign.Witness"'s payment-key decode error text (confirmed by
navigator review — no @test\/Cardano\/Tx\/Sign\/@ directory existed before
this file). Every expected string below was transcribed as a literal by
directly exercising the unmodified base commit
@7bfe95bf5ef3bfa846e62bcae94cf377b66ad0d0@ through 'cardanoCliSigningKeyHash'
via a bounded @cabal repl@ session (not computed from any refactored code),
per Opus navigator REVIEW-002 condition C1. It must pass green here, against
the pre-carve-out 'Witness.hs', before that module is touched, and again
after.

Only four of the five documented failure triggers are behaviorally
reachable through the decoder: the fifth (\"could not decode Ed25519
signing key bytes\", the @rawDeserialiseSignKeyDSIGN = Nothing@ branch) is
dead code under the current Ed25519 DSIGN algorithm —
'Cardano.Tx.Sign.Core.decode32ByteCborBytestring' already guarantees exactly
32 bytes reach it, and 'rawDeserialiseSignKeyDSIGN' succeeds for any 32-byte
input at this algorithm (independently confirmed: an all-zero 32-byte key
decodes to a real key hash, not a decode failure). Per Opus navigator
C1-RULING-001, row 5 is instead pinned as a **renderer characterization** —
it exercises the real, exported 'renderTxWitnessError' on the real, exported
'TxWitnessMalformedSigningKey' constructor, labelled explicitly as a
renderer pin rather than a decoder trigger — plus three **boundary rows**
that make the 32-byte/@5820@-prefix guard a falsifiable, enforced
invariant: if the carve-out ever loosens that guard, one of these three
starts rendering row 5's text where row 4's used to, and this spec goes
red.

Nine rows total: the four reachable decoder triggers, the row 5 renderer
pin, the three boundary rows, and a ninth — non-object JSON input (e.g.
@Null@) — added per NOTE-009. Row 9 protects the least obvious invariant in
the whole carve-out: 'Cardano.Tx.Sign.Core.decodePaymentSigningKey' parses
with @withObject \"SigningKeyEnvelope\"@, the exact legacy Aeson object
label, not its own record's name — Aeson embeds that label verbatim in a
non-object parse error, so a future "cleanup" that renames the label to
match the new record would silently change this operator-visible string.
Row 9 is what would catch that.
-}
module Cardano.Tx.Sign.WitnessCompatSpec (spec) where

import Cardano.Tx.Sign.Witness (
    TxWitnessError (TxWitnessMalformedSigningKey),
    cardanoCliSigningKeyHash,
    renderTxWitnessError,
 )
import Data.Aeson (Value (Null), object, (.=))
import Data.Text (Text)
import Test.Hspec (Spec, describe, it, shouldBe)

envelopeType :: Text
envelopeType = "PaymentSigningKeyShelley_ed25519"

{- | A well-formed 34-byte @5820@-prefixed payload, so decode/type failures
can be isolated without tripping the length guard first.
-}
wellFormedKeyHex :: Text
wellFormedKeyHex =
    "58200000000000000000000000000000000000000000000000000000000000000000"

spec :: Spec
spec = describe "cardanoCliSigningKeyHash error text (pre-existing, characterized before #181's carve-out)" $ do
    it "row 1: missing \"type\" field renders the pre-existing aeson-shape message" $
        renderResult (object ["cborHex" .= wellFormedKeyHex])
            `shouldBe` "malformed signing key material: Error in $: key \"type\" not found"

    it "row 2: unsupported envelope type renders the pre-existing unsupported-source message" $
        renderResult
            ( object
                [ "type" .= ("PaymentExtendedSigningKeyShelley_ed25519bip32" :: Text)
                , "cborHex" .= wellFormedKeyHex
                ]
            )
            `shouldBe` "unsupported signing source: cardano-cli key envelope type PaymentExtendedSigningKeyShelley_ed25519bip32"

    it "row 3: malformed hex renders the pre-existing hex-decode message" $
        renderResult (object ["type" .= envelopeType, "cborHex" .= ("zz" :: Text)])
            `shouldBe` "malformed signing key material: hex decode: invalid character at offset: 0"

    it "row 4: wrong-length key bytes render the pre-existing length message" $
        renderResult (object ["type" .= envelopeType, "cborHex" .= ("00112233" :: Text)])
            `shouldBe` "malformed signing key material: expected a 32-byte CBOR bytestring signing key"

    it "row 5 (renderer pin, not a decoder trigger): the dead-code Ed25519-decode-failure message renders unchanged" $
        renderTxWitnessError (TxWitnessMalformedSigningKey "could not decode Ed25519 signing key bytes")
            `shouldBe` "malformed signing key material: could not decode Ed25519 signing key bytes"

    it "boundary: a bare 32-byte payload with no 0x5820 prefix still trips the length guard, not the dead branch" $
        renderResult
            ( object
                [ "type" .= envelopeType
                , "cborHex" .= ("0000000000000000000000000000000000000000000000000000000000000000" :: Text)
                ]
            )
            `shouldBe` "malformed signing key material: expected a 32-byte CBOR bytestring signing key"

    it "boundary: a 34-byte payload with the wrong prefix 0x5821 still trips the length guard, not the dead branch" $
        renderResult
            ( object
                [ "type" .= envelopeType
                , "cborHex" .= ("58210000000000000000000000000000000000000000000000000000000000000000" :: Text)
                ]
            )
            `shouldBe` "malformed signing key material: expected a 32-byte CBOR bytestring signing key"

    it "boundary: a 35-byte 0x5820 payload still trips the length guard, not the dead branch" $
        renderResult
            ( object
                [ "type" .= envelopeType
                , "cborHex"
                    .= ( "5820000000000000000000000000000000000000000000000000000000000000000000" ::
                            Text
                       )
                ]
            )
            `shouldBe` "malformed signing key material: expected a 32-byte CBOR bytestring signing key"

    it "row 9: a non-object JSON value renders the pre-existing Aeson object-label message" $
        renderResult Null
            `shouldBe` "malformed signing key material: Error in $: parsing SigningKeyEnvelope failed, expected Object, but encountered Null"
  where
    renderResult value =
        either renderTxWitnessError (const "<unexpected success>") (cardanoCliSigningKeyHash value)

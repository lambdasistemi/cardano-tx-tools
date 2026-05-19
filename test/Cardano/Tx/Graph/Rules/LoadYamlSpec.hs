{- |
Module      : Cardano.Tx.Graph.Rules.LoadYamlSpec
Description : T002 unit tests for the YAML entities parser.
License     : Apache-2.0

Covers the in-memory @'parseRulesYamlText' :: ByteString -> Either
'RulesLoadError' ['EntityDecl']@ path: the @from-address@, @script@,
and @asset@ entity shapes, the six Conway base/enterprise address
classes (the cross-product of payment ∈ {Key,Script} and
stake ∈ {Key,Script,enterprise}), the slugify algorithm
(snake_case with @[^a-z0-9]@ → @_@, repeat collapse, end-trim) and
the two slug edge-cases (empty slug + leading-digit slug).

Per Q-001/A-001 the slug is used for both the entity IRI local-part
and the bnode prefix; the test only inspects the slug field — the
Turtle serializer is T003's responsibility.
-}
module Cardano.Tx.Graph.Rules.LoadYamlSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
    parseRulesYamlText,
 )

import Cardano.Crypto.Hash (Hash, HashAlgorithm, hashFromBytes)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (Mainnet))
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefBase, StakeRefNull),
 )
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..))
import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "Cardano.Tx.Graph.Rules.Load.parseRulesYamlText (T002)" $ do
    describe "happy path" $ do
        it "returns [] for an empty YAML document" $ do
            parseRulesYamlText "" `shouldBe` Right []

        it "returns [] when the document has no entities: key" $ do
            parseRulesYamlText "blueprints: []\n" `shouldBe` Right []

        it "parses a single from-address (PaymentKey + StakeKey)" $ do
            -- A real mainnet base-address from the rewrite-redesign
            -- fixture-02 corpus. The decoded payment / stake hashes
            -- are the ground-truth bytes the ledger decoder produces
            -- (the fixture's expected.ttl pre-T002 used artisanal,
            -- unrelated bytes; we ignore that and trust the decoder).
            let yaml =
                    "entities:\n\
                    \  - name: alice\n\
                    \    from-address: "
                        <> aliceBech32Mainnet
                        <> "\n"
            parseRulesYamlText (TextEncoding.encodeUtf8 yaml)
                `shouldBe` Right
                    [ EntityDecl
                        { entityName = "alice"
                        , entitySlug = "alice"
                        , entityIdentifiers =
                            [ EntityIdentifier
                                PaymentKey
                                "8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1"
                            , EntityIdentifier
                                StakeKey
                                "4c7889c658ef4f491a34cf79c35a2e0fe6b0d1b0a856fb9580f2d9c3"
                            ]
                        }
                    ]

        it "parses a single script (PaymentScript) entity" $ do
            let yaml =
                    "entities:\n\
                    \  - name: my-script\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            parseRulesYamlText yaml
                `shouldBe` Right
                    [ EntityDecl
                        { entityName = "my-script"
                        , entitySlug = "my_script"
                        , entityIdentifiers =
                            [ EntityIdentifier
                                PaymentScript
                                "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"
                            ]
                        }
                    ]

        it "parses an asset shape — bytesHex = policy ++ hex(ascii(name))" $ do
            let yaml =
                    "entities:\n\
                    \  - name: usdm\n\
                    \    asset: { policy: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad, name: USDM }\n"
            -- "USDM" → 55 53 44 4d (4 bytes ASCII = 8 hex chars).
            parseRulesYamlText yaml
                `shouldBe` Right
                    [ EntityDecl
                        { entityName = "usdm"
                        , entitySlug = "usdm"
                        , entityIdentifiers =
                            [ EntityIdentifier
                                AssetClass
                                "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad5553444d"
                            ]
                        }
                    ]

        it "parses multiple entities in source order" $ do
            let yaml =
                    "entities:\n\
                    \  - name: alpha\n\
                    \    script: 0123456789abcdef0123456789abcdef0123456789abcdef01234567\n\
                    \  - name: beta\n\
                    \    asset: { policy: aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc, name: MEME }\n"
            parseRulesYamlText yaml
                `shouldBe` Right
                    [ EntityDecl
                        "alpha"
                        "alpha"
                        [ EntityIdentifier
                            PaymentScript
                            "0123456789abcdef0123456789abcdef0123456789abcdef01234567"
                        ]
                    , EntityDecl
                        "beta"
                        "beta"
                        [ EntityIdentifier
                            AssetClass
                            "aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc4d454d45"
                        ]
                    ]

    describe "six Conway address classes (FR-005)" $ do
        it "PaymentKey + StakeKey (base, key+key)" $
            decomposeAddrShouldBe
                (mkAddr (KeyHashObj keyHashPayment) (StakeRefBase (KeyHashObj keyHashStake)))
                [ EntityIdentifier PaymentKey paymentKeyBytesHex
                , EntityIdentifier StakeKey stakeKeyBytesHex
                ]
        it "PaymentKey + StakeScript (base, key+script)" $
            decomposeAddrShouldBe
                (mkAddr (KeyHashObj keyHashPayment) (StakeRefBase (ScriptHashObj scriptHashStake)))
                [ EntityIdentifier PaymentKey paymentKeyBytesHex
                , EntityIdentifier StakeScript scriptStakeBytesHex
                ]
        it "PaymentScript + StakeKey (base, script+key)" $
            decomposeAddrShouldBe
                (mkAddr (ScriptHashObj scriptHashPayment) (StakeRefBase (KeyHashObj keyHashStake)))
                [ EntityIdentifier PaymentScript scriptPaymentBytesHex
                , EntityIdentifier StakeKey stakeKeyBytesHex
                ]
        it "PaymentScript + StakeScript (base, script+script)" $
            decomposeAddrShouldBe
                (mkAddr (ScriptHashObj scriptHashPayment) (StakeRefBase (ScriptHashObj scriptHashStake)))
                [ EntityIdentifier PaymentScript scriptPaymentBytesHex
                , EntityIdentifier StakeScript scriptStakeBytesHex
                ]
        it "PaymentKey, enterprise (no stake)" $
            decomposeAddrShouldBe
                (mkAddr (KeyHashObj keyHashPayment) StakeRefNull)
                [EntityIdentifier PaymentKey paymentKeyBytesHex]
        it "PaymentScript, enterprise (no stake)" $
            decomposeAddrShouldBe
                (mkAddr (ScriptHashObj scriptHashPayment) StakeRefNull)
                [EntityIdentifier PaymentScript scriptPaymentBytesHex]

    describe "slug edge cases" $ do
        it "empty slug after normalization → EntityNameSlugEmpty" $ do
            let yaml =
                    "entities:\n\
                    \  - name: \"---\"\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            case parseRulesYamlText yaml of
                Left (EntityNameSlugEmpty _ _ original) ->
                    original `shouldBe` "---"
                other ->
                    fail $ "expected EntityNameSlugEmpty, got: " <> show other

        it "leading-digit slug → EntityNameSlugLeadingDigit" $ do
            let yaml =
                    "entities:\n\
                    \  - name: 9lives\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            case parseRulesYamlText yaml of
                Left (EntityNameSlugLeadingDigit _ _ original) ->
                    original `shouldBe` "9lives"
                other ->
                    fail $ "expected EntityNameSlugLeadingDigit, got: " <> show other

        it "rewrites dots and dashes to underscores; collapses runs" $ do
            let yaml =
                    "entities:\n\
                    \  - name: amaru-treasury.network__compliance\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            case parseRulesYamlText yaml of
                Right [decl] ->
                    entitySlug decl `shouldBe` "amaru_treasury_network_compliance"
                other ->
                    fail $ "expected single Right decl, got: " <> show other

    describe "structural errors" $ do
        it "rejects an entity with zero identifier shapes (no from-address/script/asset)" $ do
            let yaml =
                    "entities:\n\
                    \  - name: orphan\n"
            parseRulesYamlText yaml
                `shouldSatisfy` isEntityZeroIdentifiers

isEntityZeroIdentifiers :: Either RulesLoadError [EntityDecl] -> Bool
isEntityZeroIdentifiers (Left (EntityZeroIdentifiers _)) = True
isEntityZeroIdentifiers _ = False

----------------------------------------------------------------------
-- Address synthesis helpers
----------------------------------------------------------------------

{- | Construct a Cardano mainnet 'Addr' and bech32-encode it under
@addr@ HRP, then feed it through 'parseRulesYamlText' as a
@from-address:@ entity called @synth@. Asserts the produced
'entityIdentifiers' match the expected list.
-}
decomposeAddrShouldBe :: Addr -> [EntityIdentifier] -> IO ()
decomposeAddrShouldBe addr expected = do
    let bech32 = encodeMainnetAddr addr
        yaml =
            "entities:\n\
            \  - name: synth\n\
            \    from-address: "
                <> bech32
                <> "\n"
    parseRulesYamlText (TextEncoding.encodeUtf8 yaml)
        `shouldBe` Right
            [EntityDecl "synth" "synth" expected]

encodeMainnetAddr :: Addr -> Text
encodeMainnetAddr a =
    let hrp = either (error . show) id $ Bech32.humanReadablePartFromText "addr"
        dataPart = Bech32.dataPartFromBytes (serialiseAddr a)
     in Bech32.encodeLenient hrp dataPart

mkAddr :: Credential payment -> StakeReference -> Addr
mkAddr p = Addr Mainnet (unsafeCoercePayment p)

{- | The 'Addr' constructor pins payment to @Credential Payment@; the
KeyRole phantom is irrelevant at the byte level, so we coerce.
-}
unsafeCoercePayment :: Credential payment -> Credential payment'
unsafeCoercePayment (KeyHashObj (KeyHash h)) = KeyHashObj (KeyHash h)
unsafeCoercePayment (ScriptHashObj sh) = ScriptHashObj sh

----------------------------------------------------------------------
-- Fixed test bytes
----------------------------------------------------------------------

-- | A 28-byte ed25519 verification-key hash (payment role).
paymentKeyBytesHex :: Text
paymentKeyBytesHex = "601f58e4436698104adbbda7bc9d8f3f10e9e49652f9799d6c63aeda"

-- | A 28-byte ed25519 verification-key hash (stake role).
stakeKeyBytesHex :: Text
stakeKeyBytesHex = "80226c84b26fe1a280649d819757ff2ffaec51adca5a3780356c05bf"

-- | A 28-byte payment-script hash.
scriptPaymentBytesHex :: Text
scriptPaymentBytesHex = "32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d"

{- | A 28-byte stake-script hash (chosen distinct from the payment one
so the test surface confirms the loader does not confuse the two).
-}
scriptStakeBytesHex :: Text
scriptStakeBytesHex = "9100eb83504e21b27158c84a9f89ecea2c52ee6d5da6699aa42ea906"

keyHashPayment :: KeyHash kr
keyHashPayment = KeyHash (mk28 paymentKeyBytesHex)

keyHashStake :: KeyHash kr
keyHashStake = KeyHash (mk28 stakeKeyBytesHex)

scriptHashPayment :: ScriptHash
scriptHashPayment = ScriptHash (mk28 scriptPaymentBytesHex)

scriptHashStake :: ScriptHash
scriptHashStake = ScriptHash (mk28 scriptStakeBytesHex)

mk28 :: (HashAlgorithm h) => Text -> Hash h a
mk28 hex =
    case Base16.decode (TextEncoding.encodeUtf8 hex) of
        Right bs
            | BS.length bs == 28 -> fromJust (hashFromBytes bs)
        _ -> error ("mk28: expected 28-byte hex, got: " <> Text.unpack hex)

{- | The well-known fixture-02 alice mainnet base address (PaymentKey +
StakeKey).
-}
aliceBech32Mainnet :: Text
aliceBech32Mainnet =
    "addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz"

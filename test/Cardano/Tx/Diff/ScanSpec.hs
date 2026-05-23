{- |
Module      : Cardano.Tx.Diff.ScanSpec
Description : Unit tests for the Cardanoscan URL mapper (#88, slice S1).

Pins the per-variant URL shape for every 'InspectLeaf' constructor on
'Mainnet' and on 'Preprod', and runs a QuickCheck round-trip
property: every 'cardanoscanUrl' output has the @https://@ scheme,
the expected per-network host, and a non-empty path with no
internal whitespace.
-}
module Cardano.Tx.Diff.ScanSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Hspec
import Test.QuickCheck (
    Gen,
    counterexample,
    elements,
    forAll,
    listOf1,
    property,
 )

import Cardano.Tx.Diff.Scan (
    InspectLeaf (..),
    Network (..),
    UnsupportedNetworkMagic (..),
    Url (..),
    cardanoscanUrl,
    parseNetworkMagic,
 )

spec :: Spec
spec = describe "Cardano.Tx.Diff.Scan" $ do
    describe "parseNetworkMagic" $ do
        it "maps the mainnet magic to Mainnet" $
            parseNetworkMagic 764824073 `shouldBe` Right Mainnet
        it "maps the preprod magic to Preprod" $
            parseNetworkMagic 1 `shouldBe` Right Preprod
        it "maps the preview magic to Preview" $
            parseNetworkMagic 2 `shouldBe` Right Preview
        it "rejects unsupported magics" $
            parseNetworkMagic 12345
                `shouldBe` Left (UnsupportedNetworkMagic 12345)

    describe "cardanoscanUrl — mainnet goldens" $ do
        it "renders InspectTxHash as /transaction/<hash>" $
            getUrl (cardanoscanUrl Mainnet (InspectTxHash txHash))
                `shouldBe` "https://cardanoscan.io/transaction/" <> txHash
        it "renders InspectTxIn as /transaction/<producer-hash>" $
            getUrl (cardanoscanUrl Mainnet (InspectTxIn txHash 7))
                `shouldBe` "https://cardanoscan.io/transaction/" <> txHash
        it "renders InspectPaymentAddress as /address/<bech32>" $
            getUrl (cardanoscanUrl Mainnet (InspectPaymentAddress paymentAddr))
                `shouldBe` "https://cardanoscan.io/address/" <> paymentAddr
        it "renders InspectStakeAddress as /stakekey/<bech32>" $
            getUrl (cardanoscanUrl Mainnet (InspectStakeAddress stakeAddr))
                `shouldBe` "https://cardanoscan.io/stakekey/" <> stakeAddr
        it "renders InspectPolicyId as /tokenPolicy/<hex>" $
            getUrl (cardanoscanUrl Mainnet (InspectPolicyId policyId))
                `shouldBe` "https://cardanoscan.io/tokenPolicy/" <> policyId
        it "renders InspectAssetFingerprint as /token/<fingerprint>" $
            getUrl (cardanoscanUrl Mainnet (InspectAssetFingerprint fingerprint))
                `shouldBe` "https://cardanoscan.io/token/" <> fingerprint

    describe "cardanoscanUrl — preprod host" $ do
        it "uses the preprod.cardanoscan.io host" $
            getUrl (cardanoscanUrl Preprod (InspectTxHash txHash))
                `shouldBe` "https://preprod.cardanoscan.io/transaction/" <> txHash

    describe "cardanoscanUrl — preview host" $ do
        it "uses the preview.cardanoscan.io host" $
            getUrl (cardanoscanUrl Preview (InspectTxHash txHash))
                `shouldBe` "https://preview.cardanoscan.io/transaction/" <> txHash

    describe "URL well-formedness property" $
        it "every (Network, InspectLeaf) has scheme+host+path" $
            property $
                forAll genNetwork $ \network ->
                    forAll genInspectLeaf $ \leaf ->
                        let url = getUrl (cardanoscanUrl network leaf)
                            expectedPrefix = case network of
                                Mainnet -> "https://cardanoscan.io/"
                                Preprod -> "https://preprod.cardanoscan.io/"
                                Preview -> "https://preview.cardanoscan.io/"
                            afterPrefix = Text.stripPrefix expectedPrefix url
                         in counterexample
                                ("URL did not match prefix " <> Text.unpack expectedPrefix <> ": " <> Text.unpack url)
                                ( case afterPrefix of
                                    Nothing -> False
                                    Just rest ->
                                        not (Text.null rest)
                                            && not
                                                ( Text.any
                                                    (`elem` (" \t\n\r" :: String))
                                                    url
                                                )
                                )

txHash :: Text
txHash = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

paymentAddr :: Text
paymentAddr =
    "addr1qy4w9p3uy3l4rgw7zvz9pq2c9zsh8tj4q3yxg7tk6q4cv4u8d5xt6jc5fkz3z2pll9w5"
        <> "wmlsqxd2nmrft7y8a37u2psk5e6qj"

stakeAddr :: Text
stakeAddr = "stake1u9d5xt6jc5fkz3z2pll9w5wmlsqxd2nmrft7y8a37u2psksugfeyq"

policyId :: Text
policyId = "8b05e87a51c1d4a0fa888d2bb14dbc25e8c343ea379a171b63aa84a0"

fingerprint :: Text
fingerprint = "asset1qjsm99q3dqzd97jc63qgsxgd2wsuym4ywf8u72"

genNetwork :: Gen Network
genNetwork = elements [Mainnet, Preprod, Preview]

genInspectLeaf :: Gen InspectLeaf
genInspectLeaf = do
    let hexChar = elements (['0' .. '9'] <> ['a' .. 'f'])
        hexN n = Text.pack <$> mapM (const hexChar) [1 .. n :: Int]
        bech32Text prefix =
            Text.pack . (prefix <>)
                <$> listOf1 (elements (['0' .. '9'] <> ['a' .. 'z']))
        ixGen :: Gen Word64
        ixGen = elements [0, 1, 2, 7, 42, 1000, 65535]
    elements [0 :: Int .. 5]
        >>= \case
            0 -> InspectTxHash <$> hexN 64
            1 -> InspectTxIn <$> hexN 64 <*> ixGen
            2 -> InspectPaymentAddress <$> bech32Text "addr1"
            3 -> InspectStakeAddress <$> bech32Text "stake1"
            4 -> InspectPolicyId <$> hexN 56
            _ -> InspectAssetFingerprint <$> bech32Text "asset1"

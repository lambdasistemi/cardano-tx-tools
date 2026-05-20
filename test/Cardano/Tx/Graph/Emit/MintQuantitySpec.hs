{- |
Module      : Cardano.Tx.Graph.Emit.MintQuantitySpec
Description : Mint cluster signed-quantity invariant (T106 / S5 / D-004).
License     : Apache-2.0

Asserts the T106 / S5 invariant that every body @Mint@ entry
emits the canonical signed-quantity shape:

@
_:mintN a cardano:Mint ;
  cardano:mintsAsset _:assetN ;
  cardano:quantity \<signed-integer\> .

_:assetN a cardano:Asset ;
  cardano:hasIdentifier _:asset_\<bytes\> .
@

The earlier @cardano:hasPolicy _:policyN@ + @cardano:hasAsset
_:assetN@ pair plus a separate @_:policyN a cardano:Policy@ block
must not appear inside any @Mint@ section. The Asset block
remains (carries @hasIdentifier@), so @# Mint @-section
@cardano:Asset@ count is preserved.

Per the kmaps vocab, @cardano:quantity@ has @rdfs:range xsd:integer@,
so negative quantities (burns) are emitted as plain Turtle
integer literals like @-5@.

The spec runs the body emitter against every rewrite-redesign
fixture and asserts the per-fixture mint count plus the absence
of the legacy predicates @cardano:hasPolicy@ + the bare
@cardano:hasAsset @ token inside Mint sections.
-}
module Cardano.Tx.Graph.Emit.MintQuantitySpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Lens.Micro ((^.))

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (mintTxBodyL)
import Cardano.Ledger.Mary.Value (MultiAsset (..))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl,
    RulesLoadResult (..),
    loadRulesFile,
    rulesEntities,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.S01_AmaruTreasurySwap qualified as S01
import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02
import Fixtures.RewriteRedesign.S03_MultiAssetTransfer qualified as S03
import Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap qualified as S04
import Fixtures.RewriteRedesign.S05_WithdrawalScriptStake qualified as S05
import Fixtures.RewriteRedesign.S06_StakePoolDelegation qualified as S06
import Fixtures.RewriteRedesign.S07_VoteDelegation qualified as S07
import Fixtures.RewriteRedesign.S08_ContingencyDisburse qualified as S08
import Fixtures.RewriteRedesign.S09_MpfsFactsRequest qualified as S09
import Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal qualified as S10
import Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal qualified as S11

import Test.Hspec (Spec, describe, it, runIO, shouldBe)

-- | The 11 rewrite-redesign fixtures, in slug order.
allFixtures :: [(String, ConwayTx)]
allFixtures =
    [ ("01-amaru-treasury-swap", S01.tx)
    , ("02-alice-bob-ada", S02.tx)
    , ("03-multi-asset-transfer", S03.tx)
    , ("04-mint-spend-script-overlap", S04.tx)
    , ("05-withdrawal-script-stake", S05.tx)
    , ("06-stake-pool-delegation", S06.tx)
    , ("07-vote-delegation", S07.tx)
    , ("08-contingency-disburse", S08.tx)
    , ("09-mpfs-facts-request", S09.tx)
    , ("10-governance-treasury-withdrawal", S10.tx)
    , ("11-amaru-treasury-swap-real", S11.tx)
    ]

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit mint signed quantity (T106 / S5)" $
        mapM_ fixtureSpec allFixtures

fixtureSpec :: (String, ConwayTx) -> Spec
fixtureSpec (slug, tx) = describe slug $ do
    let dir = "test/fixtures/rewrite-redesign" </> slug
        rulesPath = dir </> "rules.yaml"
    entities <- runIO (loadEntities rulesPath)
    let bytes = case emit tx emptyUtxo entities of
            Right g -> serialize Turtle slug g
            Left _ -> BS.empty
        body = tx ^. bodyTxL
        MultiAsset mintPolicies = body ^. mintTxBodyL
        mintEntries =
            [ (policyId, assetName, quantity)
            | (policyId, assets) <- Map.toAscList mintPolicies
            , (assetName, quantity) <- Map.toAscList assets
            ]
        nMints = length mintEntries
        mintSectionBytes = BS8.concat (mintSectionLines bytes)
    it "cardano:Mint subject-block count matches body mint entries" $
        countOccurrences "a cardano:Mint" mintSectionBytes `shouldBe` nMints
    if nMints > 0
        then do
            it "emits cardano:mintsAsset + cardano:quantity inside Mint sections" $ do
                countOccurrences "cardano:mintsAsset" mintSectionBytes
                    `shouldBe` nMints
                countOccurrences "cardano:quantity" mintSectionBytes
                    `shouldBe` nMints
            it "does NOT emit cardano:hasPolicy inside Mint sections" $
                countOccurrences "cardano:hasPolicy" mintSectionBytes
                    `shouldBe` 0
            it "does NOT emit bare cardano:hasAsset edge inside Mint sections" $
                -- The needle " cardano:hasAsset " (leading + trailing space)
                -- distinguishes the legacy mint-cluster edge from the
                -- T104 multi-asset @cardano:hasAssetValue@ predicate, which
                -- shares the @cardano:hasAsset@ prefix.
                countOccurrences " cardano:hasAsset " mintSectionBytes
                    `shouldBe` 0
            it "does NOT emit a cardano:Policy subject block inside Mint sections" $
                countOccurrences "a cardano:Policy" mintSectionBytes
                    `shouldBe` 0
            it "emits the per-mint cardano:Asset block (hasIdentifier carrier)" $
                countOccurrences "a cardano:Asset" mintSectionBytes
                    `shouldBe` nMints
        else it "no Mint section is emitted when the body mints nothing" $ do
            countOccurrences "# Mint " bytes `shouldBe` 0
            countOccurrences "a cardano:Mint" bytes `shouldBe` 0
            countOccurrences "cardano:mintsAsset" bytes `shouldBe` 0
            countOccurrences "cardano:hasPolicy" bytes `shouldBe` 0

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

loadEntities :: FilePath -> IO [EntityDecl]
loadEntities path = do
    result <- loadRulesFile path
    case result of
        Right res -> pure (rulesEntities res)
        Left err ->
            fail $
                "MintQuantitySpec.loadEntities: "
                    <> path
                    <> ": "
                    <> show err

{- | Return the byte lines that live inside @# Mint @ sections
only. Mirrors @MultiAssetListSpec.outputSectionLines@.
-}
mintSectionLines :: ByteString -> [ByteString]
mintSectionLines bs = concat (collect [] [] False (BS8.lines bs))
  where
    collect ::
        [[ByteString]] ->
        [ByteString] ->
        Bool ->
        [ByteString] ->
        [[ByteString]]
    collect acc cur False [] = reverse acc <> [reverse cur | not (null cur)]
    collect acc cur True [] = reverse (reverse cur : acc)
    collect acc cur inSection (line : rest)
        | isMintHeader line =
            if inSection
                then collect (reverse cur : acc) [] True rest
                else collect acc [] True rest
        | isOtherHeader line && inSection =
            collect (reverse cur : acc) [] False rest
        | inSection = collect acc (BS8.snoc line '\n' : cur) True rest
        | otherwise = collect acc cur False rest

    isMintHeader = BS8.isPrefixOf "# Mint "
    isOtherHeader l =
        BS8.isPrefixOf "# " l && not (isMintHeader l)

countOccurrences :: ByteString -> ByteString -> Int
countOccurrences needle haystack
    | BS.null needle = 0
    | otherwise =
        let (_, rest) = BS.breakSubstring needle haystack
         in if BS.null rest
                then 0
                else 1 + countOccurrences needle (BS.drop (BS.length needle) rest)

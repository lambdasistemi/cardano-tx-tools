{- |
Module      : Cardano.Tx.Graph.Emit.WithdrawalCanonicalSpec
Description : Withdrawal canonical-name invariant (T106 / S5 / D-005).
License     : Apache-2.0

Asserts the T106 / S5 invariant that every body @Withdrawal@
cluster emits the canonical kmaps shape:

@
_:withdrawalN a cardano:Withdrawal ;
  cardano:withdrawalAccount _:rewardAcctN ;
  cardano:lovelace \<amount\> .
@

The #58-inherited @cardano:onCredential@ + @cardano:withAmount@
pair must not appear inside any @Withdrawal@ section. The
@cardano:onCredential@ term may still appear in cert clusters
(stake / vote delegation) — that scope is owned by T107 and is
not checked here.

The spec runs the body emitter against every rewrite-redesign
fixture, then asserts the count of @cardano:Withdrawal@ subject
blocks matches the body's withdrawal-map size and that the
canonical predicates appear inside @# Withdrawal @ sections
exactly when the body carries at least one withdrawal.
-}
module Cardano.Tx.Graph.Emit.WithdrawalCanonicalSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Lens.Micro ((^.))

import Cardano.Ledger.Address (Withdrawals (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (withdrawalsTxBodyL)

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
    describe "Cardano.Tx.Graph.Emit withdrawal canonical names (T106 / S5)" $
        mapM_ fixtureSpec allFixtures

fixtureSpec :: (String, ConwayTx) -> Spec
fixtureSpec (slug, tx) = describe slug $ do
    let dir = "test/fixtures/rewrite-redesign" </> slug
        rulesPath = dir </> "rules.yaml"
    entities <- runIO (loadEntities rulesPath)
    let bytes = case emit tx emptyUtxo entities [] of
            Right g -> serialize Turtle slug g
            Left _ -> BS.empty
        body = tx ^. bodyTxL
        Withdrawals wmap = body ^. withdrawalsTxBodyL
        nWithdrawals = Map.size wmap
        withdrawalSectionBytes = BS8.concat (withdrawalSectionLines bytes)
    it "cardano:Withdrawal subject-block count matches body withdrawal map" $
        countOccurrences "a cardano:Withdrawal" withdrawalSectionBytes
            `shouldBe` nWithdrawals
    if nWithdrawals > 0
        then do
            it "emits cardano:withdrawalAccount + cardano:lovelace inside Withdrawal sections" $ do
                countOccurrences "cardano:withdrawalAccount" withdrawalSectionBytes
                    `shouldBe` nWithdrawals
                countOccurrences "cardano:lovelace" withdrawalSectionBytes
                    `shouldBe` nWithdrawals
            it "does NOT emit cardano:onCredential inside Withdrawal sections" $
                countOccurrences "cardano:onCredential" withdrawalSectionBytes
                    `shouldBe` 0
            it "does NOT emit cardano:withAmount anywhere" $
                countOccurrences "cardano:withAmount" bytes `shouldBe` 0
        else it "no Withdrawal section is emitted when the body carries no withdrawals" $ do
            countOccurrences "# Withdrawal " bytes `shouldBe` 0
            countOccurrences "cardano:Withdrawal" bytes `shouldBe` 0
            countOccurrences "cardano:withdrawalAccount" bytes `shouldBe` 0
            countOccurrences "cardano:withAmount" bytes `shouldBe` 0

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
                "WithdrawalCanonicalSpec.loadEntities: "
                    <> path
                    <> ": "
                    <> show err

{- | Return the byte lines that live inside @# Withdrawal @
sections only. Mirrors @MultiAssetListSpec.outputSectionLines@.
-}
withdrawalSectionLines :: ByteString -> [ByteString]
withdrawalSectionLines bs = concat (collect [] [] False (BS8.lines bs))
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
        | isWithdrawalHeader line =
            if inSection
                then collect (reverse cur : acc) [] True rest
                else collect acc [] True rest
        | isOtherHeader line && inSection =
            collect (reverse cur : acc) [] False rest
        | inSection = collect acc (BS8.snoc line '\n' : cur) True rest
        | otherwise = collect acc cur False rest

    isWithdrawalHeader = BS8.isPrefixOf "# Withdrawal "
    isOtherHeader l =
        BS8.isPrefixOf "# " l && not (isWithdrawalHeader l)

countOccurrences :: ByteString -> ByteString -> Int
countOccurrences needle haystack
    | BS.null needle = 0
    | otherwise =
        let (_, rest) = BS.breakSubstring needle haystack
         in if BS.null rest
                then 0
                else 1 + countOccurrences needle (BS.drop (BS.length needle) rest)

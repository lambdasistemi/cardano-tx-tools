{- |
Module      : Cardano.Tx.Graph.Emit.MultiAssetListSpec
Description : Per-output multi-asset RDF list invariant (T104 / S3).
License     : Apache-2.0

Asserts the T104 / S3 invariant that outputs carrying a
non-empty multi-asset value emit the RDF-list shape per A-001:

@
_:outputN cardano:hasAssetValue _:outputMultiAssetN .

_:outputMultiAssetN rdf:first _:assetEntry_outputN_1 ;
                    rdf:rest _:outputMultiAssetN_tail1 .

_:assetEntry_outputN_1 a cardano:Asset ;
  cardano:hasIdentifier _:asset_\<bytes\> ;
  cardano:quantity 100 .
...

_:outputMultiAssetN_tailM rdf:first _:assetEntry_outputN_\<M+1\> ;
                          rdf:rest rdf:nil .
@

The list-head binding predicate is @cardano:hasAssetValue@
(not @cardano:mintsAsset@) per A-001: the canonical-vocab pin
declares @cardano:mintsAsset@ with @rdfs:domain cardano:Mint@,
so reusing it on an @Output@ subject would violate the domain
axiom.

Counts are asserted against the body's actual outputs (extracted
via @cardano-ledger-api@ lenses); shape primitives are asserted
against the emitted bytes. Coin-only outputs MUST NOT emit a
@cardano:hasAssetValue@ predicate (negative shape invariant —
no @rdf:nil@ orphan, no empty list head).
-}
module Cardano.Tx.Graph.Emit.MultiAssetListSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Lens.Micro ((^.))

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (valueTxOutL)
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))

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

import Test.Hspec (Spec, describe, it, runIO, shouldBe, shouldSatisfy)

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
    describe "Cardano.Tx.Graph.Emit multi-asset RDF list (T104 / S3)" $
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
        outputsMAEmptiness =
            [ isEmptyMA ma
            | txOut <- toList (body ^. outputsTxBodyL)
            , let MaryValue _ ma = txOut ^. valueTxOutL
            ]
        nonEmptyCount = length (filter not outputsMAEmptiness)
    it "cardano:hasAssetValue count in Output sections matches non-empty MA outputs" $ do
        let outSectionBytes = BS8.concat (outputSectionLines bytes)
            hasAssetValueCount =
                countOccurrences "cardano:hasAssetValue" outSectionBytes
        hasAssetValueCount `shouldBe` nonEmptyCount
    if nonEmptyCount > 0
        then it "emits RDF-list primitives (rdf:first / rdf:rest / rdf:nil) plus cardano:Asset entries" $ do
            bytes `shouldSatisfy` BS8.isInfixOf "rdf:first"
            bytes `shouldSatisfy` BS8.isInfixOf "rdf:rest"
            bytes `shouldSatisfy` BS8.isInfixOf "rdf:nil"
            bytes `shouldSatisfy` BS8.isInfixOf "a cardano:Asset"
            bytes `shouldSatisfy` BS8.isInfixOf "cardano:quantity"
        else it "no RDF-list primitives leak when all outputs are coin-only" $ do
            countOccurrences "rdf:nil" bytes `shouldBe` 0
            countOccurrences "rdf:first" bytes `shouldBe` 0
            countOccurrences "rdf:rest" bytes `shouldBe` 0
            countOccurrences "cardano:hasAssetValue" bytes `shouldBe` 0

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
                "MultiAssetListSpec.loadEntities: "
                    <> path
                    <> ": "
                    <> show err

isEmptyMA :: MultiAsset -> Bool
isEmptyMA (MultiAsset m) = Map.null m

{- | Return the byte lines that live inside Output sections only.
Used to scope @cardano:hasAssetValue@ counts to body outputs
without picking up resolved-input or resolved-collateral
sections (which T104 also extends).
-}
outputSectionLines :: ByteString -> [ByteString]
outputSectionLines bs = concat (collect [] [] False (BS8.lines bs))
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
        | isOutputHeader line =
            if inSection
                then collect (reverse cur : acc) [] True rest
                else collect acc [] True rest
        | isOtherHeader line && inSection =
            collect (reverse cur : acc) [] False rest
        | inSection = collect acc (BS8.snoc line '\n' : cur) True rest
        | otherwise = collect acc cur False rest

    isOutputHeader = BS8.isPrefixOf "# Output "
    isOtherHeader l =
        BS8.isPrefixOf "# " l && not (isOutputHeader l)

countOccurrences :: ByteString -> ByteString -> Int
countOccurrences needle haystack
    | BS.null needle = 0
    | otherwise =
        let (_, rest) = BS.breakSubstring needle haystack
         in if BS.null rest
                then 0
                else 1 + countOccurrences needle (BS.drop (BS.length needle) rest)

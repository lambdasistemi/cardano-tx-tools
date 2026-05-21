{- |
Module      : Cardano.Tx.Graph.Emit.OutputLovelaceSpec
Description : Per-output lovelace invariant (T104 / S3).
License     : Apache-2.0

Asserts the T104 / S3 invariant: every body output's
@_:outputN@ subject block carries a @cardano:lovelace
\<integer\>@ triple. Conway outputs always carry an ADA value
(even when zero), so the predicate is unconditional — pre-T104
fixtures elided it; T104 fixtures all surface it after the
@expected.ttl@ regen.

The spec also enforces that the emitted lovelace integer matches
the body output's @Coin@ value extracted directly from the
'ConwayTx' (read via @cardano-ledger-api@'s @valueTxOutL@).

Runs across all 11 rewrite-redesign fixtures — the per-fixture
output count drives the assertion arity.
-}
module Cardano.Tx.Graph.Emit.OutputLovelaceSpec (spec) where

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
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Mary.Value (MaryValue (..))

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
    describe "Cardano.Tx.Graph.Emit output lovelace (T104 / S3)" $
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
        outputCoins =
            [ coin
            | txOut <- toList (body ^. outputsTxBodyL)
            , let MaryValue (Coin coin) _ = txOut ^. valueTxOutL
            ]
    it "emits one cardano:lovelace per body output" $ do
        let lovelaceLines =
                filter (BS8.isInfixOf "cardano:lovelace") (BS8.lines bytes)
            -- Output blocks come first under "Output N" sections;
            -- resolved-input/collateral blocks may also surface
            -- lovelace. Restrict the count to OUTPUT-section blocks
            -- only by scanning between the Output section headers.
            outputSectionLines = extractOutputSectionLovelaceLines bytes
        length outputSectionLines `shouldBe` length outputCoins
        -- Sanity: every output line is well-formed.
        lovelaceLines `shouldSatisfy'` all hasIntegerOperand
    it "emitted lovelace values match the body coin amounts" $ do
        extractOutputLovelaceValues bytes `shouldBe` outputCoins

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
                "OutputLovelaceSpec.loadEntities: "
                    <> path
                    <> ": "
                    <> show err

{- | Extract the @cardano:lovelace@ predicate lines inside
@\# Output N@ sections only. Resolved-input + resolved-collateral
sections also emit @cardano:lovelace@ but only OUTPUT-section
counts must match the body's output arity.
-}
extractOutputSectionLovelaceLines :: ByteString -> [ByteString]
extractOutputSectionLovelaceLines bs =
    concat
        [ filter (BS8.isInfixOf "cardano:lovelace") sectionLines
        | sectionLines <- outputSections bs
        ]

extractOutputLovelaceValues :: ByteString -> [Integer]
extractOutputLovelaceValues bs =
    [ readIntegerOrError line
    | sectionLines <- outputSections bs
    , line <- sectionLines
    , BS8.isInfixOf "cardano:lovelace" line
    ]

outputSections :: ByteString -> [[ByteString]]
outputSections bs = sections
  where
    ls = BS8.lines bs
    -- Section header in Turtle has the shape:
    --   #
    --   # Output N
    --   #
    --   <blank>
    --   <block lines>
    --   <blank>
    --   #
    --   # Next section
    --   ...
    -- Walk left-to-right, opening a section when we see
    -- "# Output ", closing when we see the next "# " line.
    sections = collect [] [] False ls

    collect :: [[ByteString]] -> [ByteString] -> Bool -> [ByteString] -> [[ByteString]]
    collect acc _cur False [] = reverse acc
    collect acc cur True [] = reverse (reverse cur : acc)
    collect acc cur inSection (line : rest)
        | isOutputHeader line =
            if inSection
                then collect (reverse cur : acc) [] True rest
                else collect acc [] True rest
        | isOtherHeader line && inSection =
            collect (reverse cur : acc) [] False rest
        | inSection = collect acc (line : cur) True rest
        | otherwise = collect acc cur False rest

    isOutputHeader = BS8.isPrefixOf "# Output "
    isOtherHeader l =
        BS8.isPrefixOf "# " l && not (isOutputHeader l)

hasIntegerOperand :: ByteString -> Bool
hasIntegerOperand line =
    case reverse (BS8.words (BS8.dropWhile (== ' ') line)) of
        (term : _val : _pred : _) -> term == "." || term == ";"
        _ -> False

shouldSatisfy' :: (Show a) => a -> (a -> Bool) -> IO ()
shouldSatisfy' x p
    | p x = pure ()
    | otherwise = error ("predicate failed: " <> show x)

readIntegerOrError :: ByteString -> Integer
readIntegerOrError line =
    case BS8.words (BS8.dropWhile (== ' ') line) of
        (_pred : valBs : _) ->
            let s = BS8.unpack (BS8.takeWhile (/= ';') valBs)
                s' =
                    if last s == '.' || last s == ';'
                        then init s
                        else s
             in case reads s' of
                    [(n, "")] -> n
                    _ ->
                        error
                            ( "OutputLovelaceSpec: unparseable integer on lovelace line: "
                                <> BS8.unpack line
                            )
        _ ->
            error
                ( "OutputLovelaceSpec: malformed lovelace line: "
                    <> BS8.unpack line
                )

{- |
Module      : Cardano.Tx.Graph.Emit.OutputScriptRefSpec
Description : Per-output reference-script sub-block invariant (T105 / S4).
License     : Apache-2.0

Asserts the T105 / S4 invariant: every body output whose
@referenceScriptTxOutL@ surfaces an @SJust script@ emits a
@cardano:hasReferenceScript _:outputRefScriptN@ edge plus a
sub-block carrying @cardano:hasHash "\<hex\>"@ +
@cardano:hasRawBytes "\<cbor-hex\>"@ literals. Outputs whose
@referenceScriptTxOutL@ is @SNothing@ MUST NOT carry the
@cardano:hasReferenceScript@ edge.

The spec runs the body emitter against every rewrite-redesign
fixture, then enumerates each fixture's body outputs, and
compares the per-output emitter slice against the corresponding
@referenceScriptTxOutL@ projection.
-}
module Cardano.Tx.Graph.Emit.OutputScriptRefSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Lens.Micro ((^.))

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (referenceScriptTxOutL)
import Cardano.Ledger.BaseTypes (StrictMaybe (SJust, SNothing))

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

import Test.Hspec (Spec, describe, it, runIO, shouldSatisfy)

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
    describe "Cardano.Tx.Graph.Emit output hasReferenceScript (T105 / S4)" $
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
        outputRefScripts =
            [ txOut ^. referenceScriptTxOutL
            | txOut <- toList (body ^. outputsTxBodyL)
            ]
    it "emits cardano:hasReferenceScript iff output carries a script" $
        sequence_
            [ assertRefScriptShape bytes k refScript
            | (k, refScript) <- zip [1 :: Int ..] outputRefScripts
            ]

----------------------------------------------------------------------
-- Per-output assertions
----------------------------------------------------------------------

assertRefScriptShape :: ByteString -> Int -> StrictMaybe a -> IO ()
assertRefScriptShape bytes k refScript =
    case refScript of
        SNothing ->
            -- The output bnode must NOT carry a hasReferenceScript edge.
            outputBlockOfBytes bytes k
                `shouldSatisfy` not . BS8.isInfixOf "cardano:hasReferenceScript"
        SJust _ -> do
            outputBlockOfBytes bytes k
                `shouldSatisfy` BS8.isInfixOf
                    (BS8.pack ("cardano:hasReferenceScript _:outputRefScript" <> show k))
            -- T118 / S17: script bnodes carry one of two rdf:type
            -- triples discriminating Plutus vs native scripts.
            refScriptBlockOfBytes bytes k
                `shouldSatisfy` ( \block ->
                                    BS8.isInfixOf
                                        "a cardano:PlutusScript"
                                        block
                                        || BS8.isInfixOf
                                            "a cardano:NativeScript"
                                            block
                                )
            refScriptBlockOfBytes bytes k
                `shouldSatisfy` BS8.isInfixOf "cardano:hasHash"
            refScriptBlockOfBytes bytes k
                `shouldSatisfy` BS8.isInfixOf "cardano:hasRawBytes"

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
                "OutputScriptRefSpec.loadEntities: "
                    <> path
                    <> ": "
                    <> show err

{- | The body output at position @k@ (1-based) — every byte between
the @# Output k@ section header and the next section.
-}
outputBlockOfBytes :: ByteString -> Int -> ByteString
outputBlockOfBytes bs k =
    sectionBlock bs ("# Output " <> BS8.pack (show k))

{- | The reference-script sub-block for output position @k@
(1-based) — the slice of bytes from the @_:outputRefScriptK a@
subject-position anchor (T118 / S17: script bnodes are typed
@cardano:NativeScript@ or @cardano:PlutusScript@) to the next
blank line. Skips the predicate-position occurrence inside the
parent output block. Returns empty if no such sub-block exists.
-}
refScriptBlockOfBytes :: ByteString -> Int -> ByteString
refScriptBlockOfBytes bs k =
    let needle =
            "_:outputRefScript"
                <> BS8.pack (show k)
                <> " a "
     in case BS8.breakSubstring needle bs of
            (_, suf)
                | BS.null suf -> ""
                | otherwise ->
                    let (block, _) = BS8.breakSubstring "\n\n" suf
                     in block

{- | Extract the bytes between a section header line (e.g.
@# Output 1@) and the start of the next section's header
divider (@\\n#\\n#@). See the matching helper in
'Cardano.Tx.Graph.Emit.OutputDatumSpec' for the layout
rationale.
-}
sectionBlock :: ByteString -> ByteString -> ByteString
sectionBlock bs header =
    case BS8.breakSubstring header bs of
        (_, suf)
            | BS.null suf -> ""
            | otherwise ->
                let afterHeader =
                        BS8.drop (BS8.length header) suf
                    (_, rest) =
                        BS8.breakSubstring "\n\n" afterHeader
                    body = BS8.drop 2 rest -- skip "\n\n"
                    (block, _) =
                        BS8.breakSubstring "\n#\n" body
                 in block

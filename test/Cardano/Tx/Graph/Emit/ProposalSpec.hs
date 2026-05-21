{- |
Module      : Cardano.Tx.Graph.Emit.ProposalSpec
Description : Per-proposal cluster D-006 fallback shape (T108 / S7).
License     : Apache-2.0

Asserts the T108 / S7 invariant: every body proposal procedure emits

* a @cardano:hasDatum _:proposalDatumN@ edge on the @_:proposalN@
  bnode (the proposal subject is otherwise typeless — typing under
  @cardano:Proposal@ is deferred to follow-on F3); and
* a @_:proposalDatumN a cardano:Datum ;
  cardano:decodedAs "\<variety\>" ;
  cardano:hasRawBytes "\<cbor-hex\>"@ sub-block carrying the
  variety tag (@TreasuryWithdrawals@ at T108) plus the CBOR bytes
  of the @ProposalProcedure@ wire-encoding.

The @_:proposalN@ subject MUST NOT carry the pre-D-006 shape: no
@cardano:Datum@ rdf-type, no @cardano:decodedAs@ direct triple, no
@cardano:hasIdentifier@-spam links to @returnAddr@ / withdrawal
target credentials (deferred to follow-on F3 under new
@proposerReturnAddr@ + @withdrawalTarget@ predicates).

The spec runs the body emitter against every rewrite-redesign
fixture, enumerates each fixture's @proposalProceduresTxBodyL@
projection, and compares the per-proposal emitter slice against
its position-keyed sub-block.
-}
module Cardano.Tx.Graph.Emit.ProposalSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Lens.Micro ((^.))

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (proposalProceduresTxBodyL)

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
    describe "Cardano.Tx.Graph.Emit proposal hasDatum (T108 / S7)" $
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
        nProposals = length (toList (body ^. proposalProceduresTxBodyL))
    it "emits the D-006 inline-datum sub-block per proposal" $
        sequence_
            [ assertProposalShape bytes k
            | k <- [1 .. nProposals]
            ]

----------------------------------------------------------------------
-- Per-proposal assertions
----------------------------------------------------------------------

assertProposalShape :: ByteString -> Int -> IO ()
assertProposalShape bytes k = do
    -- The proposal subject carries a hasDatum edge to its sub-block.
    proposalBlockOfBytes bytes k
        `shouldSatisfy` BS8.isInfixOf
            (BS8.pack ("cardano:hasDatum _:proposalDatum" <> show k))
    -- The proposal subject MUST NOT carry the pre-D-006 shape.
    proposalBlockOfBytes bytes k
        `shouldSatisfy` not . BS8.isInfixOf "a cardano:Datum"
    proposalBlockOfBytes bytes k
        `shouldSatisfy` not . BS8.isInfixOf "cardano:hasIdentifier"
    -- The sub-block IS typed cardano:Datum and carries the
    -- variety tag plus the CBOR raw bytes.
    proposalDatumBlockOfBytes bytes k
        `shouldSatisfy` BS8.isInfixOf "cardano:decodedAs"
    proposalDatumBlockOfBytes bytes k
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
                "ProposalSpec.loadEntities: "
                    <> path
                    <> ": "
                    <> show err

{- | The body proposal block at position @k@ (1-based) — every byte
between the @# Proposal k@ section header and the next blank line
(stops at the boundary with the proposal-datum sub-block).
-}
proposalBlockOfBytes :: ByteString -> Int -> ByteString
proposalBlockOfBytes bs k =
    let needle = "_:proposal" <> BS8.pack (show k) <> " "
     in case BS8.breakSubstring needle (sectionBlock bs ("# Proposal " <> BS8.pack (show k))) of
            (_, suf)
                | BS.null suf -> ""
                | otherwise ->
                    let (block, _) = BS8.breakSubstring "\n\n" suf
                     in block

{- | The proposal-datum sub-block at position @k@ (1-based) — the
slice from the @_:proposalDatumK a cardano:Datum@ subject-position
anchor to the next blank line. Returns empty if no such sub-block
exists.
-}
proposalDatumBlockOfBytes :: ByteString -> Int -> ByteString
proposalDatumBlockOfBytes bs k =
    let needle =
            "_:proposalDatum" <> BS8.pack (show k) <> " a cardano:Datum"
     in case BS8.breakSubstring needle bs of
            (_, suf)
                | BS.null suf -> ""
                | otherwise ->
                    let (block, _) = BS8.breakSubstring "\n\n" suf
                     in block

{- | Extract the bytes between a section header line (e.g.
@# Proposal 1@) and the start of the next section's header
divider (@\\n#\\n#@). The Turtle layout is
@#\\n# \<header\>\\n#\\n\\n\<blocks\>\\n#\\n# \<next\>\\n#@; the
helper jumps past the @\\n#\\n\\n@ frame so the returned slice
starts at the first blank-line-separated subject block.
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

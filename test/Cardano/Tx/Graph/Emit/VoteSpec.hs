{- |
Module      : Cardano.Tx.Graph.Emit.VoteSpec
Description : Voting-procedure emission + voter discrimination (T119 / S18).
License     : Apache-2.0

Asserts the T119 / S18 invariant: every entry in the body's
@votingProcedures@ surfaces as a typed @cardano:Vote@ subject
block bound to @_:tx@ via @cardano:hasVote@. Each vote subject
carries:

* @cardano:hasVoter _:voterK@ — discriminating the voter into
  one of three classes (@cardano:VoterDRep@,
  @cardano:VoterStakePool@, @cardano:VoterCommitteeCold@) with
  a 28-byte @cardano:hasIdentifier@ key/script-hash literal.
* @cardano:hasVotingAction "\<txid\>#\<ix\>"@ — the governance
  action id the vote targets.
* @cardano:hasVerdict "Yes" | "No" | "Abstain"@.
* @cardano:hasAnchor _:voteAnchorK@ — when the vote carries an
  off-chain anchor (URL + hash sub-block).

The path-A synthetic 'ConwayTx' values built here exercise the
three Voter discrimination branches + the Vote verdict
constructors + the anchor SJust branch in isolation; no
fixture currently exercises voting procedures.
-}
module Cardano.Tx.Graph.Emit.VoteSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (mkBasicTxBody, votingProceduresTxBodyL)
import Cardano.Ledger.BaseTypes (
    StrictMaybe (SJust, SNothing),
    textToUrl,
 )
import Cardano.Ledger.Conway.Governance (
    Anchor (..),
    GovActionId (..),
    GovActionIx (..),
    Vote (Abstain, VoteNo, VoteYes),
    Voter (CommitteeVoter, DRepVoter, StakePoolVoter),
    VotingProcedure (..),
    VotingProcedures (..),
 )
import Cardano.Ledger.Credential (Credential (KeyHashObj))
import Cardano.Ledger.Hashes (KeyHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyRole (..))
import Cardano.Ledger.TxIn (TxId (..))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit voting procedures (T119 / S18)" $ do
        elisionSpec
        drepSpec
        stakePoolSpec
        committeeSpec
        verdictsSpec
        anchorSpec

elisionSpec :: Spec
elisionSpec = describe "elision" $
    it "elides cardano:hasVote when votingProcedures is empty" $ do
        let bytes = emitBytes baseTx
        bytes `shouldSatisfy` (not . BS8.isInfixOf "cardano:hasVote")
        bytes `shouldSatisfy` (not . BS8.isInfixOf "cardano:Vote")

drepSpec :: Spec
drepSpec = describe "DRep voter" $
    it "types voter as cardano:VoterDRep with hasIdentifier" $ do
        let voter = DRepVoter (KeyHashObj (drepKeyHash 0xaa))
            bytes = emitBytes (txWithSingleVote voter VoteYes SNothing)
        bytes `shouldSatisfy` BS8.isInfixOf "_:vote1 a cardano:Vote"
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:hasVoter _:voter1"
        bytes `shouldSatisfy` BS8.isInfixOf "_:voter1 a cardano:VoterDRep"
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:hasIdentifier \"" <> BS8.replicate 56 'a' <> "\"")

stakePoolSpec :: Spec
stakePoolSpec = describe "stake-pool voter" $
    it "types voter as cardano:VoterStakePool with hasIdentifier" $ do
        let voter = StakePoolVoter (poolKeyHash 0xbb)
            bytes = emitBytes (txWithSingleVote voter VoteNo SNothing)
        bytes `shouldSatisfy` BS8.isInfixOf "_:voter1 a cardano:VoterStakePool"
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:hasIdentifier \"" <> BS8.replicate 56 'b' <> "\"")

committeeSpec :: Spec
committeeSpec = describe "constitutional-committee voter" $
    it "types voter as cardano:VoterCommitteeCold with hasIdentifier" $ do
        let voter = CommitteeVoter (KeyHashObj (committeeKeyHash 0xcc))
            bytes = emitBytes (txWithSingleVote voter Abstain SNothing)
        bytes
            `shouldSatisfy` BS8.isInfixOf "_:voter1 a cardano:VoterCommitteeCold"
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:hasIdentifier \"" <> BS8.replicate 56 'c' <> "\"")

verdictsSpec :: Spec
verdictsSpec = describe "verdict text" $ do
    it "emits cardano:hasVerdict \"Yes\" for VoteYes" $ do
        let voter = DRepVoter (KeyHashObj (drepKeyHash 1))
        emitBytes (txWithSingleVote voter VoteYes SNothing)
            `shouldSatisfy` BS8.isInfixOf "cardano:hasVerdict \"Yes\""
    it "emits cardano:hasVerdict \"No\" for VoteNo" $ do
        let voter = DRepVoter (KeyHashObj (drepKeyHash 1))
        emitBytes (txWithSingleVote voter VoteNo SNothing)
            `shouldSatisfy` BS8.isInfixOf "cardano:hasVerdict \"No\""
    it "emits cardano:hasVerdict \"Abstain\" for Abstain" $ do
        let voter = DRepVoter (KeyHashObj (drepKeyHash 1))
        emitBytes (txWithSingleVote voter Abstain SNothing)
            `shouldSatisfy` BS8.isInfixOf "cardano:hasVerdict \"Abstain\""

anchorSpec :: Spec
anchorSpec = describe "anchor sub-block" $
    it "emits hasAnchor + anchorUrl + anchorHash when SJust" $ do
        let voter = DRepVoter (KeyHashObj (drepKeyHash 1))
            anchor =
                Anchor
                    (fromJust (textToUrl 64 "https://example.invalid/anchor"))
                    ( unsafeMakeSafeHash
                        (fromJust (hashFromStringAsHex (replicate 64 '0')))
                    )
            bytes = emitBytes (txWithSingleVote voter VoteYes (SJust anchor))
        bytes `shouldSatisfy` BS8.isInfixOf "cardano:hasAnchor _:voteAnchor1"
        bytes
            `shouldSatisfy` BS8.isInfixOf
                "cardano:anchorUrl \"https://example.invalid/anchor\""
        bytes
            `shouldSatisfy` BS8.isInfixOf
                ("cardano:anchorHash \"" <> BS8.replicate 64 '0' <> "\"")

----------------------------------------------------------------------
-- Synthesis helpers
----------------------------------------------------------------------

baseTx :: ConwayTx
baseTx = mkBasicTx mkBasicTxBody

txWithSingleVote ::
    Voter -> Vote -> StrictMaybe Anchor -> ConwayTx
txWithSingleVote voter vote mAnchor =
    baseTx
        & bodyTxL . votingProceduresTxBodyL
            .~ VotingProcedures
                ( Map.singleton
                    voter
                    ( Map.singleton
                        (stubGovActionId 0xdd)
                        (VotingProcedure vote mAnchor)
                    )
                )

stubGovActionId :: Int -> GovActionId
stubGovActionId n =
    GovActionId
        ( TxId
            ( unsafeMakeSafeHash
                ( fromJust
                    ( hashFromStringAsHex
                        (concat (replicate 32 (hexByte n)))
                    )
                )
            )
        )
        (GovActionIx 0)
  where
    hexByte b = [d (b `div` 16), d (b `mod` 16)]
    d k = "0123456789abcdef" !! k

drepKeyHash :: Int -> KeyHash DRepRole
drepKeyHash = mkKeyHash

poolKeyHash :: Int -> KeyHash StakePool
poolKeyHash = mkKeyHash

committeeKeyHash :: Int -> KeyHash HotCommitteeRole
committeeKeyHash = mkKeyHash

mkKeyHash :: Int -> KeyHash r
mkKeyHash n =
    KeyHash
        (fromJust (hashFromStringAsHex (concat (replicate 28 (hexByte n)))))
  where
    hexByte b = [d (b `div` 16), d (b `mod` 16)]
    d k = "0123456789abcdef" !! k

emitBytes :: ConwayTx -> ByteString
emitBytes tx =
    case emit tx emptyUtxo [] [] of
        Right g -> serialize Turtle "vote-spec" g
        Left e -> error ("VoteSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

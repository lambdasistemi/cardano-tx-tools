{- |
Module      : Cardano.Tx.Graph.Emit.Project
Description : Projection-driven body walker for the joint Turtle emitter (private).
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. Walks the
'Cardano.Tx.Diff.conwayDiffProjection' tree over a 'ConwayTx',
dispatches on the typed @ConwayDiffValue@ leaves, and produces
a 'BodySection' list ready for the Turtle / JSON-LD serializers.

T005 ships **fixture-02 coverage**: @cardano:Transaction@,
@cardano:Input@, @cardano:Output@, @cardano:Address@, payment +
stake credentials, fee. T007 extends coverage with
@cardano:Mint@ + @cardano:Policy@ + @cardano:Asset@ clusters
(fixture 04) and @cardano:Withdrawal@ clusters (fixture 05).
T008 adds @cardano:StakeDelegation@ + @cardano:VoteDelegation@
cert clusters (fixtures 06, 07). T010 adds collateral inputs
(fixtures 01, 08, 11 — reusing @cardano:Input@ off the new
@cardano:hasCollateralInput@ predicate) and the Conway
TreasuryWithdrawals proposal cluster (fixture 10 — typed
@cardano:Datum@ with @cardano:decodedAs "TreasuryWithdrawals"@
plus per-stake-credential @cardano:hasIdentifier@ links for the
proposer's returnAddr and the withdrawal targets, mirroring the
artisan layout shipped by #45). Every remaining body-level leaf
(reference inputs, required signers, total-collateral, non-
TreasuryWithdrawal proposal varieties, non-delegation cert
varieties) is detected via emptiness probes / fail-loudly case
arms; a non-empty unhandled leaf surfaces as
'ProjectError.PUnsupportedLeafType'.

== T102 — monadic seam

The per-cluster block lists are now built via the
'Cardano.Tx.Graph.Emit.Monad.Emit' monad: each
@emit*Cluster@ helper is an @Emit ()@ action that 'tellTriple's
its triples in the order the pre-T102 walker produced
@[SubjectBlock]@; the local 'clusterBlocks' helper
@runEmit@s + @groupBySubject@s to recover the 'SubjectBlock'
list. The address-decomposition section uses
'Cardano.Tx.Graph.Emit.Monad.introduce' so each unique address
emits its address + payment-credential + stake-credential
blocks exactly once even when a fixture reaches the same
address from multiple inputs/outputs/collaterals.

The byte output of the Turtle serializer is unchanged by the
T102 refactor: every fixture's @expected.ttl@ is
byte-identical pre- and post-T102 (see
'Cardano.Tx.Graph.EmitGoldenSpec').

== Bnode naming scheme (T005 / Q-002 → A-002)

The address-decomposition section emits one block per unique
@'Cardano.Ledger.Address.Addr'@ value (first-occurrence wins;
see 'AddrRegistry'). Each address resolves to a /base/ name; the
serializer derives the address, payment-credential, and
stake-credential bnodes by uniform suffixing on that base:

* @\<base\>Addr@ — the @cardano:Address@ subject.
* @\<base\>CredPayment@ — the @cardano:PaymentCredential@ subject.
* @\<base\>CredStake@ — the @cardano:StakeCredential@ subject
  (omitted for enterprise addresses).

The base depends on whether an operator-declared entity covers
the address's payment credential:

[entity-covered]
The base is the entity's slug. E.g. for alice:
@_:aliceAddr@, @_:aliceCredPayment@, @_:aliceCredStake@. The
credentials' @cardano:hasIdentifier@ targets are the entity's
identifier bnodes ('Cardano.Tx.Graph.Emit.Lookup.entityBnodeName'
output): @_:alice_paymentKey@, @_:alice_stakeKey@.

[raw-bytes]
The base is the credential identifier name itself
('Cardano.Tx.Graph.Emit.Lookup.rawBytesBnodeName' output) —
@cred_\<rolePrefix\>_\<bytes16\>@. The full suffix-extended
forms become:

* address: @_:cred_paymentkey_\<bytes16\>Addr@
* payment cred: @_:cred_paymentkey_\<bytes16\>CredPayment@
* identifier target (from 'resolveCredential'):
  @_:cred_paymentkey_\<bytes16\>@

The identifier-anchor doubles as the address-bnode anchor so the
namespace stays internally consistent without inventing a parallel
@addr_…@ scheme.

If future slices (T006-T010) surface a case where two distinct
addresses share the same payment credential (e.g. base + stake
key vs base + stake script), the address bnodes would collide
on @\<paymentId\>Addr@; that's a Q-file moment — file before
introducing a stake-side disambiguator.

== Tx-block predicate order (T010 / A-001, extended at T103)

The transaction subject block lists its @has*@ predicates in this
fixed order:

@hasInput, hasReferenceInput, hasOutput, hasMint, hasWithdrawal,
hasCertificate, hasCollateralInput, hasProposal, hasFee@

The order follows the artisan @expected.ttl@ layout shipped by #45
plus the T103 reference-input insertion (clustered next to
@hasInput@ so all input-position predicates share the same anchor)
and is byte-equal-critical: the Turtle serializer preserves
predicate order verbatim. Future slices (T011+ JSON-LD, future
leaves) MUST extend the list in place rather than re-shuffling.
-}
module Cardano.Tx.Graph.Emit.Project (
    ProjectError (..),
    projectBody,
) where

import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Short qualified as SBS
import Data.List (find)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

import Codec.Binary.Bech32 qualified as Bech32
import Lens.Micro ((^.))

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    Withdrawals (..),
    serialiseAddr,
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (
    plutusScriptLanguage,
    toPlutusScript,
 )
import Cardano.Ledger.Alonzo.TxBody (ScriptIntegrityHash)
import Cardano.Ledger.Api.Era (eraProtVerLow)
import Cardano.Ledger.Api.Scripts.Data (
    Datum (Datum, DatumHash, NoDatum),
    hashBinaryData,
 )
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    auxDataHashTxBodyL,
    certsTxBodyL,
    collateralInputsTxBodyL,
    collateralReturnTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    networkIdTxBodyL,
    outputsTxBodyL,
    proposalProceduresTxBodyL,
    referenceInputsTxBodyL,
    reqSignerHashesTxBodyL,
    scriptIntegrityHashTxBodyL,
    totalCollateralTxBodyL,
    vldtTxBodyL,
    votingProceduresTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Cert (
    Delegatee (DelegStake, DelegStakeVote, DelegVote),
    pattern DelegTxCert,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    datumTxOutL,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    SlotNo (..),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
    networkToWord8,
    urlToText,
 )
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Governance (
    Anchor (..),
    GovAction (..),
    GovActionId (..),
    GovActionIx (..),
    ProposalProcedure (..),
    Vote (Abstain, VoteNo, VoteYes),
    Voter (CommitteeVoter, DRepVoter, StakePoolVoter),
    VotingProcedure (..),
    VotingProcedures (..),
    foldrVotingProcedures,
 )
import Cardano.Ledger.Conway.TxCert (
    pattern AuthCommitteeHotKeyTxCert,
    pattern RegDRepTxCert,
    pattern RegDepositDelegTxCert,
    pattern RegDepositTxCert,
    pattern ResignCommitteeColdTxCert,
    pattern UnRegDRepTxCert,
    pattern UnRegDepositTxCert,
    pattern UpdateDRepTxCert,
 )
import Cardano.Ledger.Core (Script, TxCert, hashScript)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefBase, StakeRefNull, StakeRefPtr),
 )
import Cardano.Ledger.DRep (
    DRep (DRepKeyHash, DRepScriptHash),
 )
import Cardano.Ledger.Hashes (
    KeyHash (..),
    ScriptHash (..),
    TxAuxDataHash (..),
    extractHash,
    originalBytes,
 )
import Cardano.Ledger.Keys (KeyRole (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.Language (
    Language (PlutusV1, PlutusV2, PlutusV3, PlutusV4),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.Foldable (toList)

import Cardano.Tx.Graph.Emit.Lookup (
    BnodeName (..),
    LookupTable,
    rawBytesBnodeName,
 )
import Cardano.Tx.Graph.Emit.Monad (
    Emit,
    groupBySubject,
    introduce,
    runEmit,
    tellTriple,
 )
import Cardano.Tx.Graph.Emit.Triple (
    BodySection (..),
    Object (..),
    Predicate (..),
    Subject (..),
    SubjectBlock (..),
    Triple (..),
 )
import Cardano.Tx.Graph.Emit.Vocab (VocabTerm (..), vocabCurie)
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
 )
import Cardano.Tx.Ledger (ConwayTx)

{- | Errors the body walker raises before the public emitter
wraps them in 'Cardano.Tx.Graph.Emit.EmitError'.
-}
newtype ProjectError = PUnsupportedLeafType Text
    deriving stock (Eq, Show)

{- | Walk the @ConwayBodyValue tx@ projection and produce the
body section list — transaction block, per-input + per-output
clusters, and the deduped address-decomposition block.

Resolved-UTxO entries (when the input's @TxIn@ appears in
@utxo@) attach a @cardano:resolvedTo@ predicate to the input's
block and add the resolved output's address to the
address-decomposition section.
-}
projectBody ::
    [EntityDecl] ->
    LookupTable ->
    ConwayTx ->
    Map TxIn (TxOut ConwayEra) ->
    Either ProjectError [BodySection]
projectBody entities lookupTbl tx utxo = do
    let body = tx ^. bodyTxL
        inputs = Set.toAscList (body ^. inputsTxBodyL)
        refInputs =
            Set.toAscList (body ^. referenceInputsTxBodyL)
        collateralIns =
            Set.toAscList (body ^. collateralInputsTxBodyL)
        outputs =
            foldr (:) [] (body ^. outputsTxBodyL)
        Coin feeLovelace = body ^. feeTxBodyL
        MultiAsset mintPolicies = body ^. mintTxBodyL
        mintPairs =
            [ (policyId, assetName, quantity)
            | (policyId, assets) <- Map.toAscList mintPolicies
            , (assetName, quantity) <- Map.toAscList assets
            ]
        Withdrawals wmap = body ^. withdrawalsTxBodyL
        withdrawalPairs = Map.toAscList wmap
        certs = toList (body ^. certsTxBodyL)
        proposals = toList (body ^. proposalProceduresTxBodyL)
        validity = body ^. vldtTxBodyL
        networkId = body ^. networkIdTxBodyL
        scriptDataHash = body ^. scriptIntegrityHashTxBodyL
        auxDataHash = body ^. auxDataHashTxBodyL
        requiredSigners =
            Set.toAscList (body ^. reqSignerHashesTxBodyL)
        totalCollateral = body ^. totalCollateralTxBodyL
        collateralReturn = body ^. collateralReturnTxBodyL
        votes = flattenVotingProcedures (body ^. votingProceduresTxBodyL)
    -- Build per-input data + per-output data + per-collateral
    -- data with a single deduped address bnode registry.
    let (inputData, addrRegistry1) =
            buildInputs entities lookupTbl utxo inputs
        (outputData, addrRegistry2) =
            buildOutputs entities lookupTbl outputs addrRegistry1
        (collateralData, addrRegistry3) =
            buildCollaterals entities lookupTbl utxo collateralIns addrRegistry2
        (collateralReturnData, addrRegistry4) =
            buildCollateralReturn entities lookupTbl collateralReturn addrRegistry3
        refInputData = buildReferenceInputs refInputs
        addrEntries = addrRegistryEntries addrRegistry4
    -- Per-cert clusters (T008 — fixtures 06, 07; T120 — Conway
    -- variants beyond the StakeDelegation / VoteDelegation
    -- pair fall through the OpaqueLeaf cover).
    let certClusters =
            [ buildCertCluster lookupTbl k cert
            | (k, cert) <- zip [1 ..] certs
            ]
    -- Per-proposal clusters (T010 — fixture 10; T121 — every
    -- Conway GovAction variant flows through the same fallback
    -- shape).
    let proposalBlocks =
            [ buildProposalCluster k proposal
            | (k, proposal) <- zip [1 ..] proposals
            ]
    -- Per-vote clusters (T119 / S18 — voting procedures).
    let voteBlocks =
            [ clusterBlocks (buildVoteCluster k voter actionId procedure)
            | (k, (voter, actionId, procedure)) <- zip [1 ..] votes
            ]
    -- Assemble the tx subject block via the Emit monad — the
    -- per-predicate @tellTriple@ sequence preserves the
    -- pre-T102 byte order (see the module-header note on
    -- tx-block predicate order).
    let txBlocks =
            clusterBlocks $
                emitTxBlock
                    (length inputData)
                    (length refInputData)
                    (length outputData)
                    (length mintPairs)
                    (length withdrawalPairs)
                    (length certs)
                    (length collateralData)
                    (length proposals)
                    feeLovelace
                    validity
                    networkId
                    scriptDataHash
                    auxDataHash
                    requiredSigners
                    totalCollateral
                    (not (null collateralReturnData))
                    (length votes)
        txSection =
            BodySection
                { sectionHeader = "Transaction body."
                , sectionBlocks = txBlocks
                }
        inputSections =
            [ BodySection
                { sectionHeader = "Input " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] inputData
            ]
        referenceInputSections =
            [ BodySection
                { sectionHeader = "Reference input " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] refInputData
            ]
        outputSections =
            [ BodySection
                { sectionHeader = "Output " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] outputData
            ]
        mintSections =
            [ BodySection
                { sectionHeader = "Mint " <> Text.pack (show k)
                , sectionBlocks =
                    clusterBlocks
                        (emitMintCluster lookupTbl k policyId assetName quantity)
                }
            | (k, (policyId, assetName, quantity)) <-
                zip [1 :: Int ..] mintPairs
            ]
        withdrawalSections =
            [ BodySection
                { sectionHeader = "Withdrawal " <> Text.pack (show k)
                , sectionBlocks =
                    clusterBlocks
                        (emitWithdrawalCluster lookupTbl k account coin)
                }
            | (k, (account, coin)) <- zip [1 :: Int ..] withdrawalPairs
            ]
        certSections =
            [ BodySection
                { sectionHeader = "Certificate " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] certClusters
            ]
        collateralSections =
            [ BodySection
                { sectionHeader = "Collateral " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] collateralData
            ]
        collateralReturnSections =
            [ BodySection
                { sectionHeader = "Collateral return."
                , sectionBlocks = blocks
                }
            | blocks <- collateralReturnData
            ]
        proposalSections =
            [ BodySection
                { sectionHeader = "Proposal " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] proposalBlocks
            ]
        voteSections =
            [ BodySection
                { sectionHeader = "Vote " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] voteBlocks
            ]
        addrSection
            | null addrEntries = []
            | otherwise =
                [ BodySection
                    { sectionHeader =
                        "Address decompositions — payment + "
                            <> "stake credential per leaf."
                    , sectionBlocks =
                        clusterBlocks
                            ( mapM_
                                (emitAddrEntry lookupTbl)
                                addrEntries
                            )
                    }
                ]
    pure
        ( txSection
            : inputSections
                <> referenceInputSections
                <> outputSections
                <> mintSections
                <> withdrawalSections
                <> certSections
                <> collateralSections
                <> collateralReturnSections
                <> proposalSections
                <> voteSections
                <> addrSection
        )

----------------------------------------------------------------------
-- Monadic seam: run + group.
----------------------------------------------------------------------

{- | Run an 'Emit' action and re-shape its triple stream into
the 'SubjectBlock' list the serializer consumes.

The seen-subject state is discarded — each cluster is run with
its own fresh state so per-cluster 'introduce' calls don't
leak across cluster boundaries. The address-decomposition
section is the one place that calls 'introduce' meaningfully
(dedup within a single cluster), so that's fine.
-}
clusterBlocks :: Emit () -> [SubjectBlock]
clusterBlocks action =
    let (triples, _seen) = runEmit action
     in groupBySubject triples

----------------------------------------------------------------------
-- Raw-bytes identifier literal exposure (T119b / S18b)
----------------------------------------------------------------------

{- | Resolve a @(LeafType, raw bytes)@ pair to a bnode name AND
emit the canonical identifier-literal triples
(@a cardano:Identifier ; cardano:leafType "X" ;
cardano:bytesHex "\<hex\>"@) on the bnode when the resolution
goes through the raw-bytes path. Entity-named bnodes (table
hits) skip the emission — the entity-overlay path already
emits those triples verbatim, so emitting them again from the
body walker would duplicate.

Use this instead of 'resolveCredential' in every body-walker
site that produces a credential bnode. The new triples let
SPARQL views join 'cardano:hasRequiredSigner' literals (and
similar raw-hex predicates) against the credential bnode's
@cardano:bytesHex@ via @FILTER (?signer = ?credHex)@ — no IRI
surgery required (operator-driven gap, T119b).

== Dedup

The triples are wrapped in 'introduce' so re-resolving the same
(lt, bytes) within a single 'Emit' walk emits the block only
once. The body walker runs each cluster in its own 'runEmit',
so the same identifier may emit triples in multiple clusters
that reference it — that's fine semantically (Turtle's
blank-node naming gives the same logical subject, so multiple
emissions merge into a single graph at parse time), and the
linear duplication is bounded by the number of clusters that
share a credential.
-}
resolveCredentialAndIntroduceIdent ::
    LookupTable ->
    LeafType ->
    ByteString ->
    Emit BnodeName
resolveCredentialAndIntroduceIdent tbl lt bytes = do
    case Map.lookup (lt, bytes) tbl of
        Just bn ->
            -- Entity-named — overlay path emits the literal triples.
            pure bn
        Nothing -> do
            let bn = rawBytesBnodeName lt bytes
                bnSubj = SBnode bn
            introduce bnSubj $ do
                tellTriple
                    (Triple bnSubj PRdfType (OIri (vocabCurie TermIdentifier)))
                tellTriple
                    ( Triple
                        bnSubj
                        (PIri (vocabCurie TermLeafType))
                        (OStringLit (leafTypeText lt))
                    )
                tellTriple
                    ( Triple
                        bnSubj
                        (PIri (vocabCurie TermBytesHex))
                        (OStringLit (hexText bytes))
                    )
            pure bn

{- | Canonical camelCase string form of a 'LeafType'. Matches the
@cardano:leafType@ literal the entity-overlay path emits
(see @Cardano.Tx.Graph.Rules.Load.Emit.Overlay.renderLeafType@).
-}
leafTypeText :: LeafType -> Text
leafTypeText = \case
    PaymentKey -> "PaymentKey"
    PaymentScript -> "PaymentScript"
    StakeKey -> "StakeKey"
    StakeScript -> "StakeScript"
    AssetClass -> "AssetClass"
    Policy -> "Policy"
    PoolId -> "PoolId"
    DRepKey -> "DRepKey"
    DRepScript -> "DRepScript"

----------------------------------------------------------------------
-- Per-input + per-output traversal
----------------------------------------------------------------------

-- | Bnode name a body input at position @k@ (1-based) gets.
idInputBnode :: Int -> BnodeName
idInputBnode k = BnodeName ("input" <> Text.pack (show k))

-- | Bnode name a body output at position @k@ (1-based) gets.
idOutputBnode :: Int -> BnodeName
idOutputBnode k = BnodeName ("output" <> Text.pack (show k))

{- | Bnode name the per-output datum sub-block at output position
@k@ (1-based) gets. T105 / S4 attaches it to the output via
'cardano:hasDatum' when the output carries either an inline
datum or a datum hash.
-}
idOutputDatumBnode :: Int -> BnodeName
idOutputDatumBnode k =
    BnodeName ("outputDatum" <> Text.pack (show k))

{- | Bnode name the per-output reference-script sub-block at output
position @k@ (1-based) gets. T105 / S4 attaches it to the
output via 'cardano:hasReferenceScript' when the output carries
a reference script (inline or hash-only).
-}
idOutputRefScriptBnode :: Int -> BnodeName
idOutputRefScriptBnode k =
    BnodeName ("outputRefScript" <> Text.pack (show k))

-- | Bnode name a resolved-input output at position @k@ gets.
idResolvedInputBnode :: Int -> BnodeName
idResolvedInputBnode k =
    BnodeName ("resolvedInput" <> Text.pack (show k))

-- | Bnode name a mint entry at position @k@ (1-based) gets.
idMintBnode :: Int -> BnodeName
idMintBnode k = BnodeName ("mint" <> Text.pack (show k))

-- | Bnode name a mint-entry asset at position @k@ gets.
idAssetBnode :: Int -> BnodeName
idAssetBnode k = BnodeName ("asset" <> Text.pack (show k))

-- | Bnode name a withdrawal entry at position @k@ (1-based) gets.
idWithdrawalBnode :: Int -> BnodeName
idWithdrawalBnode k =
    BnodeName ("withdrawal" <> Text.pack (show k))

-- | Bnode name a certificate entry at position @k@ (1-based) gets.
idCertBnode :: Int -> BnodeName
idCertBnode k = BnodeName ("cert" <> Text.pack (show k))

-- | Bnode name a stake-delegation pool target at position @k@ gets.
idPoolBnode :: Int -> BnodeName
idPoolBnode k = BnodeName ("pool" <> Text.pack (show k))

-- | Bnode name a vote-delegation DRep target at position @k@ gets.
idDRepBnode :: Int -> BnodeName
idDRepBnode k = BnodeName ("drep" <> Text.pack (show k))

-- | Bnode name a collateral input at position @k@ (1-based) gets.
idCollateralBnode :: Int -> BnodeName
idCollateralBnode k =
    BnodeName ("collateral" <> Text.pack (show k))

{- | Bnode name the body's single collateral-return output gets.
T117 / S16 — the collateral-return output is structurally
unique (at most one per body), so it carries a 0-arity bnode
name @collateralReturn1@ for byte-stability with future
multi-collateral-return variants.
-}
idCollateralReturnBnode :: BnodeName
idCollateralReturnBnode = BnodeName "collateralReturn1"

-- | Bnode name a reference input at position @k@ (1-based) gets.
idReferenceInputBnode :: Int -> BnodeName
idReferenceInputBnode k =
    BnodeName ("refInput" <> Text.pack (show k))

-- | Bnode name a resolved-collateral output at position @k@ gets.
idResolvedCollateralBnode :: Int -> BnodeName
idResolvedCollateralBnode k =
    BnodeName ("resolvedCollateral" <> Text.pack (show k))

-- | Bnode name a proposal entry at position @k@ (1-based) gets.
idProposalBnode :: Int -> BnodeName
idProposalBnode k =
    BnodeName ("proposal" <> Text.pack (show k))

-- | Bnode name a vote entry at position @k@ (1-based) gets.
idVoteBnode :: Int -> BnodeName
idVoteBnode k = BnodeName ("vote" <> Text.pack (show k))

-- | Bnode name a vote's voter sub-block at position @k@ gets.
idVoterBnode :: Int -> BnodeName
idVoterBnode k = BnodeName ("voter" <> Text.pack (show k))

-- | Bnode name a vote's anchor sub-block at position @k@ gets.
idVoteAnchorBnode :: Int -> BnodeName
idVoteAnchorBnode k = BnodeName ("voteAnchor" <> Text.pack (show k))

{- | Bnode name the per-proposal inline-datum sub-block at proposal
position @k@ (1-based) gets. T108 / S7 attaches it to the
proposal subject via 'cardano:hasDatum'; the sub-block carries
'cardano:decodedAs' + 'cardano:hasRawBytes' (D-006 fallback).
-}
idProposalDatumBnode :: Int -> BnodeName
idProposalDatumBnode k =
    BnodeName ("proposalDatum" <> Text.pack (show k))

----------------------------------------------------------------------
-- Multi-asset value anchor + bnode naming (T104)
----------------------------------------------------------------------

{- | An anchor for naming the per-subject multi-asset list-cell and
asset-entry bnodes T104 emits. The 'vaBase' string is the
subject's bnode-name prefix (@"output"@, @"resolvedInput"@,
@"resolvedCollateral"@) and 'vaIndex' is the 1-based position
within that role.

The produced bnode-name shape (per A-001 + the brief's D-005
example):

* list head: @\<base\>MultiAsset\<index\>@
* tail cell at position @m@ (1-based): @\<base\>MultiAsset\<index\>_tail\<m\>@
* asset-entry at position @m@ (1-based): @assetEntry_\<base\>\<index\>_\<m\>@

Resolved-input + resolved-collateral subjects (T103's payload)
reuse the same scheme with @"resolvedInput"@ / @"resolvedCollateral"@
bases so the multi-asset cells never collide across the input
and output sides of the same fixture.
-}
data ValueAnchor = ValueAnchor
    { vaBase :: !Text
    , vaIndex :: !Int
    }

-- | Bnode name of the multi-asset list head for an anchor.
valueListHead :: ValueAnchor -> BnodeName
valueListHead va =
    BnodeName
        ( vaBase va
            <> "MultiAsset"
            <> Text.pack (show (vaIndex va))
        )

-- | Bnode name of the @m@-th list tail cell (1-based).
valueListTail :: ValueAnchor -> Int -> BnodeName
valueListTail va m =
    BnodeName
        ( vaBase va
            <> "MultiAsset"
            <> Text.pack (show (vaIndex va))
            <> "_tail"
            <> Text.pack (show m)
        )

-- | Bnode name of the @m@-th asset entry (1-based).
valueAssetEntry :: ValueAnchor -> Int -> BnodeName
valueAssetEntry va m =
    BnodeName
        ( "assetEntry_"
            <> vaBase va
            <> Text.pack (show (vaIndex va))
            <> "_"
            <> Text.pack (show m)
        )

{- | Flatten a 'MultiAsset' into a deterministically-ordered list of
@(policy, asset-name, quantity)@ triples. Outer 'PolicyID' keys
are walked in ascending order; per-policy 'AssetName' keys are
walked in ascending order. Matches the order
@Cardano.Ledger.Mary.Value@'s on-wire serializer enforces.
-}
flattenMultiAsset :: MultiAsset -> [(PolicyID, AssetName, Integer)]
flattenMultiAsset (MultiAsset m) =
    [ (policy, name, q)
    | (policy, assets) <- Map.toAscList m
    , (name, q) <- Map.toAscList assets
    ]

{- | Emit the value triples that hang off a value-bearing subject:
the @cardano:lovelace@ literal always, plus — when the
multi-asset map is non-empty — a @cardano:hasAssetValue@ link to
an RDF-list head and the list-cell + per-asset-entry blocks
that decode the bundle.

The list cells use the RDF core terms @rdf:first@ / @rdf:rest@,
terminating in @rdf:nil@. Each asset entry is a
@cardano:Asset@-typed bnode carrying a @cardano:hasIdentifier@
link (resolved through the operator-rules lookup so entity
slugs win when declared) plus a @cardano:quantity@ integer.

The anchor names the multi-asset list head + tail cells + asset
entries (see 'ValueAnchor'); the @subj@ is the value-bearing
subject that gets the @cardano:hasAssetValue@ edge. Pass an
empty multi-asset map (@MultiAsset mempty@) to emit lovelace
only — no list head, no @rdf:nil@ orphan.
-}
emitOutputValue ::
    LookupTable -> ValueAnchor -> Subject -> MaryValue -> Emit ()
emitOutputValue lookupTbl va subj (MaryValue (Coin lovelace) ma) = do
    tellTriple
        ( Triple
            subj
            (PIri (vocabCurie TermLovelace))
            (OIntLit (fromIntegral lovelace))
        )
    case flattenMultiAsset ma of
        [] -> pure ()
        entries -> do
            let headBnode = valueListHead va
            tellTriple
                ( Triple
                    subj
                    (PIri (vocabCurie TermHasAssetValue))
                    (OBnode headBnode)
                )
            emitAssetList lookupTbl va entries

{- | Emit the RDF list cells + per-asset-entry blocks for a
non-empty multi-asset bundle.
-}
emitAssetList ::
    LookupTable ->
    ValueAnchor ->
    [(PolicyID, AssetName, Integer)] ->
    Emit ()
emitAssetList lookupTbl va entries =
    let total = length entries
     in mapM_
            (emitAssetListCell lookupTbl va total)
            (zip [1 ..] entries)

{- | Emit one (list cell, asset-entry) pair. The list-cell subject
is the head bnode on @m == 1@ and a tail bnode on @m > 1@; the
@rdf:rest@ target points at the next tail cell or @rdf:nil@ on
the last entry.
-}
emitAssetListCell ::
    LookupTable ->
    ValueAnchor ->
    Int ->
    (Int, (PolicyID, AssetName, Integer)) ->
    Emit ()
emitAssetListCell lookupTbl va total (m, (policy, assetName, qty)) = do
    let cellSubj
            | m == 1 = SBnode (valueListHead va)
            | otherwise = SBnode (valueListTail va (m - 1))
        nextObj
            | m == total = OIri "rdf:nil"
            | otherwise = OBnode (valueListTail va m)
        entryBnode = valueAssetEntry va m
        entrySubj = SBnode entryBnode
        policyBytes = policyIdBytes policy
        assetBytes = policyBytes <> assetClassNameBytes assetName
    assetIdBnode <-
        resolveCredentialAndIntroduceIdent lookupTbl AssetClass assetBytes
    tellTriple
        (Triple cellSubj (PIri "rdf:first") (OBnode entryBnode))
    tellTriple
        (Triple cellSubj (PIri "rdf:rest") nextObj)
    tellTriple
        (Triple entrySubj PRdfType (OIri (vocabCurie TermAsset)))
    tellTriple
        ( Triple
            entrySubj
            (PIri (vocabCurie TermHasIdentifier))
            (OBnode assetIdBnode)
        )
    tellTriple
        ( Triple
            entrySubj
            (PIri (vocabCurie TermQuantity))
            (OIntLit qty)
        )

----------------------------------------------------------------------
-- Tx-block emission.
----------------------------------------------------------------------

{- | Emit the @_:tx@ subject block. Predicate order is fixed
(see the module-header note): the per-leaf @hasX@ edges first,
then @hasFee@, then the optional body-root predicates T107
introduced (validity interval, network id, script-data hash,
auxiliary-data hash). Each of the four optional fields is
elided when its body field is @SNothing@; the validity interval
also emits a separate @_:interval1@ sub-block carrying
@cardano:intervalStart@ and\/or @cardano:intervalEnd@.
-}
emitTxBlock ::
    Int ->
    Int ->
    Int ->
    Int ->
    Int ->
    Int ->
    Int ->
    Int ->
    Integer ->
    ValidityInterval ->
    StrictMaybe Network ->
    StrictMaybe ScriptIntegrityHash ->
    StrictMaybe TxAuxDataHash ->
    [KeyHash Guard] ->
    StrictMaybe Coin ->
    Bool ->
    Int ->
    Emit ()
emitTxBlock
    nInputs
    nReferenceInputs
    nOutputs
    nMints
    nWithdrawals
    nCerts
    nCollaterals
    nProposals
    feeLovelace
    validity
    networkId
    scriptDataHash
    auxDataHash
    requiredSigners
    totalCollateral
    hasCollateralReturnFlag
    nVotes = do
        let txSubj = SBnode (BnodeName "tx")
            tt p o = tellTriple (Triple txSubj p o)
            -- Emit one @cardano:hasX _:xK@ edge per k in
            -- @[1..n]@. Sequenced via 'mapM_' over the range so
            -- the writer accumulates them in ascending order.
            edges term mkBnode n =
                mapM_
                    ( tt (PIri (vocabCurie term)) . OBnode . mkBnode
                    )
                    [1 .. n]
        tt PRdfType (OIri (vocabCurie TermTransaction))
        edges TermHasInput idInputBnode nInputs
        edges TermHasReferenceInput idReferenceInputBnode nReferenceInputs
        edges TermHasOutput idOutputBnode nOutputs
        edges TermHasMint idMintBnode nMints
        edges TermHasWithdrawal idWithdrawalBnode nWithdrawals
        edges TermHasCertificate idCertBnode nCerts
        edges TermHasCollateralInput idCollateralBnode nCollaterals
        edges TermHasProposal idProposalBnode nProposals
        tt
            (PIri (vocabCurie TermHasFee))
            (OIntLit (fromIntegral feeLovelace))
        emitValidityInterval txSubj validity
        emitNetworkId txSubj networkId
        emitScriptDataHash txSubj scriptDataHash
        emitAuxiliaryDataHash txSubj auxDataHash
        emitRequiredSigners txSubj requiredSigners
        emitTotalCollateral txSubj totalCollateral
        emitCollateralReturnEdge txSubj hasCollateralReturnFlag
        edges TermHasVote idVoteBnode nVotes

{- | Emit @cardano:totalCollateral N@ when the body's total
collateral is @SJust@ (Conway's pre-declared collateral total in
lovelace). @SNothing@ elides the predicate entirely.

T117 / S16.
-}
emitTotalCollateral :: Subject -> StrictMaybe Coin -> Emit ()
emitTotalCollateral _ SNothing = pure ()
emitTotalCollateral txSubj (SJust (Coin n)) =
    tellTriple
        ( Triple
            txSubj
            (PIri (vocabCurie TermTotalCollateral))
            (OIntLit (fromIntegral n))
        )

{- | Emit @_:tx cardano:hasCollateralReturn _:collateralReturn1@
when the body carries a collateral-return output. The output's
own subject block (typed @cardano:Output@, with @cardano:atAddress@
+ @cardano:lovelace@) lives in its own body section emitted by
'buildCollateralReturn'.

T117 / S16.
-}
emitCollateralReturnEdge :: Subject -> Bool -> Emit ()
emitCollateralReturnEdge _ False = pure ()
emitCollateralReturnEdge txSubj True =
    tellTriple
        ( Triple
            txSubj
            (PIri (vocabCurie TermHasCollateralReturn))
            (OBnode idCollateralReturnBnode)
        )

{- | Emit one @cardano:hasRequiredSigner "\<hex\>"@ triple per
required-signer key-hash declared on the body. The set is
ascending-sorted so the emitted triples are deterministic across
runs; an empty set elides the predicate entirely (no triple).

T116 / S15. Closes the operator's 2026-05-21 crash mode
(@UnsupportedLeafType: ConwayRequiredSignersValue@) — required
signers are the key-hashes Plutus scripts consult via the script
context to gate spending.
-}
emitRequiredSigners :: Subject -> [KeyHash Guard] -> Emit ()
emitRequiredSigners txSubj = mapM_ emit1
  where
    emit1 (KeyHash h) =
        tellTriple
            ( Triple
                txSubj
                (PIri (vocabCurie TermHasRequiredSigner))
                (OStringLit (hexText (hashToBytes h)))
            )

{- | Emit the @cardano:hasValidityInterval _:interval1@ edge plus
the @_:interval1@ sub-block carrying @cardano:intervalStart@
and\/or @cardano:intervalEnd@. When both bounds are @SNothing@
the predicate is elided and no sub-block is emitted; otherwise
each bound is included only when @SJust@.
-}
emitValidityInterval :: Subject -> ValidityInterval -> Emit ()
emitValidityInterval txSubj (ValidityInterval before after) =
    case (before, after) of
        (SNothing, SNothing) -> pure ()
        _ -> do
            let intervalBnode = BnodeName "interval1"
                intervalSubj = SBnode intervalBnode
            tellTriple
                ( Triple
                    txSubj
                    (PIri (vocabCurie TermHasValidityInterval))
                    (OBnode intervalBnode)
                )
            case before of
                SNothing -> pure ()
                SJust (SlotNo s) ->
                    tellTriple
                        ( Triple
                            intervalSubj
                            (PIri (vocabCurie TermIntervalStart))
                            (OIntLit (fromIntegral s))
                        )
            case after of
                SNothing -> pure ()
                SJust (SlotNo s) ->
                    tellTriple
                        ( Triple
                            intervalSubj
                            (PIri (vocabCurie TermIntervalEnd))
                            (OIntLit (fromIntegral s))
                        )

{- | Emit @cardano:networkId N@ when the body's network id is
'SJust' (Testnet → 0, Mainnet → 1 per Cardano's wire encoding).
-}
emitNetworkId :: Subject -> StrictMaybe Network -> Emit ()
emitNetworkId _ SNothing = pure ()
emitNetworkId txSubj (SJust net) =
    tellTriple
        ( Triple
            txSubj
            (PIri (vocabCurie TermNetworkId))
            (OIntLit (fromIntegral (networkToWord8 net)))
        )

{- | Emit @cardano:scriptDataHash \"\<hex\>\"@ when the body's
script-integrity hash is 'SJust'. The 32-byte hash is rendered
as a hex string literal.
-}
emitScriptDataHash :: Subject -> StrictMaybe ScriptIntegrityHash -> Emit ()
emitScriptDataHash _ SNothing = pure ()
emitScriptDataHash txSubj (SJust h) =
    tellTriple
        ( Triple
            txSubj
            (PIri (vocabCurie TermScriptDataHash))
            (OStringLit (hexText (hashToBytes (extractHash h))))
        )

{- | Emit @cardano:auxiliaryDataHash \"\<hex\>\"@ when the body's
aux-data hash is 'SJust'. The 32-byte hash is rendered as a hex
string literal.
-}
emitAuxiliaryDataHash :: Subject -> StrictMaybe TxAuxDataHash -> Emit ()
emitAuxiliaryDataHash _ SNothing = pure ()
emitAuxiliaryDataHash txSubj (SJust (TxAuxDataHash h)) =
    tellTriple
        ( Triple
            txSubj
            (PIri (vocabCurie TermAuxiliaryDataHash))
            (OStringLit (hexText (hashToBytes (extractHash h))))
        )

----------------------------------------------------------------------
-- Address registry — first-occurrence-wins de-dup
----------------------------------------------------------------------

{- | One entry in the address-decomposition registry. Records the
bnode name the address resolves to plus the decoded payment +
stake credentials so the address subject block can be rendered
without re-parsing.
-}
data AddrEntry = AddrEntry
    { aeAddr :: !Addr
    , aeBnodeBase :: !Text
    -- ^ The base name (e.g. @"alice"@ when an entity covers the
    -- payment credential; @"addr_paymentkey_<bytes16>"@ when no
    -- entity covers it). The full address bnode is
    -- @\<base\>Addr@; the credential bnodes are
    -- @\<base\>CredPayment@ / @\<base\>CredStake@.
    , aePaymentCred :: !PaymentLeaf
    , aeStakeCred :: !(Maybe StakeLeaf)
    , aeBech32 :: !Text
    }
    deriving stock (Eq, Show)

-- | Payment credential leaf metadata.
data PaymentLeaf = PaymentLeaf
    { plLeafType :: !LeafType
    , plBytes :: !ByteString
    }
    deriving stock (Eq, Show)

-- | Stake credential leaf metadata.
data StakeLeaf = StakeLeaf
    { slLeafType :: !LeafType
    , slBytes :: !ByteString
    }
    deriving stock (Eq, Show)

{- | First-occurrence-wins address registry. The 'Map' keys on
'Addr'; the registry's element order is the order of first
encounter.
-}
data AddrRegistry = AddrRegistry
    { arSeen :: !(Map Addr Int)
    -- ^ first-occurrence index (0-based) so we can recover order.
    , arEntries :: ![AddrEntry]
    -- ^ entries in first-occurrence order, reversed (head = last
    -- inserted); 'addrRegistryEntries' un-reverses.
    }

emptyAddrRegistry :: AddrRegistry
emptyAddrRegistry =
    AddrRegistry Map.empty []

{- | Insert an address into the registry if not yet seen.
Returns the resolved 'AddrEntry' (existing or new).
-}
insertAddr ::
    [EntityDecl] ->
    LookupTable ->
    Addr ->
    AddrRegistry ->
    (AddrEntry, AddrRegistry)
insertAddr entities lookupTbl addr reg@AddrRegistry{arSeen, arEntries} =
    case Map.lookup addr arSeen of
        Just ix ->
            ( reverse arEntries !! ix
            , reg
            )
        Nothing ->
            let entry = mkAddrEntry entities lookupTbl addr
                ix = Map.size arSeen
             in ( entry
                , AddrRegistry
                    { arSeen = Map.insert addr ix arSeen
                    , arEntries = entry : arEntries
                    }
                )

-- | Walk the registry's entries in insertion order.
addrRegistryEntries :: AddrRegistry -> [AddrEntry]
addrRegistryEntries AddrRegistry{arEntries} = reverse arEntries

-- | Materialise an 'AddrEntry' from a decoded 'Addr'.
mkAddrEntry :: [EntityDecl] -> LookupTable -> Addr -> AddrEntry
mkAddrEntry entities _lookupTbl addr@(Addr network paymentCred stakeRef) =
    AddrEntry
        { aeAddr = addr
        , aeBnodeBase = base
        , aePaymentCred = pl
        , aeStakeCred = sl
        , aeBech32 = encodeBech32 network addr
        }
  where
    pl = paymentLeaf paymentCred
    sl = stakeLeaf stakeRef
    base = pickAddrBase entities pl
mkAddrEntry _ _ (AddrBootstrap _) =
    error "Cardano.Tx.Graph.Emit.Project: Byron address unexpected in Conway fixture"

paymentLeaf :: Credential payment -> PaymentLeaf
paymentLeaf = \case
    KeyHashObj (KeyHash h) -> PaymentLeaf PaymentKey (hashToBytes h)
    ScriptHashObj (ScriptHash h) ->
        PaymentLeaf PaymentScript (hashToBytes h)

stakeLeaf :: StakeReference -> Maybe StakeLeaf
stakeLeaf = \case
    StakeRefNull -> Nothing
    StakeRefPtr _ -> Nothing
    StakeRefBase (KeyHashObj (KeyHash h)) ->
        Just (StakeLeaf StakeKey (hashToBytes h))
    StakeRefBase (ScriptHashObj (ScriptHash h)) ->
        Just (StakeLeaf StakeScript (hashToBytes h))

{- | Pick the bnode base name for an address.

When an entity in @entities@ covers the payment credential's
@(leafType, bytes)@ pair, the base is the entity's slug (so the
address bnode becomes @\<slug\>Addr@ — matching the artisan
@_:aliceAddr@ form). Otherwise the base is the raw-bytes
credential identifier name (@cred_\<role\>_\<bytes16\>@) so the
generated triples share the namespace anchor with the
identifier bnode 'resolveCredential' returns.

Both forms produce uniform downstream suffixes:
@\<base\>Addr@, @\<base\>CredPayment@, @\<base\>CredStake@.
-}
pickAddrBase :: [EntityDecl] -> PaymentLeaf -> Text
pickAddrBase entities pl =
    case findEntityForLeaf entities (plLeafType pl) (plBytes pl) of
        Just slug -> slug
        Nothing ->
            "cred_"
                <> rolePrefixText (plLeafType pl)
                <> "_"
                <> Text.take 16 (hexText (plBytes pl))

findEntityForLeaf ::
    [EntityDecl] -> LeafType -> ByteString -> Maybe Text
findEntityForLeaf entities lt bytes =
    entitySlug
        <$> find
            ( any
                ( \i ->
                    entityIdLeafType i == lt
                        && entityIdBytesHex i == hexText bytes
                )
                . entityIdentifiers
            )
            entities

rolePrefixText :: LeafType -> Text
rolePrefixText = \case
    PaymentKey -> "paymentkey"
    PaymentScript -> "paymentscript"
    StakeKey -> "stakekey"
    StakeScript -> "stakescript"
    AssetClass -> "assetclass"
    Policy -> "policy"
    PoolId -> "poolid"
    DRepKey -> "drepkey"
    DRepScript -> "drepscript"

hexText :: ByteString -> Text
hexText = TextEncoding.decodeLatin1 . Base16.encode

----------------------------------------------------------------------
-- Inputs
----------------------------------------------------------------------

buildInputs ::
    [EntityDecl] ->
    LookupTable ->
    Map TxIn (TxOut ConwayEra) ->
    [TxIn] ->
    ([[SubjectBlock]], AddrRegistry)
buildInputs entities lookupTbl utxo = go [] emptyAddrRegistry . zip [1 ..]
  where
    go acc reg [] = (reverse acc, reg)
    go acc reg ((k, txIn) : rest) =
        case Map.lookup txIn utxo of
            Nothing ->
                let blocks =
                        clusterBlocks (emitUnresolvedInput k txIn)
                 in go (blocks : acc) reg rest
            Just resolved ->
                let (entry, reg') =
                        insertAddr
                            entities
                            lookupTbl
                            (resolved ^. addrTxOutL)
                            reg
                    blocks =
                        clusterBlocks
                            ( emitResolvedInput
                                lookupTbl
                                k
                                txIn
                                (aeBnodeBase entry)
                                (resolved ^. valueTxOutL)
                            )
                 in go (blocks : acc) reg' rest

{- | Emit triples for an input whose 'TxIn' is NOT resolved
under the operator-supplied UTxO map. T103: every input —
resolved or not — carries @cardano:fromTxOutRef
"\<txid\>#\<ix\>"@ as its first non-@rdf:type@ triple
(spec FR-004).
-}
emitUnresolvedInput :: Int -> TxIn -> Emit ()
emitUnresolvedInput k txIn = do
    let inputSubj = SBnode (idInputBnode k)
    tellTriple (Triple inputSubj PRdfType (OIri (vocabCurie TermInput)))
    tellTriple
        ( Triple
            inputSubj
            (PIri (vocabCurie TermFromTxOutRef))
            (OStringLit (formatTxIn txIn))
        )

{- | Emit triples for an input whose 'TxIn' IS resolved.
T103: the @cardano:fromTxOutRef@ literal sits between the
@rdf:type@ triple and the @cardano:resolvedTo@ edge so the
predicate order is uniform across resolved / unresolved
inputs. The shared address bnode base is passed in (it
comes from the 'AddrRegistry' first-occurrence-wins
lookup). T104 threads the resolved 'TxOut' value through so
the resolved-output subject carries @cardano:lovelace@ and
(when non-empty) the multi-asset RDF list.
-}
emitResolvedInput ::
    LookupTable -> Int -> TxIn -> Text -> MaryValue -> Emit ()
emitResolvedInput lookupTbl k txIn base value = do
    let inputSubj = SBnode (idInputBnode k)
        resolvedSubj = SBnode (idResolvedInputBnode k)
    tellTriple (Triple inputSubj PRdfType (OIri (vocabCurie TermInput)))
    tellTriple
        ( Triple
            inputSubj
            (PIri (vocabCurie TermFromTxOutRef))
            (OStringLit (formatTxIn txIn))
        )
    tellTriple
        ( Triple
            inputSubj
            (PIri (vocabCurie TermResolvedTo))
            (OBnode (idResolvedInputBnode k))
        )
    tellTriple (Triple resolvedSubj PRdfType (OIri (vocabCurie TermOutput)))
    tellTriple
        ( Triple
            resolvedSubj
            (PIri (vocabCurie TermAtAddress))
            (OBnode (BnodeName (base <> "Addr")))
        )
    emitOutputValue
        lookupTbl
        (ValueAnchor "resolvedInput" k)
        resolvedSubj
        value

{- | Render a 'TxIn' as the @cardano:fromTxOutRef@ literal:
@\<txid_hex\>#\<index\>@. The 'TxId' is the safe-hash of the
producing transaction; the 'TxIx' is its output position
(0-based, ledger semantics).
-}
formatTxIn :: TxIn -> Text
formatTxIn (TxIn (TxId safeHash) (TxIx index)) =
    hexText (hashToBytes (extractHash safeHash))
        <> "#"
        <> Text.pack (show index)

----------------------------------------------------------------------
-- Outputs
----------------------------------------------------------------------

buildOutputs ::
    [EntityDecl] ->
    LookupTable ->
    [TxOut ConwayEra] ->
    AddrRegistry ->
    ([[SubjectBlock]], AddrRegistry)
buildOutputs entities lookupTbl outputs reg0 =
    go [] reg0 (zip [1 ..] outputs)
  where
    -- Strict iteration: 'outputs' is a small list.
    go acc reg [] = (reverse acc, reg)
    go acc reg ((k, txOut) : rest) =
        let (entry, reg') =
                insertAddr
                    entities
                    lookupTbl
                    (txOut ^. addrTxOutL)
                    reg
            blocks =
                clusterBlocks
                    (emitOutput lookupTbl k (aeBnodeBase entry) txOut)
         in go (blocks : acc) reg' rest

{- | Emit triples for a body output at position @k@. T104 attaches
the output's @cardano:lovelace@ literal and (when the
multi-asset bundle is non-empty) the @cardano:hasAssetValue@
edge to an RDF-list head, followed by the per-asset-entry
blocks. T105 attaches a @cardano:hasDatum@ edge (with a
@cardano:Datum@-typed sub-block carrying @cardano:hasHash@,
plus @cardano:hasRawBytes@ for inline datums) when the output
carries a datum, and a @cardano:hasReferenceScript@ edge (with
a sub-block carrying @cardano:hasHash@ + @cardano:hasRawBytes@)
when the output carries a reference script. Outputs with
neither datum nor reference script keep their pre-T105 shape.
-}
emitOutput :: LookupTable -> Int -> Text -> TxOut ConwayEra -> Emit ()
emitOutput lookupTbl k base txOut = do
    let outSubj = SBnode (idOutputBnode k)
        value = txOut ^. valueTxOutL
        datum = txOut ^. datumTxOutL
        refScript = txOut ^. referenceScriptTxOutL
    tellTriple (Triple outSubj PRdfType (OIri (vocabCurie TermOutput)))
    tellTriple
        ( Triple
            outSubj
            (PIri (vocabCurie TermAtAddress))
            (OBnode (BnodeName (base <> "Addr")))
        )
    emitOutputValue lookupTbl (ValueAnchor "output" k) outSubj value
    emitOutputDatum k outSubj datum
    emitOutputReferenceScript k outSubj refScript

{- | Emit the @cardano:hasDatum@ edge + per-datum sub-block for an
output at position @k@ when the output carries a datum.
@DatumHash@-only outputs emit @cardano:hasHash@ alone; inline
@Datum@ outputs additionally emit @cardano:hasRawBytes@ — the
presence of @hasRawBytes@ is the distinguisher between the two
shapes (per D-002). Outputs with @NoDatum@ emit nothing.
-}
emitOutputDatum :: Int -> Subject -> Datum ConwayEra -> Emit ()
emitOutputDatum _ _ NoDatum = pure ()
emitOutputDatum k outSubj (DatumHash dh) = do
    let datumBnode = idOutputDatumBnode k
        datumSubj = SBnode datumBnode
        hashBytes = hashToBytes (extractHash dh)
    tellTriple
        ( Triple
            outSubj
            (PIri (vocabCurie TermHasDatum))
            (OBnode datumBnode)
        )
    tellTriple (Triple datumSubj PRdfType (OIri (vocabCurie TermDatum)))
    tellTriple
        ( Triple
            datumSubj
            (PIri (vocabCurie TermHasHash))
            (OStringLit (hexText hashBytes))
        )
emitOutputDatum k outSubj (Datum binaryData) = do
    let datumBnode = idOutputDatumBnode k
        datumSubj = SBnode datumBnode
        hashBytes = hashToBytes (extractHash (hashBinaryData binaryData))
        rawBytes = originalBytes binaryData
    tellTriple
        ( Triple
            outSubj
            (PIri (vocabCurie TermHasDatum))
            (OBnode datumBnode)
        )
    tellTriple (Triple datumSubj PRdfType (OIri (vocabCurie TermDatum)))
    tellTriple
        ( Triple
            datumSubj
            (PIri (vocabCurie TermHasHash))
            (OStringLit (hexText hashBytes))
        )
    tellTriple
        ( Triple
            datumSubj
            (PIri (vocabCurie TermHasRawBytes))
            (OStringLit (hexText rawBytes))
        )

{- | Emit the @cardano:hasReferenceScript@ edge + per-script
sub-block for an output at position @k@ when the output carries
a reference script.

T118 / S17 adds the script-language discrimination: the script
bnode is typed @cardano:PlutusScript@ (with a
@cardano:hasVersion N@ literal where N is the Plutus version
1/2/3) when @toPlutusScript@ returns @Just@, and
@cardano:NativeScript@ when it returns @Nothing@ (a Conway-era
@TimelockScript@). Both branches keep @cardano:hasHash@ +
@cardano:hasRawBytes@. Outputs with no reference script emit
nothing.
-}
emitOutputReferenceScript ::
    Int -> Subject -> StrictMaybe (Script ConwayEra) -> Emit ()
emitOutputReferenceScript _ _ SNothing = pure ()
emitOutputReferenceScript k outSubj (SJust script) = do
    let scriptBnode = idOutputRefScriptBnode k
        scriptSubj = SBnode scriptBnode
        ScriptHash hh = hashScript script
        hashBytes = hashToBytes hh
        rawBytes = originalBytes script
        (classTerm, mVersion) = case toPlutusScript script of
            Just ps ->
                ( TermPlutusScript
                , Just (plutusVersionInt (plutusScriptLanguage ps))
                )
            Nothing -> (TermNativeScript, Nothing)
    tellTriple
        ( Triple
            outSubj
            (PIri (vocabCurie TermHasReferenceScript))
            (OBnode scriptBnode)
        )
    tellTriple (Triple scriptSubj PRdfType (OIri (vocabCurie classTerm)))
    tellTriple
        ( Triple
            scriptSubj
            (PIri (vocabCurie TermHasHash))
            (OStringLit (hexText hashBytes))
        )
    tellTriple
        ( Triple
            scriptSubj
            (PIri (vocabCurie TermHasRawBytes))
            (OStringLit (hexText rawBytes))
        )
    case mVersion of
        Nothing -> pure ()
        Just v ->
            tellTriple
                ( Triple
                    scriptSubj
                    (PIri (vocabCurie TermHasVersion))
                    (OIntLit (fromIntegral v))
                )

-- | Map ledger 'Language' to its Plutus version integer.
plutusVersionInt :: Language -> Int
plutusVersionInt = \case
    PlutusV1 -> 1
    PlutusV2 -> 2
    PlutusV3 -> 3
    PlutusV4 -> 4

----------------------------------------------------------------------
-- Address decomposition blocks
----------------------------------------------------------------------

{- | Emit triples for an 'AddrEntry' — one address block plus
its payment credential block plus (optionally) its stake
credential block.

The address subject is wrapped in 'introduce' so re-walking
the same registry entry never re-emits the block. The
address-decomposition section is the canonical home of the
T102 dedup invariant: when fixtures with shared addresses
(01, 11) flow through, each unique address bnode appears
exactly once.
-}
emitAddrEntry :: LookupTable -> AddrEntry -> Emit ()
emitAddrEntry
    lookupTbl
    AddrEntry{aeBnodeBase, aePaymentCred, aeStakeCred, aeBech32} = do
        let addrBnode = BnodeName (aeBnodeBase <> "Addr")
            payCredBnode = BnodeName (aeBnodeBase <> "CredPayment")
            stakeCredBnode = BnodeName (aeBnodeBase <> "CredStake")
            addrSubj = SBnode addrBnode
            payCredSubj = SBnode payCredBnode
            stakeCredSubj = SBnode stakeCredBnode
        introduce addrSubj $ do
            tellTriple
                (Triple addrSubj PRdfType (OIri (vocabCurie TermAddress)))
            tellTriple
                ( Triple
                    addrSubj
                    (PIri (vocabCurie TermBech32))
                    (OStringLit aeBech32)
                )
            tellTriple
                ( Triple
                    addrSubj
                    (PIri (vocabCurie TermHasPaymentCredential))
                    (OBnode payCredBnode)
                )
            -- Emit the @hasStakeCredential@ edge only when the
            -- address carries a stake credential — Maybe-driven.
            case aeStakeCred of
                Nothing -> pure ()
                Just _ ->
                    tellTriple
                        ( Triple
                            addrSubj
                            (PIri (vocabCurie TermHasStakeCredential))
                            (OBnode stakeCredBnode)
                        )
        payIdBnode <-
            resolveCredentialAndIntroduceIdent
                lookupTbl
                (plLeafType aePaymentCred)
                (plBytes aePaymentCred)
        introduce payCredSubj $ do
            tellTriple
                ( Triple
                    payCredSubj
                    PRdfType
                    (OIri (vocabCurie TermPaymentCredential))
                )
            tellTriple
                ( Triple
                    payCredSubj
                    (PIri (vocabCurie TermHasIdentifier))
                    (OBnode payIdBnode)
                )
        case aeStakeCred of
            Nothing -> pure ()
            Just sl -> do
                stakeIdBnode <-
                    resolveCredentialAndIntroduceIdent
                        lookupTbl
                        (slLeafType sl)
                        (slBytes sl)
                introduce stakeCredSubj $ do
                    tellTriple
                        ( Triple
                            stakeCredSubj
                            PRdfType
                            (OIri (vocabCurie TermStakeCredential))
                        )
                    tellTriple
                        ( Triple
                            stakeCredSubj
                            (PIri (vocabCurie TermHasIdentifier))
                            (OBnode stakeIdBnode)
                        )

----------------------------------------------------------------------
-- Mint cluster (T007 — fixture 04)
----------------------------------------------------------------------

{- | Emit the two subject blocks for one mint entry at position
@k@: the @cardano:Mint@ cluster header carrying
@cardano:mintsAsset _:assetN@ + @cardano:quantity \<signed-integer\>@,
plus a @cardano:Asset@ block for the @policy ++ asset-name@
identifier. The signed-integer literal mirrors the ledger
@MultiAsset@ quantity — negative values denote burns and render
as e.g. @-5@.

Per research R2, the @AssetClass@ identifier's @bytesHex@ is the
concatenation of the 28-byte policy hash and the raw bytes of the
asset name; the lookup table follows the same convention. The
policy identifier itself is implicit in the asset identifier's
leading 28 bytes, so the T106 / D-004 shape no longer emits a
standalone @cardano:Policy@ block.
-}
emitMintCluster ::
    LookupTable -> Int -> PolicyID -> AssetName -> Integer -> Emit ()
emitMintCluster lookupTbl k policyId assetName quantity = do
    let policyBytes = policyIdBytes policyId
        assetBytes = policyBytes <> assetClassNameBytes assetName
        mintSubj = SBnode (idMintBnode k)
        assetSubj = SBnode (idAssetBnode k)
    assetIdBnode <-
        resolveCredentialAndIntroduceIdent lookupTbl AssetClass assetBytes
    tellTriple (Triple mintSubj PRdfType (OIri (vocabCurie TermMint)))
    tellTriple
        ( Triple
            mintSubj
            (PIri (vocabCurie TermMintsAsset))
            (OBnode (idAssetBnode k))
        )
    tellTriple
        ( Triple
            mintSubj
            (PIri (vocabCurie TermQuantity))
            (OIntLit quantity)
        )
    tellTriple (Triple assetSubj PRdfType (OIri (vocabCurie TermAsset)))
    tellTriple
        ( Triple
            assetSubj
            (PIri (vocabCurie TermHasIdentifier))
            (OBnode assetIdBnode)
        )

policyIdBytes :: PolicyID -> ByteString
policyIdBytes (PolicyID (ScriptHash h)) = hashToBytes h

assetClassNameBytes :: AssetName -> ByteString
assetClassNameBytes (AssetName sbs) = SBS.fromShort sbs

----------------------------------------------------------------------
-- Withdrawal cluster (T007 — fixture 05)
----------------------------------------------------------------------

{- | Emit the @cardano:Withdrawal@ subject block for one
withdrawal at position @k@. The cluster carries
@cardano:withdrawalAccount@ — pointing at the reward-account
stake credential's identifier bnode (entity-named when an entity
covers it, raw-bytes-named otherwise) — and @cardano:lovelace@ —
the withdrawn amount as an integer literal.

T106 / D-005 replaces the #58-inherited @cardano:onCredential@ +
@cardano:withAmount@ pair with the canonical kmaps names; the
identifier-bnode lookup logic is unchanged so an operator-entity
overlay continues to redirect raw-bytes bnodes into the
entity-named reward-account identifier when one is declared.

R2 wires withdrawal stake credentials as @StakeKey@ (key-hash
credential) or @StakeScript@ (script-hash credential). T007's
harness fixture 05 exercises the key-hash case; T010 may
encounter the script-hash case in fixture 11.
-}
emitWithdrawalCluster ::
    LookupTable -> Int -> AccountAddress -> Coin -> Emit ()
emitWithdrawalCluster lookupTbl k account (Coin lovelace) = do
    let (leafTy, credBytes) = accountStakeLeaf account
        wSubj = SBnode (idWithdrawalBnode k)
    credIdBnode <-
        resolveCredentialAndIntroduceIdent lookupTbl leafTy credBytes
    tellTriple (Triple wSubj PRdfType (OIri (vocabCurie TermWithdrawal)))
    tellTriple
        ( Triple
            wSubj
            (PIri (vocabCurie TermWithdrawalAccount))
            (OBnode credIdBnode)
        )
    tellTriple
        ( Triple
            wSubj
            (PIri (vocabCurie TermLovelace))
            (OIntLit (fromIntegral lovelace))
        )

accountStakeLeaf :: AccountAddress -> (LeafType, ByteString)
accountStakeLeaf (AccountAddress _ (AccountId cred)) =
    case cred of
        KeyHashObj (KeyHash h) -> (StakeKey, hashToBytes h)
        ScriptHashObj (ScriptHash h) -> (StakeScript, hashToBytes h)

----------------------------------------------------------------------
-- Certificate cluster (T008 — fixtures 06, 07)
----------------------------------------------------------------------

{- | Build the subject blocks for one certificate at position @k@.

T008 ships the @StakeDelegation@ + @VoteDelegation@ variants the
harness exercises via @stubStakeDelegationCert@ (S06) and
@stubVoteDelegationCert@ (S07): each renders the cert cluster
plus a target-leaf block (@cardano:Pool@ for stake delegation,
@cardano:DRep@ for vote delegation).

== Policy: fail-loudly on unsupported cert variants (T008 A-001 D3)

Cert variants not exercised by the post-#45 harness raise
'PUnsupportedLeafType' rather than silently emitting partial
triples. Future slices that need a variant extend this function
explicitly.

Unsupported as of T008:

* @DelegTxCert _ (DelegVote DRepAlwaysAbstain)@ — no @hasIdentifier@ link.
* @DelegTxCert _ (DelegVote DRepAlwaysNoConfidence)@ — no @hasIdentifier@ link.
* @DelegTxCert _ DelegStakeVote{}@ — combined stake + vote delegation.
* All non-@DelegTxCert@ variants (@RegCert@, @UnRegCert@,
  @RegDepositTxCert@, @UnRegDepositTxCert@, @RegDepositDelegTxCert@,
  pool certs (@RegPoolCert@ / @RetirePoolCert@), governance /
  committee / DRep registration certs).

The @DRepScriptHash@ DRep variant is supported (handled identically
to @DRepKeyHash@ via the 'DRepScript' leaf type) even though no
current fixture exercises it — the branch is trivial and keeps the
DRep case symmetric with the on-credential side.
-}
buildCertCluster ::
    LookupTable ->
    Int ->
    TxCert ConwayEra ->
    [SubjectBlock]
buildCertCluster lookupTbl k = \case
    DelegTxCert cred (DelegStake (KeyHash poolHash)) ->
        clusterBlocks
            (emitStakeDelegation lookupTbl k cred (hashToBytes poolHash))
    DelegTxCert cred (DelegVote (DRepKeyHash (KeyHash drepHash))) ->
        clusterBlocks
            ( emitVoteDelegation
                lookupTbl
                k
                cred
                DRepKey
                (hashToBytes drepHash)
            )
    DelegTxCert cred (DelegVote (DRepScriptHash (ScriptHash drepHash))) ->
        clusterBlocks
            ( emitVoteDelegation
                lookupTbl
                k
                cred
                DRepScript
                (hashToBytes drepHash)
            )
    -- T120 / S19: all remaining Conway cert constructors fall
    -- through to the OpaqueLeaf fallback shape — typed
    -- @cardano:Certificate, cardano:OpaqueLeaf@ with @cardano:leafType@
    -- discriminating the variant and @cardano:hasRawBytes@ carrying
    -- the CBOR wire encoding. This keeps the emit walker total over
    -- TxCert ConwayEra without designing a typed shape for every
    -- governance / registration variant at once.
    cert -> clusterBlocks (emitCertOpaqueLeaf k (certVariantTag cert) cert)

{- | Emit an OpaqueLeaf fallback for a cert variant whose typed
RDF shape hasn't been designed yet.

@
_:certK a cardano:Certificate, cardano:OpaqueLeaf ;
  cardano:leafType "\<variantTag\>" ;
  cardano:hasRawBytes "\<cbor-hex\>" .
@
-}
emitCertOpaqueLeaf :: Int -> Text -> TxCert ConwayEra -> Emit ()
emitCertOpaqueLeaf k variantTag cert = do
    let certSubj = SBnode (idCertBnode k)
        rawBytes = serialize' (eraProtVerLow @ConwayEra) cert
    tellTriple
        (Triple certSubj PRdfType (OIri (vocabCurie TermCertificate)))
    tellTriple
        (Triple certSubj PRdfType (OIri (vocabCurie TermOpaqueLeaf)))
    tellTriple
        ( Triple
            certSubj
            (PIri (vocabCurie TermLeafType))
            (OStringLit variantTag)
        )
    tellTriple
        ( Triple
            certSubj
            (PIri (vocabCurie TermHasRawBytes))
            (OStringLit (hexText rawBytes))
        )

{- | Stable variant-tag string for any Conway 'TxCert' constructor —
the literal that appears in the @cardano:leafType@ predicate of
the OpaqueLeaf fallback. Total over all constructors so the
emit walker is exhaustive at the type level (T120 / S19).
-}
certVariantTag :: TxCert ConwayEra -> Text
certVariantTag = \case
    -- Conway stake-credential certs.
    RegDepositTxCert{} -> "ConwayRegDeposit"
    UnRegDepositTxCert{} -> "ConwayUnRegDeposit"
    RegDepositDelegTxCert{} -> "ConwayRegDepositDeleg"
    DelegTxCert _ DelegStake{} ->
        -- Covered by the rich StakeDelegation case-arm above;
        -- reachable here only via the catch-all if someone
        -- passes a DelegStake-with-non-KeyHash pool variant
        -- (presently impossible). Tag kept for completeness.
        "ConwayDelegStakeNonKeyHash"
    DelegTxCert _ DelegVote{} ->
        -- DelegVote DRepAlwaysAbstain / DRepAlwaysNoConfidence
        -- variants — typed pre-aggregated DRep targets that
        -- don't fit the on-credential / to-DRep cert shape.
        "ConwayDelegVoteAggregateDRep"
    DelegTxCert _ DelegStakeVote{} -> "ConwayDelegStakeVote"
    -- Conway governance certs.
    RegDRepTxCert{} -> "ConwayRegDRep"
    UnRegDRepTxCert{} -> "ConwayUnRegDRep"
    UpdateDRepTxCert{} -> "ConwayUpdateDRep"
    AuthCommitteeHotKeyTxCert{} -> "ConwayAuthCommitteeHotKey"
    ResignCommitteeColdTxCert{} -> "ConwayResignCommitteeColdKey"
    -- Pre-Conway-era pass-throughs (still encoded under the
    -- Conway tx type for backwards compatibility). The rich
    -- StakeDelegation case-arm above captures the DelegStake
    -- pass-through; the remaining stake reg/dereg + pool reg/retire
    -- fall here.
    _ -> "ConwayLegacyCertPassThrough"

emitStakeDelegation ::
    LookupTable ->
    Int ->
    Credential Staking ->
    ByteString ->
    Emit ()
emitStakeDelegation lookupTbl k stakeCred poolBytes = do
    let (stakeLT, stakeBytes) = stakeCredLeaf stakeCred
        certSubj = SBnode (idCertBnode k)
        poolSubj = SBnode (idPoolBnode k)
    stakeIdBnode <-
        resolveCredentialAndIntroduceIdent lookupTbl stakeLT stakeBytes
    poolIdBnode <-
        resolveCredentialAndIntroduceIdent lookupTbl PoolId poolBytes
    tellTriple
        ( Triple
            certSubj
            PRdfType
            (OIri (vocabCurie TermStakeDelegation))
        )
    tellTriple
        ( Triple
            certSubj
            (PIri (vocabCurie TermOnCredential))
            (OBnode stakeIdBnode)
        )
    tellTriple
        ( Triple
            certSubj
            (PIri (vocabCurie TermToPool))
            (OBnode (idPoolBnode k))
        )
    tellTriple (Triple poolSubj PRdfType (OIri (vocabCurie TermPool)))
    tellTriple
        ( Triple
            poolSubj
            (PIri (vocabCurie TermHasIdentifier))
            (OBnode poolIdBnode)
        )

emitVoteDelegation ::
    LookupTable ->
    Int ->
    Credential Staking ->
    LeafType ->
    ByteString ->
    Emit ()
emitVoteDelegation lookupTbl k stakeCred drepLT drepBytes = do
    let (stakeLT, stakeBytes) = stakeCredLeaf stakeCred
        certSubj = SBnode (idCertBnode k)
        drepSubj = SBnode (idDRepBnode k)
    stakeIdBnode <-
        resolveCredentialAndIntroduceIdent lookupTbl stakeLT stakeBytes
    drepIdBnode <-
        resolveCredentialAndIntroduceIdent lookupTbl drepLT drepBytes
    tellTriple
        ( Triple
            certSubj
            PRdfType
            (OIri (vocabCurie TermVoteDelegation))
        )
    tellTriple
        ( Triple
            certSubj
            (PIri (vocabCurie TermOnCredential))
            (OBnode stakeIdBnode)
        )
    tellTriple
        ( Triple
            certSubj
            (PIri (vocabCurie TermToDRep))
            (OBnode (idDRepBnode k))
        )
    tellTriple (Triple drepSubj PRdfType (OIri (vocabCurie TermDRep)))
    tellTriple
        ( Triple
            drepSubj
            (PIri (vocabCurie TermHasIdentifier))
            (OBnode drepIdBnode)
        )

stakeCredLeaf :: Credential Staking -> (LeafType, ByteString)
stakeCredLeaf = \case
    KeyHashObj (KeyHash h) -> (StakeKey, hashToBytes h)
    ScriptHashObj (ScriptHash h) -> (StakeScript, hashToBytes h)

----------------------------------------------------------------------
-- Collateral inputs (T010 — fixtures 01, 08, 11)
----------------------------------------------------------------------

{- | Build per-collateral-input cluster blocks. Each collateral
input renders as @_:collateralK a cardano:Input .@ plus, when the
input's 'TxIn' resolves under @utxo@, a @cardano:resolvedTo@
predicate pointing at a resolved-output block whose
@cardano:atAddress@ target reuses the shared address registry.

Collateral inputs reuse the @cardano:Input@ class (rather than
introducing a separate @cardano:CollateralInput@); only the
@_:tx@ binding predicate is collateral-specific
(@cardano:hasCollateralInput@), matching the artisan layout
shipped by #45 for fixtures 01 + 11.
-}
buildCollaterals ::
    [EntityDecl] ->
    LookupTable ->
    Map TxIn (TxOut ConwayEra) ->
    [TxIn] ->
    AddrRegistry ->
    ([[SubjectBlock]], AddrRegistry)
buildCollaterals entities lookupTbl utxo txIns reg0 =
    go [] reg0 (zip [1 ..] txIns)
  where
    go acc reg [] = (reverse acc, reg)
    go acc reg ((k, txIn) : rest) =
        case Map.lookup txIn utxo of
            Nothing ->
                let blocks = clusterBlocks (emitUnresolvedCollateral k txIn)
                 in go (blocks : acc) reg rest
            Just resolved ->
                let (entry, reg') =
                        insertAddr
                            entities
                            lookupTbl
                            (resolved ^. addrTxOutL)
                            reg
                    blocks =
                        clusterBlocks
                            ( emitResolvedCollateral
                                lookupTbl
                                k
                                txIn
                                (aeBnodeBase entry)
                                (resolved ^. valueTxOutL)
                            )
                 in go (blocks : acc) reg' rest

{- | Emit triples for a collateral input whose 'TxIn' is NOT
resolved. Shape mirrors 'emitUnresolvedInput' — T103 adds
the @cardano:fromTxOutRef@ literal.
-}
emitUnresolvedCollateral :: Int -> TxIn -> Emit ()
emitUnresolvedCollateral k txIn = do
    let collSubj = SBnode (idCollateralBnode k)
    tellTriple (Triple collSubj PRdfType (OIri (vocabCurie TermInput)))
    tellTriple
        ( Triple
            collSubj
            (PIri (vocabCurie TermFromTxOutRef))
            (OStringLit (formatTxIn txIn))
        )

{- | Emit triples for a collateral input whose 'TxIn' IS
resolved. Shape mirrors 'emitResolvedInput' with the
collateral-specific @resolvedCollateralN@ bnode. T103 adds
the @cardano:fromTxOutRef@ literal between the @rdf:type@
triple and the @cardano:resolvedTo@ edge; T104 attaches the
resolved-output value triples (lovelace + optional MA list).
-}
emitResolvedCollateral ::
    LookupTable -> Int -> TxIn -> Text -> MaryValue -> Emit ()
emitResolvedCollateral lookupTbl k txIn base value = do
    let collSubj = SBnode (idCollateralBnode k)
        resolvedSubj = SBnode (idResolvedCollateralBnode k)
    tellTriple (Triple collSubj PRdfType (OIri (vocabCurie TermInput)))
    tellTriple
        ( Triple
            collSubj
            (PIri (vocabCurie TermFromTxOutRef))
            (OStringLit (formatTxIn txIn))
        )
    tellTriple
        ( Triple
            collSubj
            (PIri (vocabCurie TermResolvedTo))
            (OBnode (idResolvedCollateralBnode k))
        )
    tellTriple (Triple resolvedSubj PRdfType (OIri (vocabCurie TermOutput)))
    tellTriple
        ( Triple
            resolvedSubj
            (PIri (vocabCurie TermAtAddress))
            (OBnode (BnodeName (base <> "Addr")))
        )
    emitOutputValue
        lookupTbl
        (ValueAnchor "resolvedCollateral" k)
        resolvedSubj
        value

----------------------------------------------------------------------
-- Collateral return (T117 — single-output sub-block under _:tx)
----------------------------------------------------------------------

{- | Build the collateral-return output's sub-block when the body
carries one. Threads through the shared address registry so the
return output's address dedups against the rest of the body's
addresses. Returns @[]@ when the body's collateral-return is
'SNothing'.
-}
buildCollateralReturn ::
    [EntityDecl] ->
    LookupTable ->
    StrictMaybe (TxOut ConwayEra) ->
    AddrRegistry ->
    ([[SubjectBlock]], AddrRegistry)
buildCollateralReturn _ _ SNothing reg = ([], reg)
buildCollateralReturn entities lookupTbl (SJust txOut) reg =
    let (entry, reg') =
            insertAddr entities lookupTbl (txOut ^. addrTxOutL) reg
        blocks =
            clusterBlocks
                ( emitCollateralReturn
                    lookupTbl
                    (aeBnodeBase entry)
                    txOut
                )
     in ([blocks], reg')

{- | Emit the @_:collateralReturn1 a cardano:Output ;
cardano:atAddress _:addr ; cardano:lovelace N@ sub-block for the
body's single collateral-return output. Datum and reference
scripts on a collateral-return output are unusual on real chain
but supported: the per-output datum / ref-script emission paths
that 'emitOutput' uses are reused here verbatim.
-}
emitCollateralReturn ::
    LookupTable -> Text -> TxOut ConwayEra -> Emit ()
emitCollateralReturn lookupTbl base txOut = do
    let outSubj = SBnode idCollateralReturnBnode
        value = txOut ^. valueTxOutL
        datum = txOut ^. datumTxOutL
        refScript = txOut ^. referenceScriptTxOutL
    tellTriple (Triple outSubj PRdfType (OIri (vocabCurie TermOutput)))
    tellTriple
        ( Triple
            outSubj
            (PIri (vocabCurie TermAtAddress))
            (OBnode (BnodeName (base <> "Addr")))
        )
    emitOutputValue
        lookupTbl
        (ValueAnchor "collateralReturn" 1)
        outSubj
        value
    -- Reuse the per-output datum + ref-script emission paths
    -- with k = 0 so the bnode names (outputDatum0,
    -- outputRefScript0) do not collide with regular outputs at
    -- positions [1..]. T117 / S16.
    emitOutputDatum 0 outSubj datum
    emitOutputReferenceScript 0 outSubj refScript

----------------------------------------------------------------------
-- Reference inputs (T103 — fixture 11)
----------------------------------------------------------------------

{- | Build per-reference-input cluster blocks. Each reference
input renders as @_:refInputK a cardano:Input ;
cardano:fromTxOutRef "\<txid\>#\<ix\>"@. The class is
@cardano:Input@ — same as spending and collateral inputs
(D-003); only the @_:tx@ binding predicate
(@cardano:hasReferenceInput@) distinguishes the position.
T103 does not surface @cardano:resolvedTo@ for reference
inputs — the resolved-output payload arrives across T104+T105.
-}
buildReferenceInputs :: [TxIn] -> [[SubjectBlock]]
buildReferenceInputs txIns =
    [ clusterBlocks (emitReferenceInput k txIn)
    | (k, txIn) <- zip [1 :: Int ..] txIns
    ]

-- | Emit triples for a reference input at position @k@.
emitReferenceInput :: Int -> TxIn -> Emit ()
emitReferenceInput k txIn = do
    let refSubj = SBnode (idReferenceInputBnode k)
    tellTriple (Triple refSubj PRdfType (OIri (vocabCurie TermInput)))
    tellTriple
        ( Triple
            refSubj
            (PIri (vocabCurie TermFromTxOutRef))
            (OStringLit (formatTxIn txIn))
        )

----------------------------------------------------------------------
-- Proposal cluster (T010 — fixture 10)
----------------------------------------------------------------------

{- | Build the cluster of subject blocks for one proposal at
position @k@.

T108 / S7 introduced the D-006 fallback shape; T121 / S20
generalizes it across every Conway 'GovAction' constructor so
the emit walker is total over 'ProposalProcedure ConwayEra'.

Every proposal emits:

@
_:proposalK cardano:hasDatum _:proposalDatumK .
_:proposalDatumK a cardano:Datum ;
  cardano:decodedAs "\<varietyTag\>" ;
  cardano:hasRawBytes "\<cbor-hex\>" .
@

The variety tag names the 'GovAction' constructor
(@TreasuryWithdrawals@, @ParameterChange@,
@HardForkInitiation@, @NoConfidence@, @UpdateCommittee@,
@NewConstitution@, @InfoAction@) so SPARQL views can
@FILTER@ on it. The CBOR raw bytes are the full
@ProposalProcedure@ wire encoding via 'serialize'' at
'eraProtVerLow' for 'ConwayEra'.

The proposer's return-address and the per-variant inner
shape (treasury withdrawal targets, parameter-change deltas,
hard-fork target version, committee membership tuples,
constitution anchor) are still folded into the @hasRawBytes@
literal — typed RDF decomposition for those is deferred to a
follow-on (typed datum decoding via CIP-57 blueprints, #50).
-}
buildProposalCluster ::
    Int ->
    ProposalProcedure ConwayEra ->
    [SubjectBlock]
buildProposalCluster k proposal@(ProposalProcedure _ _ action _) =
    clusterBlocks (emitProposalDatumFallback k (govActionTag action) proposal)

{- | Stable variety-tag string for any Conway 'GovAction'
constructor — the literal that appears in the proposal datum
sub-block's @cardano:decodedAs@ predicate. Total over all
constructors so the emit walker is exhaustive at the type
level (T121 / S20).
-}
govActionTag :: GovAction ConwayEra -> Text
govActionTag = \case
    TreasuryWithdrawals{} -> "TreasuryWithdrawals"
    ParameterChange{} -> "ParameterChange"
    HardForkInitiation{} -> "HardForkInitiation"
    NoConfidence{} -> "NoConfidence"
    UpdateCommittee{} -> "UpdateCommittee"
    NewConstitution{} -> "NewConstitution"
    InfoAction{} -> "InfoAction"

{- | Emit the D-006 fallback shape for a proposal at position @k@:
@_:proposalK cardano:hasDatum _:proposalDatumK@ on the proposal
subject, plus a typed @_:proposalDatumK a cardano:Datum ;
cardano:decodedAs "\<variety\>" ; cardano:hasRawBytes "\<cbor-hex\>"@
sub-block. The raw bytes are the CBOR wire-encoding of the
@ProposalProcedure@ at the Conway era's protocol version (per the
ledger's 'EncCBOR' instance).
-}
emitProposalDatumFallback ::
    Int ->
    Text ->
    ProposalProcedure ConwayEra ->
    Emit ()
emitProposalDatumFallback k variety proposal = do
    let propSubj = SBnode (idProposalBnode k)
        datumBnode = idProposalDatumBnode k
        datumSubj = SBnode datumBnode
        rawBytes = serialize' (eraProtVerLow @ConwayEra) proposal
    tellTriple
        ( Triple
            propSubj
            (PIri (vocabCurie TermHasDatum))
            (OBnode datumBnode)
        )
    tellTriple (Triple datumSubj PRdfType (OIri (vocabCurie TermDatum)))
    tellTriple
        ( Triple
            datumSubj
            (PIri (vocabCurie TermDecodedAs))
            (OStringLit variety)
        )
    tellTriple
        ( Triple
            datumSubj
            (PIri (vocabCurie TermHasRawBytes))
            (OStringLit (hexText rawBytes))
        )

----------------------------------------------------------------------
-- Voting procedures (T119 — voter discrimination + verdict + anchor)
----------------------------------------------------------------------

{- | Flatten 'VotingProcedures' into a deterministic list of
@(voter, govActionId, procedure)@ triples in ascending voter
then ascending govActionId order. The underlying
@Map Voter (Map GovActionId VotingProcedure)@ is already
'Map.toAscList'-orderable, so the flattening preserves a
canonical, byte-stable iteration.
-}
flattenVotingProcedures ::
    VotingProcedures ConwayEra ->
    [(Voter, GovActionId, VotingProcedure ConwayEra)]
flattenVotingProcedures =
    foldrVotingProcedures (\v g p acc -> (v, g, p) : acc) []

{- | Build the subject blocks for one vote at position @k@.

== Shape

@
_:voteK a cardano:Vote ;
        cardano:hasVoter _:voterK ;
        cardano:hasVotingAction "\<txid\>#\<ix\>" ;
        cardano:hasVerdict "Yes" | "No" | "Abstain" ;
        cardano:hasAnchor _:voteAnchorK .  -- when SJust
@

@_:voterK@ carries one of three discriminating @rdf:type@
triples (@cardano:VoterDRep@ / @cardano:VoterStakePool@ /
@cardano:VoterCommitteeCold@) plus a @cardano:hasIdentifier@
predicate carrying the 28-byte key/script hash as a hex
literal.

When the procedure carries an 'Anchor', @_:voteAnchorK@ carries
@cardano:anchorUrl "url"@ + @cardano:anchorHash "hex"@.
-}
buildVoteCluster ::
    Int ->
    Voter ->
    GovActionId ->
    VotingProcedure ConwayEra ->
    Emit ()
buildVoteCluster k voter actionId procedure = do
    let voteSubj = SBnode (idVoteBnode k)
        voterSubj = SBnode (idVoterBnode k)
        VotingProcedure vote mAnchor = procedure
    tellTriple (Triple voteSubj PRdfType (OIri (vocabCurie TermVote)))
    tellTriple
        ( Triple
            voteSubj
            (PIri (vocabCurie TermHasVoter))
            (OBnode (idVoterBnode k))
        )
    tellTriple
        ( Triple
            voteSubj
            (PIri (vocabCurie TermHasVotingAction))
            (OStringLit (formatGovActionId actionId))
        )
    tellTriple
        ( Triple
            voteSubj
            (PIri (vocabCurie TermHasVerdict))
            (OStringLit (verdictText vote))
        )
    case mAnchor of
        SNothing -> pure ()
        SJust anchor -> emitVoteAnchor k voteSubj anchor
    emitVoterBlock k voterSubj voter

-- | The verdict text literal: @"Yes"@, @"No"@, or @"Abstain"@.
verdictText :: Vote -> Text
verdictText = \case
    VoteYes -> "Yes"
    VoteNo -> "No"
    Abstain -> "Abstain"

-- | Render a 'GovActionId' as @"\<txid_hex\>#\<index\>"@.
formatGovActionId :: GovActionId -> Text
formatGovActionId (GovActionId (TxId safeHash) (GovActionIx ix)) =
    hexText (hashToBytes (extractHash safeHash))
        <> "#"
        <> Text.pack (show ix)

{- | Emit the @_:voterK a cardano:VoterX ; cardano:hasIdentifier
"\<hex\>"@ sub-block. The discriminating class
('VoterDRep' / 'VoterStakePool' / 'VoterCommitteeCold') is
keyed by the 'Voter' constructor; the identifier is the
28-byte key-hash (or script-hash) the voter is bound to.
-}
emitVoterBlock :: Int -> Subject -> Voter -> Emit ()
emitVoterBlock _ voterSubj voter = do
    let (classTerm, idBytes) = voterDiscrimination voter
    tellTriple (Triple voterSubj PRdfType (OIri (vocabCurie classTerm)))
    tellTriple
        ( Triple
            voterSubj
            (PIri (vocabCurie TermHasIdentifier))
            (OStringLit (hexText idBytes))
        )

{- | Classify a 'Voter' into its discriminating class term and
identifier bytes. @CommitteeVoter@ wraps a hot-committee
credential (key or script hash); @DRepVoter@ wraps a DRep
credential (key or script hash); @StakePoolVoter@ wraps a pool
key-hash directly.
-}
voterDiscrimination :: Voter -> (VocabTerm, ByteString)
voterDiscrimination = \case
    CommitteeVoter (KeyHashObj (KeyHash h)) ->
        (TermVoterCommitteeCold, hashToBytes h)
    CommitteeVoter (ScriptHashObj (ScriptHash h)) ->
        (TermVoterCommitteeCold, hashToBytes h)
    DRepVoter (KeyHashObj (KeyHash h)) ->
        (TermVoterDRep, hashToBytes h)
    DRepVoter (ScriptHashObj (ScriptHash h)) ->
        (TermVoterDRep, hashToBytes h)
    StakePoolVoter (KeyHash h) ->
        (TermVoterStakePool, hashToBytes h)

{- | Emit the @cardano:hasAnchor _:voteAnchorK@ edge + sub-block
on a vote subject at position @k@. The sub-block carries
@cardano:anchorUrl "url"@ + @cardano:anchorHash "hex"@.
-}
emitVoteAnchor :: Int -> Subject -> Anchor -> Emit ()
emitVoteAnchor k voteSubj (Anchor url dataHash) = do
    let anchorSubj = SBnode (idVoteAnchorBnode k)
    tellTriple
        ( Triple
            voteSubj
            (PIri (vocabCurie TermHasAnchor))
            (OBnode (idVoteAnchorBnode k))
        )
    tellTriple
        ( Triple
            anchorSubj
            (PIri (vocabCurie TermAnchorUrl))
            (OStringLit (urlToText url))
        )
    tellTriple
        ( Triple
            anchorSubj
            (PIri (vocabCurie TermAnchorHash))
            (OStringLit (hexText (hashToBytes (extractHash dataHash))))
        )

----------------------------------------------------------------------
-- Bech32 encoding for the cardano:bech32 literal
----------------------------------------------------------------------

{- | Encode a Conway 'Addr' to its bech32 string. Uses the
network-discriminated HRP (@addr@ for mainnet, @addr_test@ for
testnet); the data part is the raw ledger serialization bytes
('serialiseAddr').
-}
encodeBech32 :: Network -> Addr -> Text
encodeBech32 network addr =
    case Bech32.humanReadablePartFromText hrp of
        Right h ->
            Bech32.encodeLenient
                h
                (Bech32.dataPartFromBytes (serialiseAddr addr))
        Left _ ->
            error
                ( "Cardano.Tx.Graph.Emit.Project: invalid bech32 HRP "
                    <> Text.unpack hrp
                )
  where
    hrp = case network of
        Mainnet -> "addr"
        Testnet -> "addr_test"

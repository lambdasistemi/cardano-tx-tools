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
import Cardano.Ledger.Api.Scripts.Data (
    Datum (Datum, DatumHash, NoDatum),
    hashBinaryData,
 )
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    outputsTxBodyL,
    proposalProceduresTxBodyL,
    referenceInputsTxBodyL,
    reqSignerHashesTxBodyL,
    totalCollateralTxBodyL,
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
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Governance (
    GovAction (TreasuryWithdrawals),
    ProposalProcedure (..),
 )
import Cardano.Ledger.Core (Script, TxCert, hashScript)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefBase, StakeRefNull, StakeRefPtr),
 )
import Cardano.Ledger.DRep (
    DRep (DRepAlwaysAbstain, DRepAlwaysNoConfidence, DRepKeyHash, DRepScriptHash),
 )
import Cardano.Ledger.Hashes (
    KeyHash (..),
    ScriptHash (..),
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
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.Foldable (toList)

import Cardano.Tx.Graph.Emit.Lookup (
    BnodeName (..),
    LookupTable,
    resolveCredential,
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
    -- Probe leaves not covered by any projection case for
    -- emptiness; any non-empty unhandled leaf is a structural
    -- mismatch the slice does not cover.
    assertEmptyLeavesForT008 tx
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
    -- Build per-input data + per-output data + per-collateral
    -- data with a single deduped address bnode registry.
    let (inputData, addrRegistry1) =
            buildInputs entities lookupTbl utxo inputs
        (outputData, addrRegistry2) =
            buildOutputs entities lookupTbl outputs addrRegistry1
        (collateralData, addrRegistry3) =
            buildCollaterals entities lookupTbl utxo collateralIns addrRegistry2
        refInputData = buildReferenceInputs refInputs
        addrEntries = addrRegistryEntries addrRegistry3
    -- Per-cert clusters (T008 — fixtures 06, 07).
    certClusters <-
        traverse (uncurry (buildCertCluster lookupTbl)) (zip [1 ..] certs)
    -- Per-proposal clusters (T010 — fixture 10).
    proposalBlocks <-
        traverse
            (uncurry (buildProposalCluster lookupTbl))
            (zip [1 ..] proposals)
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
        proposalSections =
            [ BodySection
                { sectionHeader = "Proposal " <> Text.pack (show k)
                , sectionBlocks = [block]
                }
            | (k, block) <- zip [1 :: Int ..] proposalBlocks
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
                <> proposalSections
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
-- Empty-leaf probes (T007 detects non-T005/T007 coverage)
----------------------------------------------------------------------

{- | Probe the tx's leaves not yet covered by the projection
walker for emptiness. T005+T007+T008+T010+T103 cover @inputs@ +
@outputs@ + @fee@ + @mint@ + @withdrawals@ + @certs@ +
@collateralInputs@ + @proposalProcedures@ + @referenceInputs@.
Anything else (required signers, total collateral) must be
empty: a non-empty unhandled leaf surfaces as
'PUnsupportedLeafType' so future slices extend coverage without
silent drops (T008 D3 — fail loudly).

T103 / S2 relaxes the @referenceInputs@ probe: reference inputs
now decode and emit as @cardano:Input@ subject blocks bound to
@_:tx@ via @cardano:hasReferenceInput@. Required-signers and
total-collateral remain fail-loudly until a later slice covers
them.
-}
assertEmptyLeavesForT008 :: ConwayTx -> Either ProjectError ()
assertEmptyLeavesForT008 tx = do
    let body = tx ^. bodyTxL
    chk "ConwayRequiredSignersValue" (length (body ^. reqSignerHashesTxBodyL))
    case body ^. totalCollateralTxBodyL of
        SNothing -> pure ()
        SJust _ -> Left (PUnsupportedLeafType "ConwayTotalCollateralValue")
  where
    chk leaf n
        | n == 0 = Right ()
        | otherwise = Left (PUnsupportedLeafType leaf)

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
        assetIdBnode =
            resolveCredential lookupTbl AssetClass assetBytes
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
(see the module-header note); the @hasFee@ predicate always
sits at the end so the byte layout matches the artisan
@expected.ttl@ shape.
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
    feeLovelace = do
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
a reference script. The sub-block carries @cardano:hasHash@ +
@cardano:hasRawBytes@; the script bnode is untyped (the
canonical @cardano:Script@ class is declared in the kmaps pin
but is not applied here — see the navigator brief literal
shape). Outputs with no reference script emit nothing.
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
    tellTriple
        ( Triple
            outSubj
            (PIri (vocabCurie TermHasReferenceScript))
            (OBnode scriptBnode)
        )
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
        let payIdBnode =
                resolveCredential
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
                let stakeIdBnode =
                        resolveCredential
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
        assetIdBnode = resolveCredential lookupTbl AssetClass assetBytes
        mintSubj = SBnode (idMintBnode k)
        assetSubj = SBnode (idAssetBnode k)
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
        credIdBnode = resolveCredential lookupTbl leafTy credBytes
        wSubj = SBnode (idWithdrawalBnode k)
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
    Either ProjectError [SubjectBlock]
buildCertCluster lookupTbl k = \case
    DelegTxCert cred (DelegStake (KeyHash poolHash)) ->
        Right
            ( clusterBlocks
                (emitStakeDelegation lookupTbl k cred (hashToBytes poolHash))
            )
    DelegTxCert cred (DelegVote (DRepKeyHash (KeyHash drepHash))) ->
        Right
            ( clusterBlocks
                ( emitVoteDelegation
                    lookupTbl
                    k
                    cred
                    DRepKey
                    (hashToBytes drepHash)
                )
            )
    DelegTxCert cred (DelegVote (DRepScriptHash (ScriptHash drepHash))) ->
        Right
            ( clusterBlocks
                ( emitVoteDelegation
                    lookupTbl
                    k
                    cred
                    DRepScript
                    (hashToBytes drepHash)
                )
            )
    DelegTxCert _ (DelegVote DRepAlwaysAbstain) ->
        Left (PUnsupportedLeafType "ConwayCertValue DelegVote DRepAlwaysAbstain")
    DelegTxCert _ (DelegVote DRepAlwaysNoConfidence) ->
        Left
            ( PUnsupportedLeafType
                "ConwayCertValue DelegVote DRepAlwaysNoConfidence"
            )
    DelegTxCert _ DelegStakeVote{} ->
        Left (PUnsupportedLeafType "ConwayCertValue DelegStakeVote")
    _ -> Left (PUnsupportedLeafType "ConwayCertValue (non-delegation)")

emitStakeDelegation ::
    LookupTable ->
    Int ->
    Credential Staking ->
    ByteString ->
    Emit ()
emitStakeDelegation lookupTbl k stakeCred poolBytes = do
    let (stakeLT, stakeBytes) = stakeCredLeaf stakeCred
        stakeIdBnode = resolveCredential lookupTbl stakeLT stakeBytes
        poolIdBnode = resolveCredential lookupTbl PoolId poolBytes
        certSubj = SBnode (idCertBnode k)
        poolSubj = SBnode (idPoolBnode k)
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
        stakeIdBnode = resolveCredential lookupTbl stakeLT stakeBytes
        drepIdBnode = resolveCredential lookupTbl drepLT drepBytes
        certSubj = SBnode (idCertBnode k)
        drepSubj = SBnode (idDRepBnode k)
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

{- | Build the subject block for one proposal at position @k@.

T010 ships the @TreasuryWithdrawals@ variety only, which is the
sole proposal the post-#45 harness exercises (S10 via
@stubTreasuryWithdrawalProposal@). The cluster pins the proposal
under @cardano:Datum@ (a deliberate reuse of the datum vocab,
matching the artisan layout from #45 — Phase A declares
@cardano:hasProposal@ as the body binding but does not (yet)
declare a @ProposalProcedure@ class or per-variety subclasses)
plus @cardano:decodedAs "TreasuryWithdrawals"@ to label the
variant. The proposer's @returnAddr@ stake credential surfaces
as a @cardano:hasIdentifier@ link, followed by one
@cardano:hasIdentifier@ per @TreasuryWithdrawals@ target
reward-account (in 'Map' ascending order — the same order the
ledger enforces on the wire).

== Policy: fail-loudly on unsupported proposal varieties (T008 D3)

Conway @GovAction@ constructors other than @TreasuryWithdrawals@
(@ParameterChange@, @HardForkInitiation@, @NoConfidence@,
@UpdateCommittee@, @NewConstitution@, @InfoAction@) raise
'PUnsupportedLeafType' rather than silently emitting partial
triples. Future slices that need a variant extend this function
explicitly.
-}
buildProposalCluster ::
    LookupTable ->
    Int ->
    ProposalProcedure ConwayEra ->
    Either ProjectError SubjectBlock
buildProposalCluster lookupTbl k (ProposalProcedure _ returnAddr action _) =
    case action of
        TreasuryWithdrawals targets _ ->
            let blocks =
                    clusterBlocks
                        (emitProposalTreasuryWithdrawals lookupTbl k returnAddr targets)
             in case blocks of
                    [b] -> Right b
                    _ ->
                        -- T102 invariant: emitProposalTreasuryWithdrawals
                        -- emits triples for a single subject, so
                        -- groupBySubject must return exactly one block.
                        -- This arm is unreachable; the explicit
                        -- pattern guards against silent regression
                        -- if a future slice adds extra subjects.
                        Left
                            ( PUnsupportedLeafType
                                "ConwayProposalValue TreasuryWithdrawals (unexpected multi-subject)"
                            )
        _ ->
            Left
                ( PUnsupportedLeafType
                    "ConwayProposalValue (non-TreasuryWithdrawals)"
                )

emitProposalTreasuryWithdrawals ::
    LookupTable ->
    Int ->
    AccountAddress ->
    Map AccountAddress Coin ->
    Emit ()
emitProposalTreasuryWithdrawals lookupTbl k returnAddr targets = do
    let (returnLT, returnBytes) = accountStakeLeaf returnAddr
        returnIdBnode =
            resolveCredential lookupTbl returnLT returnBytes
        targetIdBnodes =
            [ resolveCredential lookupTbl lt bytes
            | acct <- Map.keys targets
            , let (lt, bytes) = accountStakeLeaf acct
            ]
        propSubj = SBnode (idProposalBnode k)
    -- T105 / S4 drops the @_:proposalN a cardano:Datum@ type
    -- triple — the @cardano:Datum@ class declaration in the
    -- canonical pin is retained, but the proposal subject is
    -- left typeless here until T108 / S7 retypes it under the
    -- D-006 fallback shape.
    tellTriple
        ( Triple
            propSubj
            (PIri (vocabCurie TermDecodedAs))
            (OStringLit "TreasuryWithdrawals")
        )
    tellTriple
        ( Triple
            propSubj
            (PIri (vocabCurie TermHasIdentifier))
            (OBnode returnIdBnode)
        )
    mapM_
        ( tellTriple
            . Triple propSubj (PIri (vocabCurie TermHasIdentifier))
            . OBnode
        )
        targetIdBnodes

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

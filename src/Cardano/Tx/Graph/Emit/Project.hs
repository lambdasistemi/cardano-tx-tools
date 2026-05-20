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

== Tx-block predicate order (T010 / A-001)

The transaction subject block lists its @has*@ predicates in this
fixed order:

@hasInput, hasOutput, hasMint, hasWithdrawal, hasCertificate,
hasCollateralInput, hasProposal, hasFee@

The order follows the artisan @expected.ttl@ layout shipped by #45
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
import Data.Maybe (maybeToList)
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
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    StrictMaybe (SJust, SNothing),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Governance (
    GovAction (TreasuryWithdrawals),
    ProposalProcedure (..),
 )
import Cardano.Ledger.Core (TxCert)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefBase, StakeRefNull, StakeRefPtr),
 )
import Cardano.Ledger.DRep (
    DRep (DRepAlwaysAbstain, DRepAlwaysNoConfidence, DRepKeyHash, DRepScriptHash),
 )
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..))
import Cardano.Ledger.Keys (KeyRole (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxIn)
import Data.Foldable (toList)

import Cardano.Tx.Graph.Emit.Lookup (
    BnodeName (..),
    LookupTable,
    resolveCredential,
 )
import Cardano.Tx.Graph.Emit.Triple (
    BodySection (..),
    Object (..),
    Predicate (..),
    Subject (..),
    SubjectBlock (..),
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
        addrEntries = addrRegistryEntries addrRegistry3
    -- Per-cert clusters (T008 — fixtures 06, 07).
    certClusters <-
        traverse (uncurry (buildCertCluster lookupTbl)) (zip [1 ..] certs)
    -- Per-proposal clusters (T010 — fixture 10).
    proposalBlocks <-
        traverse
            (uncurry (buildProposalCluster lookupTbl))
            (zip [1 ..] proposals)
    -- Assemble the tx subject block.
    let txBlock =
            SubjectBlock
                (SBnode (BnodeName "tx"))
                ( (PRdfType, OIri (vocabCurie TermTransaction))
                    : [ (PIri (vocabCurie TermHasInput), OBnode (idInputBnode k))
                      | k <- [1 .. length inputData]
                      ]
                        <> [ (PIri (vocabCurie TermHasOutput), OBnode (idOutputBnode k))
                           | k <- [1 .. length outputData]
                           ]
                        <> [ (PIri (vocabCurie TermHasMint), OBnode (idMintBnode k))
                           | k <- [1 .. length mintPairs]
                           ]
                        <> [ (PIri (vocabCurie TermHasWithdrawal), OBnode (idWithdrawalBnode k))
                           | k <- [1 .. length withdrawalPairs]
                           ]
                        <> [ (PIri (vocabCurie TermHasCertificate), OBnode (idCertBnode k))
                           | k <- [1 .. length certs]
                           ]
                        <> [ ( PIri (vocabCurie TermHasCollateralInput)
                             , OBnode (idCollateralBnode k)
                             )
                           | k <- [1 .. length collateralData]
                           ]
                        <> [ (PIri (vocabCurie TermHasProposal), OBnode (idProposalBnode k))
                           | k <- [1 .. length proposals]
                           ]
                        <> [(PIri (vocabCurie TermHasFee), OIntLit (fromIntegral feeLovelace))]
                )
        txSection =
            BodySection
                { sectionHeader = "Transaction body."
                , sectionBlocks = [txBlock]
                }
        inputSections =
            [ BodySection
                { sectionHeader = "Input " <> Text.pack (show k)
                , sectionBlocks = blocks
                }
            | (k, blocks) <- zip [1 :: Int ..] inputData
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
                , sectionBlocks = buildMintCluster lookupTbl k policyId assetName
                }
            | (k, (policyId, assetName, _quantity)) <-
                zip [1 :: Int ..] mintPairs
            ]
        withdrawalSections =
            [ BodySection
                { sectionHeader = "Withdrawal " <> Text.pack (show k)
                , sectionBlocks =
                    [buildWithdrawalCluster lookupTbl k account coin]
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
                        concatMap (addrEntryBlocks lookupTbl) addrEntries
                    }
                ]
    pure
        ( txSection
            : inputSections
                <> outputSections
                <> mintSections
                <> withdrawalSections
                <> certSections
                <> collateralSections
                <> proposalSections
                <> addrSection
        )

----------------------------------------------------------------------
-- Empty-leaf probes (T007 detects non-T005/T007 coverage)
----------------------------------------------------------------------

{- | Probe the tx's leaves not yet covered by the projection
walker for emptiness. T005+T007+T008+T010 cover @inputs@ +
@outputs@ + @fee@ + @mint@ + @withdrawals@ + @certs@ +
@collateralInputs@ + @proposalProcedures@. Anything else
(reference inputs, required signers, total collateral) must be
empty: a non-empty unhandled leaf surfaces as
'PUnsupportedLeafType' so future slices extend coverage without
silent drops (T008 D3 — fail loudly).
-}
assertEmptyLeavesForT008 :: ConwayTx -> Either ProjectError ()
assertEmptyLeavesForT008 tx = do
    let body = tx ^. bodyTxL
    chk "ConwayReferenceInputValue" (length (body ^. referenceInputsTxBodyL))
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

-- | Bnode name a resolved-input output at position @k@ gets.
idResolvedInputBnode :: Int -> BnodeName
idResolvedInputBnode k =
    BnodeName ("resolvedInput" <> Text.pack (show k))

-- | Bnode name a mint entry at position @k@ (1-based) gets.
idMintBnode :: Int -> BnodeName
idMintBnode k = BnodeName ("mint" <> Text.pack (show k))

-- | Bnode name a mint-entry policy at position @k@ gets.
idPolicyBnode :: Int -> BnodeName
idPolicyBnode k = BnodeName ("policy" <> Text.pack (show k))

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

-- | Bnode name a resolved-collateral output at position @k@ gets.
idResolvedCollateralBnode :: Int -> BnodeName
idResolvedCollateralBnode k =
    BnodeName ("resolvedCollateral" <> Text.pack (show k))

-- | Bnode name a proposal entry at position @k@ (1-based) gets.
idProposalBnode :: Int -> BnodeName
idProposalBnode k =
    BnodeName ("proposal" <> Text.pack (show k))

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
                let block =
                        SubjectBlock
                            (SBnode (idInputBnode k))
                            [(PRdfType, OIri (vocabCurie TermInput))]
                 in go ([block] : acc) reg rest
            Just resolved ->
                let (entry, reg') =
                        insertAddr
                            entities
                            lookupTbl
                            (resolved ^. addrTxOutL)
                            reg
                    inputBlock =
                        SubjectBlock
                            (SBnode (idInputBnode k))
                            [ (PRdfType, OIri (vocabCurie TermInput))
                            ,
                                ( PIri (vocabCurie TermResolvedTo)
                                , OBnode (idResolvedInputBnode k)
                                )
                            ]
                    resolvedBlock =
                        SubjectBlock
                            (SBnode (idResolvedInputBnode k))
                            [ (PRdfType, OIri (vocabCurie TermOutput))
                            ,
                                ( PIri (vocabCurie TermAtAddress)
                                , OBnode (BnodeName (aeBnodeBase entry <> "Addr"))
                                )
                            ]
                 in go ([inputBlock, resolvedBlock] : acc) reg' rest

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
            block =
                SubjectBlock
                    (SBnode (idOutputBnode k))
                    [ (PRdfType, OIri (vocabCurie TermOutput))
                    ,
                        ( PIri (vocabCurie TermAtAddress)
                        , OBnode (BnodeName (aeBnodeBase entry <> "Addr"))
                        )
                    ]
         in go ([block] : acc) reg' rest

----------------------------------------------------------------------
-- Address decomposition blocks
----------------------------------------------------------------------

{- | Render an 'AddrEntry' as the @[address-block, payment-cred-block,
stake-cred-block]@ trio (stake-cred-block omitted when the
address has no stake credential).
-}
addrEntryBlocks :: LookupTable -> AddrEntry -> [SubjectBlock]
addrEntryBlocks lookupTbl AddrEntry{aeBnodeBase, aePaymentCred, aeStakeCred, aeBech32} =
    let addrBnode = BnodeName (aeBnodeBase <> "Addr")
        payCredBnode = BnodeName (aeBnodeBase <> "CredPayment")
        stakeCredBnode = BnodeName (aeBnodeBase <> "CredStake")
        addrBlock =
            SubjectBlock
                (SBnode addrBnode)
                ( [ (PRdfType, OIri (vocabCurie TermAddress))
                  , (PIri (vocabCurie TermBech32), OStringLit aeBech32)
                  ,
                      ( PIri (vocabCurie TermHasPaymentCredential)
                      , OBnode payCredBnode
                      )
                  ]
                    <> [ ( PIri (vocabCurie TermHasStakeCredential)
                         , OBnode stakeCredBnode
                         )
                       | _ <- maybeToList aeStakeCred
                       ]
                )
        payIdBnode =
            resolveCredential
                lookupTbl
                (plLeafType aePaymentCred)
                (plBytes aePaymentCred)
        payCredBlock =
            SubjectBlock
                (SBnode payCredBnode)
                [ (PRdfType, OIri (vocabCurie TermPaymentCredential))
                ,
                    ( PIri (vocabCurie TermHasIdentifier)
                    , OBnode payIdBnode
                    )
                ]
        stakeCredBlocks =
            case aeStakeCred of
                Nothing -> []
                Just sl ->
                    let stakeIdBnode =
                            resolveCredential
                                lookupTbl
                                (slLeafType sl)
                                (slBytes sl)
                     in [ SubjectBlock
                            (SBnode stakeCredBnode)
                            [ (PRdfType, OIri (vocabCurie TermStakeCredential))
                            ,
                                ( PIri (vocabCurie TermHasIdentifier)
                                , OBnode stakeIdBnode
                                )
                            ]
                        ]
     in addrBlock : payCredBlock : stakeCredBlocks

----------------------------------------------------------------------
-- Mint cluster (T007 — fixture 04)
----------------------------------------------------------------------

{- | Build the three subject blocks for one mint entry at
position @k@: the @cardano:Mint@ cluster header, a
@cardano:Policy@ block for the policy identifier, and a
@cardano:Asset@ block for the @policy ++ asset-name@ identifier.

Per research R2, the @AssetClass@ identifier's @bytesHex@ is the
concatenation of the 28-byte policy hash and the raw bytes of the
asset name; the lookup table follows the same convention.
-}
buildMintCluster ::
    LookupTable -> Int -> PolicyID -> AssetName -> [SubjectBlock]
buildMintCluster lookupTbl k policyId assetName =
    [mintBlock, policyBlock, assetBlock]
  where
    policyBytes = policyIdBytes policyId
    assetBytes = policyBytes <> assetClassNameBytes assetName
    policyIdBnode = resolveCredential lookupTbl Policy policyBytes
    assetIdBnode = resolveCredential lookupTbl AssetClass assetBytes
    mintBlock =
        SubjectBlock
            (SBnode (idMintBnode k))
            [ (PRdfType, OIri (vocabCurie TermMint))
            , (PIri (vocabCurie TermHasPolicy), OBnode (idPolicyBnode k))
            , (PIri (vocabCurie TermHasAsset), OBnode (idAssetBnode k))
            ]
    policyBlock =
        SubjectBlock
            (SBnode (idPolicyBnode k))
            [ (PRdfType, OIri (vocabCurie TermPolicy))
            , (PIri (vocabCurie TermHasIdentifier), OBnode policyIdBnode)
            ]
    assetBlock =
        SubjectBlock
            (SBnode (idAssetBnode k))
            [ (PRdfType, OIri (vocabCurie TermAsset))
            , (PIri (vocabCurie TermHasIdentifier), OBnode assetIdBnode)
            ]

policyIdBytes :: PolicyID -> ByteString
policyIdBytes (PolicyID (ScriptHash h)) = hashToBytes h

assetClassNameBytes :: AssetName -> ByteString
assetClassNameBytes (AssetName sbs) = SBS.fromShort sbs

----------------------------------------------------------------------
-- Withdrawal cluster (T007 — fixture 05)
----------------------------------------------------------------------

{- | Build the @cardano:Withdrawal@ subject block for one
withdrawal at position @k@. The cluster carries
@cardano:onCredential@ — pointing at the reward-account stake
credential's identifier bnode (entity-named when an entity
covers it, raw-bytes-named otherwise) — and
@cardano:withAmount@ — the lovelace quantity as an integer
literal.

R2 wires withdrawal stake credentials as @StakeKey@ (key-hash
credential) or @StakeScript@ (script-hash credential). T007's
harness fixture 05 exercises the key-hash case; T010 may
encounter the script-hash case in fixture 11.
-}
buildWithdrawalCluster ::
    LookupTable -> Int -> AccountAddress -> Coin -> SubjectBlock
buildWithdrawalCluster lookupTbl k account (Coin lovelace) =
    SubjectBlock
        (SBnode (idWithdrawalBnode k))
        [ (PRdfType, OIri (vocabCurie TermWithdrawal))
        , (PIri (vocabCurie TermOnCredential), OBnode credIdBnode)
        , (PIri (vocabCurie TermWithAmount), OIntLit (fromIntegral lovelace))
        ]
  where
    (leafTy, credBytes) = accountStakeLeaf account
    credIdBnode = resolveCredential lookupTbl leafTy credBytes

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
        Right (stakeDelegationBlocks lookupTbl k cred (hashToBytes poolHash))
    DelegTxCert cred (DelegVote (DRepKeyHash (KeyHash drepHash))) ->
        Right
            ( voteDelegationBlocks
                lookupTbl
                k
                cred
                DRepKey
                (hashToBytes drepHash)
            )
    DelegTxCert cred (DelegVote (DRepScriptHash (ScriptHash drepHash))) ->
        Right
            ( voteDelegationBlocks
                lookupTbl
                k
                cred
                DRepScript
                (hashToBytes drepHash)
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

stakeDelegationBlocks ::
    LookupTable ->
    Int ->
    Credential Staking ->
    ByteString ->
    [SubjectBlock]
stakeDelegationBlocks lookupTbl k stakeCred poolBytes =
    [certBlock, poolBlock]
  where
    (stakeLT, stakeBytes) = stakeCredLeaf stakeCred
    stakeIdBnode = resolveCredential lookupTbl stakeLT stakeBytes
    poolIdBnode = resolveCredential lookupTbl PoolId poolBytes
    certBlock =
        SubjectBlock
            (SBnode (idCertBnode k))
            [ (PRdfType, OIri (vocabCurie TermStakeDelegation))
            , (PIri (vocabCurie TermOnCredential), OBnode stakeIdBnode)
            , (PIri (vocabCurie TermToPool), OBnode (idPoolBnode k))
            ]
    poolBlock =
        SubjectBlock
            (SBnode (idPoolBnode k))
            [ (PRdfType, OIri (vocabCurie TermPool))
            , (PIri (vocabCurie TermHasIdentifier), OBnode poolIdBnode)
            ]

voteDelegationBlocks ::
    LookupTable ->
    Int ->
    Credential Staking ->
    LeafType ->
    ByteString ->
    [SubjectBlock]
voteDelegationBlocks lookupTbl k stakeCred drepLT drepBytes =
    [certBlock, drepBlock]
  where
    (stakeLT, stakeBytes) = stakeCredLeaf stakeCred
    stakeIdBnode = resolveCredential lookupTbl stakeLT stakeBytes
    drepIdBnode = resolveCredential lookupTbl drepLT drepBytes
    certBlock =
        SubjectBlock
            (SBnode (idCertBnode k))
            [ (PRdfType, OIri (vocabCurie TermVoteDelegation))
            , (PIri (vocabCurie TermOnCredential), OBnode stakeIdBnode)
            , (PIri (vocabCurie TermToDRep), OBnode (idDRepBnode k))
            ]
    drepBlock =
        SubjectBlock
            (SBnode (idDRepBnode k))
            [ (PRdfType, OIri (vocabCurie TermDRep))
            , (PIri (vocabCurie TermHasIdentifier), OBnode drepIdBnode)
            ]

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
                let block =
                        SubjectBlock
                            (SBnode (idCollateralBnode k))
                            [(PRdfType, OIri (vocabCurie TermInput))]
                 in go ([block] : acc) reg rest
            Just resolved ->
                let (entry, reg') =
                        insertAddr
                            entities
                            lookupTbl
                            (resolved ^. addrTxOutL)
                            reg
                    collBlock =
                        SubjectBlock
                            (SBnode (idCollateralBnode k))
                            [ (PRdfType, OIri (vocabCurie TermInput))
                            ,
                                ( PIri (vocabCurie TermResolvedTo)
                                , OBnode (idResolvedCollateralBnode k)
                                )
                            ]
                    resolvedBlock =
                        SubjectBlock
                            (SBnode (idResolvedCollateralBnode k))
                            [ (PRdfType, OIri (vocabCurie TermOutput))
                            ,
                                ( PIri (vocabCurie TermAtAddress)
                                , OBnode (BnodeName (aeBnodeBase entry <> "Addr"))
                                )
                            ]
                 in go ([collBlock, resolvedBlock] : acc) reg' rest

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
            let (returnLT, returnBytes) = accountStakeLeaf returnAddr
                returnIdBnode =
                    resolveCredential lookupTbl returnLT returnBytes
                targetIdBnodes =
                    [ resolveCredential lookupTbl lt bytes
                    | acct <- Map.keys targets
                    , let (lt, bytes) = accountStakeLeaf acct
                    ]
             in Right $
                    SubjectBlock
                        (SBnode (idProposalBnode k))
                        ( [ (PRdfType, OIri (vocabCurie TermDatum))
                          ,
                              ( PIri (vocabCurie TermDecodedAs)
                              , OStringLit "TreasuryWithdrawals"
                              )
                          ,
                              ( PIri (vocabCurie TermHasIdentifier)
                              , OBnode returnIdBnode
                              )
                          ]
                            <> [ ( PIri (vocabCurie TermHasIdentifier)
                                 , OBnode bn
                                 )
                               | bn <- targetIdBnodes
                               ]
                        )
        _ ->
            Left
                ( PUnsupportedLeafType
                    "ConwayProposalValue (non-TreasuryWithdrawals)"
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

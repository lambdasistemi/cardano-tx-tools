{- |
Module      : Cardano.Tx.Graph.Emit.Witness
Description : Witness-set walker for the joint Turtle emitter (private).
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. Walks the
@tx ^. witsTxL@ component of a Conway transaction and emits one
'BodySection' grouping the typed RDF blocks for redeemers, key
witnesses, datum witnesses, script witnesses, and bootstrap
witnesses (T128b / S31).

The five witness collections in 'Cardano.Ledger.Alonzo.TxWits' are:

* @addrTxWitsL@ — @Set (WitVKey 'Witness)@
* @bootAddrTxWitsL@ — @Set BootstrapWitness@
* @scriptTxWitsL@ — @Map ScriptHash (Script era)@
* @datsTxWitsL@ — @TxDats era@ (@Map DataHash (Data era)@)
* @rdmrsTxWitsL@ — @Redeemers era@
  (@Map (PlutusPurpose AsIx era) (Data era, ExUnits)@)

Each non-empty collection contributes a typed cluster of sub-blocks
to the single \"Witness set.\" 'BodySection'. The cluster for an
empty witness set is the empty list; the emitter contributes ZERO
'BodySection' entries when every witness collection is empty, so
body-only fixtures stay byte-stable.

== Bnode sharing

Key witnesses bind 'cardano:hasVerificationKey' to the same
@_:cred_paymentkey_\<bytes16\>@ identifier bnode the body
walker's 'cardano:hasRequiredSigner' targets, via the shared
'Cardano.Tx.Graph.Emit.Project.resolveCredentialAndIntroduceIdent'
helper (T128b shared-identity invariant). Datum-witness and
script-witness hash references go through the same helper so they
join on bnode equality with any output-side inline datum / inline
reference-script reference to the same hash.

== Opaque CBOR

PlutusData typed decoding is deferred to #50; redeemer @data@ and
datum-witness bodies render as
@cardano:hasRawBytes "\<cbor-hex\>"@ inside their
@cardano:Datum@-typed sub-blocks. Bootstrap witnesses are similarly
opaque (Byron-era plumbing).
-}
module Cardano.Tx.Graph.Emit.Witness (
    -- * Entry point
    projectWitness,

    -- * Counts (consumed by 'Cardano.Tx.Graph.Emit.Project.emitTxBlock')
    witnessCounts,
    WitnessCounts (..),
) where

import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text

import Lens.Micro ((^.))

import Cardano.Crypto.DSIGN (SignedDSIGN (..))
import Cardano.Crypto.DSIGN.Class (rawSerialiseSigDSIGN)
import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.Scripts (
    AsIx (..),
    plutusScriptLanguage,
    toPlutusScript,
 )
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..), TxDats (..))
import Cardano.Ledger.Api.Era (eraProtVerLow)
import Cardano.Ledger.Api.Scripts.Data (
    Data,
    Datum (DatumHash),
    hashData,
 )
import Cardano.Ledger.Api.Tx (
    addrTxWitsL,
    bodyTxL,
    bootAddrTxWitsL,
    witsTxL,
 )
import Cardano.Ledger.Api.Tx.Body (
    inputsTxBodyL,
    mintTxBodyL,
    outputsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, datumTxOutL)
import Cardano.Ledger.Api.Tx.Wits (
    datsTxWitsL,
    rdmrsTxWitsL,
    scriptTxWitsL,
    witVKeyHash,
 )
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (Script, hashScript)
import Cardano.Ledger.Credential (Credential (ScriptHashObj))
import Cardano.Ledger.Hashes (
    DataHash,
    KeyHash (..),
    ScriptHash (..),
    extractHash,
 )
import Cardano.Ledger.Keys (KeyRole (..), WitVKey (..))
import Cardano.Ledger.Keys.Bootstrap (BootstrapWitness)
import Cardano.Ledger.Mary.Value (MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (
    Language (PlutusV1, PlutusV2, PlutusV3, PlutusV4),
 )
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Tx.Blueprint (Blueprint)
import Cardano.Tx.Graph.Emit.Blueprint (
    BlueprintDecodeResult (..),
    RdmrPurpose (..),
    decodeDatumForOutput,
    decodeRedeemerForPurpose,
 )
import Cardano.Tx.Graph.Emit.Lookup (BnodeName (..), LookupTable)
import Cardano.Tx.Graph.Emit.Monad (Emit, tellTriple)
import Cardano.Tx.Graph.Emit.Project (
    clusterBlocks,
    datumValidatorPick,
    emitDecodedOrOpaque,
    hexText,
    idBootstrapWitnessBnode,
    idDatumWitnessBnode,
    idKeyWitnessBnode,
    idRedeemerBnode,
    idScriptWitnessBnode,
    redeemerValidatorPick,
    resolveCredentialAndIntroduceIdent,
 )
import Cardano.Tx.Graph.Emit.Triple (
    BodySection (..),
    Object (..),
    Predicate (..),
    Subject (..),
    Triple (..),
 )
import Cardano.Tx.Graph.Emit.Vocab (VocabTerm (..), vocabCurie)
import Cardano.Tx.Graph.Rules.Load (EntityDecl, LeafType (..))
import Cardano.Tx.Ledger (ConwayTx)

----------------------------------------------------------------------
-- Counts
----------------------------------------------------------------------

{- | The per-collection cardinalities the @_:tx@ block needs to
emit one @cardano:hasX _:xK@ edge per witness. Produced by
'witnessCounts'; consumed by
'Cardano.Tx.Graph.Emit.Project.emitTxBlock'.
-}
data WitnessCounts = WitnessCounts
    { wcRedeemers :: !Int
    , wcKeyWitnesses :: !Int
    , wcDatumWitnesses :: !Int
    , wcScriptWitnesses :: !Int
    , wcBootstrapWitnesses :: !Int
    }
    deriving stock (Eq, Show)

-- | Read the witness-set cardinalities off a 'ConwayTx'.
witnessCounts :: ConwayTx -> WitnessCounts
witnessCounts tx =
    let wits = tx ^. witsTxL
        Redeemers redeemers = wits ^. rdmrsTxWitsL
        TxDats datums = wits ^. datsTxWitsL
     in WitnessCounts
            { wcRedeemers = Map.size redeemers
            , wcKeyWitnesses = Set.size (wits ^. addrTxWitsL)
            , wcDatumWitnesses = Map.size datums
            , wcScriptWitnesses = Map.size (wits ^. scriptTxWitsL)
            , wcBootstrapWitnesses = Set.size (wits ^. bootAddrTxWitsL)
            }

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

{- | Walk the @tx ^. witsTxL@ component and emit one
\"Witness set.\" 'BodySection' grouping every non-empty
witness-type cluster. Returns @[]@ when every witness collection
is empty so body-only fixtures stay byte-stable.

T102 / S2 (#50): the @blueprints@ index is consulted on each
redeemer (via 'decodeRedeemerForPurpose' keyed by purpose-resolved
script hash) and on each datum witness (via
'decodeDatumForOutput' keyed by the referencing output's
payment-credential script hash — looked up by 'DataHash' against
the body's outputs). Empty index ⇒ every consultation returns
'NoBlueprintRegistered' ⇒ no behaviour change.
-}
projectWitness ::
    [EntityDecl] ->
    LookupTable ->
    [(ScriptHash, Blueprint, Text)] ->
    ConwayTx ->
    Map TxIn (TxOut ConwayEra) ->
    [BodySection]
projectWitness _entities lookupTbl blueprints tx utxo =
    let body = tx ^. bodyTxL
        wits = tx ^. witsTxL
        Redeemers redeemers = wits ^. rdmrsTxWitsL
        TxDats datums = wits ^. datsTxWitsL
        keyWits = wits ^. addrTxWitsL
        scripts = wits ^. scriptTxWitsL
        boots = wits ^. bootAddrTxWitsL
        bodyOutputs = foldr (:) [] (body ^. outputsTxBodyL)
        inputs = Set.toAscList (body ^. inputsTxBodyL)
        MultiAsset mintMap = body ^. mintTxBodyL
        mintPolicies = Map.keys mintMap
        action = do
            emitRedeemers
                lookupTbl
                blueprints
                utxo
                inputs
                mintPolicies
                redeemers
            emitKeyWitnesses lookupTbl keyWits
            emitDatumWitnesses lookupTbl blueprints bodyOutputs datums
            emitScriptWitnesses lookupTbl scripts
            emitBootstrapWitnesses boots
        anyNonEmpty =
            not (Map.null redeemers)
                || not (Set.null keyWits)
                || not (Map.null datums)
                || not (Map.null scripts)
                || not (Set.null boots)
     in [ BodySection
            { sectionHeader = "Witness set."
            , sectionBlocks = clusterBlocks action
            }
        | anyNonEmpty
        ]

----------------------------------------------------------------------
-- Redeemers
----------------------------------------------------------------------

-- | Bnode name for the @k@-th redeemer's data sub-block.
idRedeemerDataBnode :: Int -> BnodeName
idRedeemerDataBnode k = BnodeName ("redeemerData" <> Text.pack (show k))

-- | Bnode name for the @k@-th redeemer's ExUnits sub-block.
idExUnitsBnode :: Int -> BnodeName
idExUnitsBnode k = BnodeName ("exUnits" <> Text.pack (show k))

emitRedeemers ::
    LookupTable ->
    [(ScriptHash, Blueprint, Text)] ->
    Map TxIn (TxOut ConwayEra) ->
    [TxIn] ->
    [PolicyID] ->
    Map (ConwayPlutusPurpose AsIx ConwayEra) (Data ConwayEra, ExUnits) ->
    Emit ()
emitRedeemers lookupTbl blueprints utxo inputs mintPolicies rdmrs =
    mapM_
        ( uncurry
            ( emitRedeemerEntry
                lookupTbl
                blueprints
                utxo
                inputs
                mintPolicies
            )
        )
        (zip [1 ..] (Map.toAscList rdmrs))

emitRedeemerEntry ::
    LookupTable ->
    [(ScriptHash, Blueprint, Text)] ->
    Map TxIn (TxOut ConwayEra) ->
    [TxIn] ->
    [PolicyID] ->
    Int ->
    (ConwayPlutusPurpose AsIx ConwayEra, (Data ConwayEra, ExUnits)) ->
    Emit ()
emitRedeemerEntry
    lookupTbl
    blueprints
    utxo
    inputs
    mintPolicies
    k
    (purpose, (datum, exUnits)) = do
        let rdmrSubj = SBnode (idRedeemerBnode k)
            dataSubj = SBnode (idRedeemerDataBnode k)
            exUnitsSubj = SBnode (idExUnitsBnode k)
            (purposeTag, purposeIx) = purposeDiscrimination purpose
            ExUnits memUnits cpuUnits = exUnits
            dataHashBytes = hashToBytes (extractHash (hashData datum))
            dataBytes = serialize' (eraProtVerLow @ConwayEra) datum
            mResolved =
                resolveRedeemerPurposeHash
                    utxo
                    inputs
                    mintPolicies
                    purpose
            decodeResult =
                case mResolved of
                    Nothing -> NoBlueprintRegistered
                    Just (rdmrPurpose, sh) ->
                        decodeRedeemerForPurpose
                            blueprints
                            rdmrPurpose
                            sh
                            datum
            bnodeBase = "redeemerData" <> Text.pack (show k)
        tellTriple (Triple rdmrSubj PRdfType (OIri (vocabCurie TermRedeemer)))
        tellTriple
            ( Triple
                rdmrSubj
                (PIri (vocabCurie TermHasPurpose))
                (OStringLit purposeTag)
            )
        tellTriple
            ( Triple
                rdmrSubj
                (PIri (vocabCurie TermHasIndex))
                (OIntLit purposeIx)
            )
        tellTriple
            ( Triple
                rdmrSubj
                (PIri (vocabCurie TermHasData))
                (OBnode (idRedeemerDataBnode k))
            )
        tellTriple
            ( Triple
                rdmrSubj
                (PIri (vocabCurie TermHasExUnits))
                (OBnode (idExUnitsBnode k))
            )
        tellTriple (Triple dataSubj PRdfType (OIri (vocabCurie TermDatum)))
        hashBnode <-
            resolveCredentialAndIntroduceIdent
                lookupTbl
                LtDatumHash
                dataHashBytes
        tellTriple
            ( Triple
                dataSubj
                (PIri (vocabCurie TermHasHash))
                (OBnode hashBnode)
            )
        emitDecodedOrOpaque
            dataSubj
            bnodeBase
            redeemerValidatorPick
            decodeResult
            dataBytes
        tellTriple
            (Triple exUnitsSubj PRdfType (OIri (vocabCurie TermExUnits)))
        tellTriple
            ( Triple
                exUnitsSubj
                (PIri (vocabCurie TermMemoryUnits))
                (OIntLit (toInteger memUnits))
            )
        tellTriple
            ( Triple
                exUnitsSubj
                (PIri (vocabCurie TermCpuUnits))
                (OIntLit (toInteger cpuUnits))
            )

{- | Map a Conway 'ConwayPlutusPurpose' to its @hasPurpose@ enum
literal plus its 'AsIx' numeric component (cast to 'Integer' so
the literal renders as a typed xsd:integer).
-}
purposeDiscrimination ::
    ConwayPlutusPurpose AsIx ConwayEra -> (Text, Integer)
purposeDiscrimination = \case
    ConwaySpending (AsIx ix) -> ("Spend", toInteger ix)
    ConwayMinting (AsIx ix) -> ("Mint", toInteger ix)
    ConwayCertifying (AsIx ix) -> ("Cert", toInteger ix)
    ConwayRewarding (AsIx ix) -> ("Withdraw", toInteger ix)
    ConwayVoting (AsIx ix) -> ("Vote", toInteger ix)
    ConwayProposing (AsIx ix) -> ("Propose", toInteger ix)

{- | Resolve a Conway 'ConwayPlutusPurpose' to the script hash the
blueprint index keys on, paired with the 'RdmrPurpose' tag the
T101 decoder expects. Returns 'Nothing' when the resolution
cannot be carried out from local state alone (e.g. the spend
purpose's input is not in the resolved-UTxO map, or the
certificate's script credential is not extractable in T102's
minimal walker).

T102 minimum:

* 'Spend' — read the @AsIx@-th input (in the ledger's ascending
  input order), look it up in the resolved-UTxO map, and extract
  the payment-credential script hash. 'Nothing' when the input
  is not in the map or the address has a key-credential payment
  part.
* 'Mint' — read the @AsIx@-th policy id from the body's mint
  multi-asset map (already a 'ScriptHash').
* 'Cert' / 'Reward' / 'Propose' / 'Vote' — 'Nothing' for T102.
  T105+ wires these as the corresponding fixtures demand
  (operator-side script-credentialed certs / withdrawals / votes /
  proposals are rare and T103's happy-path fixture exercises
  'Spend' only).
-}
resolveRedeemerPurposeHash ::
    Map TxIn (TxOut ConwayEra) ->
    [TxIn] ->
    [PolicyID] ->
    ConwayPlutusPurpose AsIx ConwayEra ->
    Maybe (RdmrPurpose, ScriptHash)
resolveRedeemerPurposeHash utxo inputs mintPolicies = \case
    ConwaySpending (AsIx ix) -> do
        txIn <- safeIndex (fromIntegral ix) inputs
        txOut <- Map.lookup txIn utxo
        sh <- paymentScriptHash (txOut ^. addrTxOutL)
        pure (Spend, sh)
    ConwayMinting (AsIx ix) -> do
        PolicyID sh <- safeIndex (fromIntegral ix) mintPolicies
        pure (Mint, sh)
    -- T102 minimum: governance/cert/reward redeemer script-hash
    -- resolution deferred to a later slice (see Haddock above).
    ConwayCertifying _ -> Nothing
    ConwayRewarding _ -> Nothing
    ConwayVoting _ -> Nothing
    ConwayProposing _ -> Nothing
  where
    safeIndex :: Int -> [a] -> Maybe a
    safeIndex _ [] = Nothing
    safeIndex 0 (x : _) = Just x
    safeIndex n (_ : rest) = safeIndex (n - 1) rest
    paymentScriptHash :: Addr -> Maybe ScriptHash
    paymentScriptHash (Addr _network (ScriptHashObj sh) _stake) = Just sh
    paymentScriptHash _ = Nothing

----------------------------------------------------------------------
-- Key witnesses
----------------------------------------------------------------------

emitKeyWitnesses ::
    LookupTable -> Set (WitVKey Witness) -> Emit ()
emitKeyWitnesses lookupTbl wits =
    mapM_
        (uncurry (emitKeyWitnessEntry lookupTbl))
        (zip [1 ..] (Set.toAscList wits))

emitKeyWitnessEntry ::
    LookupTable -> Int -> WitVKey Witness -> Emit ()
emitKeyWitnessEntry lookupTbl k wit = do
    let kwSubj = SBnode (idKeyWitnessBnode k)
        WitVKey _ (SignedDSIGN sig) = wit
        KeyHash keyHashHash = witVKeyHash wit
        keyHashBytes = hashToBytes keyHashHash
    keyBnode <-
        resolveCredentialAndIntroduceIdent
            lookupTbl
            PaymentKey
            keyHashBytes
    tellTriple
        (Triple kwSubj PRdfType (OIri (vocabCurie TermKeyWitness)))
    tellTriple
        ( Triple
            kwSubj
            (PIri (vocabCurie TermHasSignature))
            (OStringLit (hexText (rawSerialiseSigDSIGN sig)))
        )
    tellTriple
        ( Triple
            kwSubj
            (PIri (vocabCurie TermHasVerificationKey))
            (OBnode keyBnode)
        )

----------------------------------------------------------------------
-- Datum witnesses
----------------------------------------------------------------------

emitDatumWitnesses ::
    LookupTable ->
    [(ScriptHash, Blueprint, Text)] ->
    [TxOut ConwayEra] ->
    Map DataHash (Data ConwayEra) ->
    Emit ()
emitDatumWitnesses lookupTbl blueprints outputs datums =
    mapM_
        (uncurry (emitDatumWitnessEntry lookupTbl blueprints outputs))
        (zip [1 ..] (Map.toAscList datums))

emitDatumWitnessEntry ::
    LookupTable ->
    [(ScriptHash, Blueprint, Text)] ->
    [TxOut ConwayEra] ->
    Int ->
    (DataHash, Data ConwayEra) ->
    Emit ()
emitDatumWitnessEntry lookupTbl blueprints outputs k (dHash, datum) = do
    let datumSubj = SBnode (idDatumWitnessBnode k)
        hashBytes = hashToBytes (extractHash dHash)
        rawBytes = serialize' (eraProtVerLow @ConwayEra) datum
        bnodeBase = "datumWitness" <> Text.pack (show k)
        decodeResult =
            case findOutputForDatumHash dHash outputs of
                Nothing -> NoBlueprintRegistered
                Just txOut -> decodeDatumForOutput blueprints txOut datum
    tellTriple (Triple datumSubj PRdfType (OIri (vocabCurie TermDatum)))
    hashBnode <-
        resolveCredentialAndIntroduceIdent
            lookupTbl
            LtDatumHash
            hashBytes
    tellTriple
        ( Triple
            datumSubj
            (PIri (vocabCurie TermHasHash))
            (OBnode hashBnode)
        )
    emitDecodedOrOpaque
        datumSubj
        bnodeBase
        datumValidatorPick
        decodeResult
        rawBytes

{- | Find a body output whose 'DatumHash'-only datum references the
given hash. Used by 'emitDatumWitnessEntry' to recover the
payment-credential script hash the blueprint index keys on
(FR-006).

Inline-datum outputs do not contribute — their datum body emits
in 'Cardano.Tx.Graph.Emit.Project.emitOutputDatum' against the
output directly. Outputs with @NoDatum@ obviously don't either.
-}
findOutputForDatumHash ::
    DataHash -> [TxOut ConwayEra] -> Maybe (TxOut ConwayEra)
findOutputForDatumHash needle = go
  where
    go [] = Nothing
    go (out : rest) =
        case out ^. datumTxOutL of
            DatumHash dh | dh == needle -> Just out
            _ -> go rest

----------------------------------------------------------------------
-- Script witnesses
----------------------------------------------------------------------

emitScriptWitnesses ::
    LookupTable -> Map ScriptHash (Script ConwayEra) -> Emit ()
emitScriptWitnesses lookupTbl scripts =
    mapM_
        (uncurry (emitScriptWitnessEntry lookupTbl))
        (zip [1 ..] (Map.toAscList scripts))

emitScriptWitnessEntry ::
    LookupTable ->
    Int ->
    (ScriptHash, Script ConwayEra) ->
    Emit ()
emitScriptWitnessEntry lookupTbl k (_, script) = do
    let scriptSubj = SBnode (idScriptWitnessBnode k)
        ScriptHash hh = hashScript script
        hashBytes = hashToBytes hh
        rawBytes = scriptRawBytes script
        (classTerm, mVersion) = case toPlutusScript script of
            Just ps ->
                ( TermPlutusScript
                , Just (plutusVersionInt (plutusScriptLanguage ps))
                )
            Nothing -> (TermNativeScript, Nothing)
    tellTriple
        (Triple scriptSubj PRdfType (OIri (vocabCurie classTerm)))
    hashBnode <-
        resolveCredentialAndIntroduceIdent
            lookupTbl
            LtScriptHash
            hashBytes
    tellTriple
        ( Triple
            scriptSubj
            (PIri (vocabCurie TermHasHash))
            (OBnode hashBnode)
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

scriptRawBytes :: Script ConwayEra -> ByteString
scriptRawBytes = serialize' (eraProtVerLow @ConwayEra)

-- | Map ledger 'Language' to its Plutus version integer.
plutusVersionInt :: Language -> Int
plutusVersionInt = \case
    PlutusV1 -> 1
    PlutusV2 -> 2
    PlutusV3 -> 3
    PlutusV4 -> 4

----------------------------------------------------------------------
-- Bootstrap witnesses
----------------------------------------------------------------------

emitBootstrapWitnesses :: Set BootstrapWitness -> Emit ()
emitBootstrapWitnesses wits =
    mapM_
        (uncurry emitBootstrapWitnessEntry)
        (zip [1 ..] (Set.toAscList wits))

emitBootstrapWitnessEntry :: Int -> BootstrapWitness -> Emit ()
emitBootstrapWitnessEntry k wit = do
    let bwSubj = SBnode (idBootstrapWitnessBnode k)
        rawBytes = serialize' (eraProtVerLow @ConwayEra) wit
    tellTriple
        (Triple bwSubj PRdfType (OIri (vocabCurie TermBootstrapWitness)))
    tellTriple
        (Triple bwSubj PRdfType (OIri (vocabCurie TermOpaqueLeaf)))
    tellTriple
        ( Triple
            bwSubj
            (PIri (vocabCurie TermHasRawBytes))
            (OStringLit (hexText rawBytes))
        )

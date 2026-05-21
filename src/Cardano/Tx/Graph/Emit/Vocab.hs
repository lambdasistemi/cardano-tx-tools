{- |
Module      : Cardano.Tx.Graph.Emit.Vocab
Description : Single-source-of-truth registry of vocab IRIs used by the body emitter.
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. The projection
walker ('Cardano.Tx.Graph.Emit.Project') and the Turtle / JSON-LD
serializers route every emitted IRI through this registry; the
'Cardano.Tx.Graph.Emit.VocabTraceabilitySpec' (analyzer H1
closer) cross-checks the emitter output against
'allVocabTerms' + the fixture-local prefix.

Closes spec FR-009 + SC-005 (vocab traceability) for the
fixture-02 coverage shipped by T005. Future slices (T006-T010)
extend the enum as new leaves require new terms.
-}
module Cardano.Tx.Graph.Emit.Vocab (
    -- * Prefix bases
    cardanoPrefix,
    rdfsPrefix,
    rdfPrefix,
    fixturePrefixBase,

    -- * Vocab term registry
    VocabTerm (..),
    vocabIri,
    vocabCurie,
    allVocabTerms,
) where

import Data.Text (Text)

-- | The kmaps Phase A @cardano:@ namespace base.
cardanoPrefix :: Text
cardanoPrefix =
    "https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#"

-- | The RDF Schema namespace.
rdfsPrefix :: Text
rdfsPrefix = "http://www.w3.org/2000/01/rdf-schema#"

{- | The core RDF namespace. Carries 'rdf:first', 'rdf:rest', and
'rdf:nil' — the list-cell primitives T104 emits when an output
carries a non-empty multi-asset value.
-}
rdfPrefix :: Text
rdfPrefix = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

{- | The fixture-local prefix base. The full @\@prefix :@ IRI is
@\<fixturePrefixBase\>\<slug\>#@ for a given fixture slug.
-}
fixturePrefixBase :: Text
fixturePrefixBase =
    "https://lambdasistemi.github.io/cardano-tx-tools/fixtures/"

{- | Every @cardano:@-namespaced term the body emitter writes.

Adding a new term requires extending this enum; the serializer's
'vocabIri' / 'vocabCurie' patterns surface gaps via
@-Wincomplete-patterns@. The traceability spec asserts every
@cardano:@-prefixed IRI in the emitter output traces to one of
these.
-}
data VocabTerm
    = -- Classes
      TermTransaction
    | TermInput
    | TermOutput
    | TermAddress
    | TermPaymentCredential
    | TermStakeCredential
    | TermMint
    | TermPolicy
    | TermAsset
    | TermWithdrawal
    | TermStakeDelegation
    | TermVoteDelegation
    | TermPool
    | TermDRep
    | TermDatum
    | -- Body predicates
      TermHasInput
    | TermHasOutput
    | TermHasFee
    | TermResolvedTo
    | TermAtAddress
    | TermBech32
    | TermHasPaymentCredential
    | TermHasStakeCredential
    | TermHasIdentifier
    | TermHasMint
    | TermHasPolicy
    | TermHasAsset
    | TermHasWithdrawal
    | TermOnCredential
    | TermWithdrawalAccount
    | TermHasCertificate
    | TermToPool
    | TermToDRep
    | TermHasCollateralInput
    | TermHasReferenceInput
    | TermHasProposal
    | TermDecodedAs
    | TermFromTxOutRef
    | -- Value semantics (T104 / S3 — output ADA + multi-asset)
      TermLovelace
    | TermHasAssetValue
    | TermMintsAsset
    | TermQuantity
    | -- Datum + reference-script sub-block (T105 / S4)
      TermHasDatum
    | TermHasReferenceScript
    | TermHasHash
    | TermHasRawBytes
    | -- Body-root predicates (T107 / S6 — validity interval,
      -- network id, script-data hash, aux-data hash)
      TermHasValidityInterval
    | TermIntervalStart
    | TermIntervalEnd
    | TermNetworkId
    | TermScriptDataHash
    | TermAuxiliaryDataHash
    | -- Required signers (T116 / S15)
      TermHasRequiredSigner
    | -- Collateral (T117 / S16)
      TermTotalCollateral
    | TermHasCollateralReturn
    | -- Reference-script script-language discrimination
      -- (T118 / S17). 'TermPlutusScript' / 'TermNativeScript'
      -- are NOT yet declared canonically; they're invented
      -- locally per A-006 and get exported upstream via T122b.
      TermPlutusScript
    | TermNativeScript
    | TermHasVersion
    deriving stock (Eq, Ord, Show, Enum, Bounded)

{- | The full IRI for a vocab term — e.g.
@"https://…/cardano#hasInput"@. The serializer normally writes
the prefixed CURIE ('vocabCurie'); the IRI form is the canonical
target the traceability spec compares against.
-}
vocabIri :: VocabTerm -> Text
vocabIri = \case
    TermTransaction -> cardanoPrefix <> "Transaction"
    TermInput -> cardanoPrefix <> "Input"
    TermOutput -> cardanoPrefix <> "Output"
    TermAddress -> cardanoPrefix <> "Address"
    TermPaymentCredential -> cardanoPrefix <> "PaymentCredential"
    TermStakeCredential -> cardanoPrefix <> "StakeCredential"
    TermMint -> cardanoPrefix <> "Mint"
    TermPolicy -> cardanoPrefix <> "Policy"
    TermAsset -> cardanoPrefix <> "Asset"
    TermWithdrawal -> cardanoPrefix <> "Withdrawal"
    TermStakeDelegation -> cardanoPrefix <> "StakeDelegation"
    TermVoteDelegation -> cardanoPrefix <> "VoteDelegation"
    TermPool -> cardanoPrefix <> "Pool"
    TermDRep -> cardanoPrefix <> "DRep"
    TermDatum -> cardanoPrefix <> "Datum"
    TermHasInput -> cardanoPrefix <> "hasInput"
    TermHasOutput -> cardanoPrefix <> "hasOutput"
    TermHasFee -> cardanoPrefix <> "hasFee"
    TermResolvedTo -> cardanoPrefix <> "resolvedTo"
    TermAtAddress -> cardanoPrefix <> "atAddress"
    TermBech32 -> cardanoPrefix <> "bech32"
    TermHasPaymentCredential -> cardanoPrefix <> "hasPaymentCredential"
    TermHasStakeCredential -> cardanoPrefix <> "hasStakeCredential"
    TermHasIdentifier -> cardanoPrefix <> "hasIdentifier"
    TermHasMint -> cardanoPrefix <> "hasMint"
    TermHasPolicy -> cardanoPrefix <> "hasPolicy"
    TermHasAsset -> cardanoPrefix <> "hasAsset"
    TermHasWithdrawal -> cardanoPrefix <> "hasWithdrawal"
    TermOnCredential -> cardanoPrefix <> "onCredential"
    TermWithdrawalAccount -> cardanoPrefix <> "withdrawalAccount"
    TermHasCertificate -> cardanoPrefix <> "hasCertificate"
    TermToPool -> cardanoPrefix <> "toPool"
    TermToDRep -> cardanoPrefix <> "toDRep"
    TermHasCollateralInput -> cardanoPrefix <> "hasCollateralInput"
    TermHasReferenceInput -> cardanoPrefix <> "hasReferenceInput"
    TermHasProposal -> cardanoPrefix <> "hasProposal"
    TermDecodedAs -> cardanoPrefix <> "decodedAs"
    TermFromTxOutRef -> cardanoPrefix <> "fromTxOutRef"
    TermLovelace -> cardanoPrefix <> "lovelace"
    TermHasAssetValue -> cardanoPrefix <> "hasAssetValue"
    TermMintsAsset -> cardanoPrefix <> "mintsAsset"
    TermQuantity -> cardanoPrefix <> "quantity"
    TermHasDatum -> cardanoPrefix <> "hasDatum"
    TermHasReferenceScript -> cardanoPrefix <> "hasReferenceScript"
    TermHasHash -> cardanoPrefix <> "hasHash"
    TermHasRawBytes -> cardanoPrefix <> "hasRawBytes"
    TermHasValidityInterval -> cardanoPrefix <> "hasValidityInterval"
    TermIntervalStart -> cardanoPrefix <> "intervalStart"
    TermIntervalEnd -> cardanoPrefix <> "intervalEnd"
    TermNetworkId -> cardanoPrefix <> "networkId"
    TermScriptDataHash -> cardanoPrefix <> "scriptDataHash"
    TermAuxiliaryDataHash -> cardanoPrefix <> "auxiliaryDataHash"
    TermHasRequiredSigner -> cardanoPrefix <> "hasRequiredSigner"
    TermTotalCollateral -> cardanoPrefix <> "totalCollateral"
    TermHasCollateralReturn -> cardanoPrefix <> "hasCollateralReturn"
    TermPlutusScript -> cardanoPrefix <> "PlutusScript"
    TermNativeScript -> cardanoPrefix <> "NativeScript"
    TermHasVersion -> cardanoPrefix <> "hasVersion"

{- | The prefixed CURIE form, e.g. @"cardano:hasInput"@. Every
term in this registry lives under the @cardano:@ prefix; the
serializer emits the CURIE form so its output stays byte-equal
to the artisan reference.
-}
vocabCurie :: VocabTerm -> Text
vocabCurie = \case
    TermTransaction -> "cardano:Transaction"
    TermInput -> "cardano:Input"
    TermOutput -> "cardano:Output"
    TermAddress -> "cardano:Address"
    TermPaymentCredential -> "cardano:PaymentCredential"
    TermStakeCredential -> "cardano:StakeCredential"
    TermMint -> "cardano:Mint"
    TermPolicy -> "cardano:Policy"
    TermAsset -> "cardano:Asset"
    TermWithdrawal -> "cardano:Withdrawal"
    TermStakeDelegation -> "cardano:StakeDelegation"
    TermVoteDelegation -> "cardano:VoteDelegation"
    TermPool -> "cardano:Pool"
    TermDRep -> "cardano:DRep"
    TermDatum -> "cardano:Datum"
    TermHasInput -> "cardano:hasInput"
    TermHasOutput -> "cardano:hasOutput"
    TermHasFee -> "cardano:hasFee"
    TermResolvedTo -> "cardano:resolvedTo"
    TermAtAddress -> "cardano:atAddress"
    TermBech32 -> "cardano:bech32"
    TermHasPaymentCredential -> "cardano:hasPaymentCredential"
    TermHasStakeCredential -> "cardano:hasStakeCredential"
    TermHasIdentifier -> "cardano:hasIdentifier"
    TermHasMint -> "cardano:hasMint"
    TermHasPolicy -> "cardano:hasPolicy"
    TermHasAsset -> "cardano:hasAsset"
    TermHasWithdrawal -> "cardano:hasWithdrawal"
    TermOnCredential -> "cardano:onCredential"
    TermWithdrawalAccount -> "cardano:withdrawalAccount"
    TermHasCertificate -> "cardano:hasCertificate"
    TermToPool -> "cardano:toPool"
    TermToDRep -> "cardano:toDRep"
    TermHasCollateralInput -> "cardano:hasCollateralInput"
    TermHasReferenceInput -> "cardano:hasReferenceInput"
    TermHasProposal -> "cardano:hasProposal"
    TermDecodedAs -> "cardano:decodedAs"
    TermFromTxOutRef -> "cardano:fromTxOutRef"
    TermLovelace -> "cardano:lovelace"
    TermHasAssetValue -> "cardano:hasAssetValue"
    TermMintsAsset -> "cardano:mintsAsset"
    TermQuantity -> "cardano:quantity"
    TermHasDatum -> "cardano:hasDatum"
    TermHasReferenceScript -> "cardano:hasReferenceScript"
    TermHasHash -> "cardano:hasHash"
    TermHasRawBytes -> "cardano:hasRawBytes"
    TermHasValidityInterval -> "cardano:hasValidityInterval"
    TermIntervalStart -> "cardano:intervalStart"
    TermIntervalEnd -> "cardano:intervalEnd"
    TermNetworkId -> "cardano:networkId"
    TermScriptDataHash -> "cardano:scriptDataHash"
    TermAuxiliaryDataHash -> "cardano:auxiliaryDataHash"
    TermHasRequiredSigner -> "cardano:hasRequiredSigner"
    TermTotalCollateral -> "cardano:totalCollateral"
    TermHasCollateralReturn -> "cardano:hasCollateralReturn"
    TermPlutusScript -> "cardano:PlutusScript"
    TermNativeScript -> "cardano:NativeScript"
    TermHasVersion -> "cardano:hasVersion"

{- | Every vocab term registered in 'VocabTerm', in declaration
order.
-}
allVocabTerms :: [VocabTerm]
allVocabTerms = [minBound .. maxBound]

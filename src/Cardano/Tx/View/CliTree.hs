{- |
Module      : Cardano.Tx.View.CliTree
Description : cli-tree projection over a canonical Turtle graph.
License     : Apache-2.0

Implements the @cli-tree@ view contract (see @views\/cli-tree.rq@):
a graph-faithful text-tree projection of the tx subject's body
sections — inputs, reference inputs, outputs (with their address,
coin, assets, datum, and reference script), collateral, mint,
withdrawals, certificates, proposals, and fee.

Entity-label resolution is honest: when an Identifier bnode reached
from an address payment credential, an asset class, a withdrawal
account, or a certificate credential is also reached from a
@cardano:Entity@ @cardano:hasIdentifier@ link, the entity's
@rdfs:label@ is rendered. Otherwise the raw graph leaf (bech32,
bytesHex, IRI name) is rendered.

Empty-result invariant (FR-008): if the graph has no subject of type
@cardano:Transaction@, the projection returns the empty byte string.
The CLI dispatcher then writes nothing to stdout and exits 0.
-}
module Cardano.Tx.View.CliTree (renderCliTree) where

import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

import Cardano.Tx.View.Turtle (
    Graph,
    Object (..),
    Predicate (..),
    Subject (..),
    findAllObjects,
    findFirstObject,
    lookupPreds,
 )

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

-- | Render the cli-tree projection of a canonical Turtle graph.
renderCliTree :: Graph -> ByteString
renderCliTree g = case findTransactionSubject g of
    Nothing -> mempty
    Just tx ->
        TextEncoding.encodeUtf8 $
            renderTx (entityMap g) g tx

----------------------------------------------------------------------
-- Locate the Transaction subject
----------------------------------------------------------------------

findTransactionSubject :: Graph -> Maybe Subject
findTransactionSubject g =
    listToMaybe
        [ s
        | (s, preds) <- Map.toList g
        , any isTransactionType preds
        ]
  where
    isTransactionType (PA, OIri "cardano:Transaction") = True
    isTransactionType _ = False

----------------------------------------------------------------------
-- Entity-label map
----------------------------------------------------------------------

{- | Map from Identifier bnode name (the @_:foo@ tail) to its
@rdfs:label@ as declared by some @cardano:Entity@ subject.
-}
entityMap :: Graph -> Map Text Text
entityMap g =
    Map.fromList
        [ (idName, label)
        | (_, preds) <- Map.toList g
        , any (\(p, o) -> p == PA && o == OIri "cardano:Entity") preds
        , Just label <- [findStringPred (PIri "rdfs:label") preds]
        , idName <- [n | (PIri "cardano:hasIdentifier", OBnode n) <- preds]
        ]

----------------------------------------------------------------------
-- Top-level body renderer
----------------------------------------------------------------------

renderTx :: Map Text Text -> Graph -> Subject -> Text
renderTx em g tx =
    Text.concat
        [ section
        | section <- map ($ ctx) sections
        , not (Text.null section)
        ]
        <> renderFee g tx
  where
    ctx = Ctx em g tx
    sections =
        [ renderInputsSection
        , renderReferenceInputsSection
        , renderOutputsSection
        , renderMintSection
        , renderWithdrawalsSection
        , renderCertificatesSection
        , renderCollateralSection
        , renderProposalsSection
        ]

-- | Bundle of state every section renderer needs.
data Ctx = Ctx
    { ctxEntities :: !(Map Text Text)
    , ctxGraph :: !Graph
    , ctxTx :: !Subject
    }

----------------------------------------------------------------------
-- inputs: / referenceInputs: / collateral:
----------------------------------------------------------------------

renderInputsSection :: Ctx -> Text
renderInputsSection ctx@Ctx{ctxGraph, ctxTx} =
    renderTxOutRefSection
        "inputs:"
        (bnodeObjects (PIri "cardano:hasInput") ctxTx ctxGraph)
        ctx

renderReferenceInputsSection :: Ctx -> Text
renderReferenceInputsSection ctx@Ctx{ctxGraph, ctxTx} =
    renderTxOutRefSection
        "referenceInputs:"
        (bnodeObjects (PIri "cardano:hasReferenceInput") ctxTx ctxGraph)
        ctx

renderCollateralSection :: Ctx -> Text
renderCollateralSection ctx@Ctx{ctxGraph, ctxTx} =
    renderTxOutRefSection
        "collateral:"
        (bnodeObjects (PIri "cardano:hasCollateralInput") ctxTx ctxGraph)
        ctx

renderTxOutRefSection :: Text -> [Subject] -> Ctx -> Text
renderTxOutRefSection _ [] _ = ""
renderTxOutRefSection header subs Ctx{ctxGraph} =
    header
        <> "\n"
        <> Text.concat (map renderOne subs)
  where
    renderOne s =
        let outRef =
                bnodeObject (PIri "cardano:fromTxOutRef") s ctxGraph
            txOutRefText = case outRef of
                Just outRefSubj -> renderTxOutRef ctxGraph outRefSubj
                Nothing -> "<missing TxOutRef>"
         in "  - txOutRef: " <> txOutRefText <> "\n"

renderTxOutRef :: Graph -> Subject -> Text
renderTxOutRef g s =
    let txIdHex =
            case bnodeObject (PIri "cardano:hasTxId") s g of
                Just idSubj ->
                    fromMaybe (subjectText (SBnode "")) $
                        findStringObject (PIri "cardano:bytesHex") idSubj g
                Nothing -> "<missing TxId>"
        ix = case findFirstObject s (PIri "cardano:hasIndex") g of
            Just (OIntLit i) -> Text.pack (show i)
            _ -> "0"
     in txIdHex <> "#" <> ix

----------------------------------------------------------------------
-- outputs:
----------------------------------------------------------------------

renderOutputsSection :: Ctx -> Text
renderOutputsSection ctx@Ctx{ctxGraph, ctxTx} =
    case bnodeObjects (PIri "cardano:hasOutput") ctxTx ctxGraph of
        [] -> ""
        outs -> "outputs:\n" <> Text.concat (map (renderOutput ctx) outs)

renderOutput :: Ctx -> Subject -> Text
renderOutput ctx@Ctx{ctxGraph, ctxEntities} s =
    "  - address: "
        <> addr
        <> "\n"
        <> "    coin: "
        <> renderAda lovelace
        <> "\n"
        <> assetsBlock
        <> datumBlock
        <> refScriptBlock
  where
    addr = case findFirstObject s (PIri "cardano:atAddress") ctxGraph of
        Just (OBnode addrName) ->
            resolveAddressLabel ctxGraph ctxEntities (SBnode addrName)
        Just other -> objectText other
        Nothing -> "<missing address>"
    lovelace = case findFirstObject s (PIri "cardano:lovelace") ctxGraph of
        Just (OIntLit i) -> i
        _ -> 0
    assetsBlock = case bnodeObject (PIri "cardano:hasAssetValue") s ctxGraph of
        Nothing -> ""
        Just listSubj -> renderAssetList ctx listSubj
    datumBlock = case bnodeObject (PIri "cardano:hasDatum") s ctxGraph of
        Nothing -> ""
        Just dSubj -> renderDatumBlock ctxGraph dSubj
    refScriptBlock = case bnodeObject (PIri "cardano:hasReferenceScript") s ctxGraph of
        Nothing -> ""
        Just rSubj -> renderRefScriptBlock ctxGraph rSubj

renderAssetList :: Ctx -> Subject -> Text
renderAssetList ctx listSubj =
    case walkRdfList (ctxGraph ctx) listSubj of
        [] -> ""
        assets ->
            "    assets:\n"
                <> Text.concat (map (renderAssetEntry ctx) assets)

renderAssetEntry :: Ctx -> Subject -> Text
renderAssetEntry ctx s =
    let label = case bnodeObject (PIri "cardano:hasIdentifier") s (ctxGraph ctx) of
            Just idSubj -> resolveIdentifierLabel (ctxGraph ctx) (ctxEntities ctx) idSubj
            Nothing -> "<missing asset identifier>"
        qty = case findFirstObject s (PIri "cardano:quantity") (ctxGraph ctx) of
            Just (OIntLit i) -> Text.pack (show i)
            _ -> "0"
     in "      - " <> label <> ": " <> qty <> "\n"

renderDatumBlock :: Graph -> Subject -> Text
renderDatumBlock g s =
    let hashHex =
            case bnodeObject (PIri "cardano:hasHash") s g of
                Just idSubj -> findStringObject (PIri "cardano:bytesHex") idSubj g
                Nothing -> Nothing
        rawBytes = findStringObject (PIri "cardano:hasRawBytes") s g
        decodedAs = findStringObject (PIri "cardano:decodedAs") s g
     in "    datum:\n"
            <> renderOptField "      hash: " hashHex
            <> renderOptField "      decodedAs: " decodedAs
            <> renderOptField "      rawBytes: " rawBytes

renderRefScriptBlock :: Graph -> Subject -> Text
renderRefScriptBlock g s =
    let ty = case findFirstObject s PA g of
            Just (OIri n) -> Just n
            _ -> Nothing
        hashHex = case bnodeObject (PIri "cardano:hasHash") s g of
            Just idSubj -> findStringObject (PIri "cardano:bytesHex") idSubj g
            Nothing -> Nothing
     in "    refScript:\n"
            <> renderOptField "      type: " ty
            <> renderOptField "      hash: " hashHex

----------------------------------------------------------------------
-- mint:
----------------------------------------------------------------------

renderMintSection :: Ctx -> Text
renderMintSection Ctx{ctxGraph, ctxTx, ctxEntities} =
    case bnodeObjects (PIri "cardano:hasMint") ctxTx ctxGraph of
        [] -> ""
        ms -> "mint:\n" <> Text.concat (map renderMint ms)
  where
    renderMint m =
        let assetSubj =
                bnodeObject (PIri "cardano:mintsAsset") m ctxGraph
            qty = case findFirstObject m (PIri "cardano:quantity") ctxGraph of
                Just (OIntLit i) -> i
                _ -> 0
            label = case assetSubj of
                Just a -> case bnodeObject (PIri "cardano:hasIdentifier") a ctxGraph of
                    Just idSubj ->
                        resolveIdentifierLabel ctxGraph ctxEntities idSubj
                    Nothing -> "<missing asset identifier>"
                Nothing -> "<missing asset>"
            sign = if qty >= 0 then "+" else ""
         in "  - " <> label <> ": " <> sign <> Text.pack (show qty) <> "\n"

----------------------------------------------------------------------
-- withdrawals:
----------------------------------------------------------------------

renderWithdrawalsSection :: Ctx -> Text
renderWithdrawalsSection Ctx{ctxGraph, ctxTx, ctxEntities} =
    case bnodeObjects (PIri "cardano:hasWithdrawal") ctxTx ctxGraph of
        [] -> ""
        ws -> "withdrawals:\n" <> Text.concat (map renderW ws)
  where
    renderW w =
        let acct = case bnodeObject (PIri "cardano:withdrawalAccount") w ctxGraph of
                Just idSubj ->
                    resolveIdentifierLabel ctxGraph ctxEntities idSubj
                Nothing -> "<missing withdrawal account>"
            amount = case findFirstObject w (PIri "cardano:lovelace") ctxGraph of
                Just (OIntLit i) -> i
                _ -> 0
         in "  - account: "
                <> acct
                <> "\n    amount: "
                <> renderAda amount
                <> "\n"

----------------------------------------------------------------------
-- certificates:
----------------------------------------------------------------------

renderCertificatesSection :: Ctx -> Text
renderCertificatesSection Ctx{ctxGraph, ctxTx, ctxEntities} =
    case bnodeObjects (PIri "cardano:hasCertificate") ctxTx ctxGraph of
        [] -> ""
        cs -> "certificates:\n" <> Text.concat (map renderCert cs)
  where
    renderCert c =
        let ty = case findFirstObject c PA ctxGraph of
                Just (OIri n) -> stripCardanoPrefix n
                _ -> "Unknown"
            onCred = case bnodeObject (PIri "cardano:onCredential") c ctxGraph of
                Just s -> resolveIdentifierLabel ctxGraph ctxEntities s
                Nothing -> "<missing onCredential>"
            extras = certExtras c
         in "  - "
                <> ty
                <> ":\n      onCredential: "
                <> onCred
                <> "\n"
                <> extras

    certExtras c =
        let toPool = case bnodeObject (PIri "cardano:toPool") c ctxGraph of
                Just s -> Just (renderPoolOrDRep s)
                Nothing -> Nothing
            toDRep = case bnodeObject (PIri "cardano:toDRep") c ctxGraph of
                Just s -> Just (renderPoolOrDRep s)
                Nothing -> Nothing
         in renderOptField "      toPool: " toPool
                <> renderOptField "      toDRep: " toDRep

    renderPoolOrDRep s =
        case bnodeObject (PIri "cardano:hasIdentifier") s ctxGraph of
            Just idSubj ->
                resolveIdentifierLabel ctxGraph ctxEntities idSubj
            Nothing -> subjectText s

----------------------------------------------------------------------
-- proposals:
----------------------------------------------------------------------

renderProposalsSection :: Ctx -> Text
renderProposalsSection Ctx{ctxGraph, ctxTx} =
    case bnodeObjects (PIri "cardano:hasProposal") ctxTx ctxGraph of
        [] -> ""
        ps -> "proposals:\n" <> Text.concat (map renderProposal ps)
  where
    renderProposal p =
        case bnodeObject (PIri "cardano:hasDatum") p ctxGraph of
            Just dSubj ->
                "  - datum:\n"
                    <> renderOptField
                        "      decodedAs: "
                        (findStringObject (PIri "cardano:decodedAs") dSubj ctxGraph)
                    <> ( case bnodeObject (PIri "cardano:hasHash") dSubj ctxGraph of
                            Just idSubj ->
                                renderOptField
                                    "      hash: "
                                    (findStringObject (PIri "cardano:bytesHex") idSubj ctxGraph)
                            Nothing -> ""
                       )
                    <> renderOptField
                        "      rawBytes: "
                        (findStringObject (PIri "cardano:hasRawBytes") dSubj ctxGraph)
            Nothing -> "  - <proposal with no datum>\n"

----------------------------------------------------------------------
-- fee:
----------------------------------------------------------------------

renderFee :: Graph -> Subject -> Text
renderFee g tx =
    let fee = case findFirstObject tx (PIri "cardano:hasFee") g of
            Just (OIntLit i) -> i
            _ -> 0
     in "fee: " <> renderAda fee <> "\n"

----------------------------------------------------------------------
-- Label resolution
----------------------------------------------------------------------

{- | Resolve a subject that names an Identifier (or that's reachable
through a hasIdentifier link) to either its entity label or its
@cardano:bytesHex@.
-}
resolveIdentifierLabel :: Graph -> Map Text Text -> Subject -> Text
resolveIdentifierLabel g em s = case s of
    SBnode name
        | Just label <- Map.lookup name em -> label
        | otherwise -> case findStringObject (PIri "cardano:bytesHex") s g of
            Just hex -> hex
            Nothing -> "_:" <> name
    SIri name -> name

{- | Resolve an Address subject to either an entity label (when its
payment credential's hasIdentifier bnode is part of an entity) or
its @cardano:bech32@ string.
-}
resolveAddressLabel :: Graph -> Map Text Text -> Subject -> Text
resolveAddressLabel g em addrSubj =
    let bech32 =
            fromMaybe (subjectText addrSubj) $
                findStringObject (PIri "cardano:bech32") addrSubj g
        mLabel = do
            pcObj <- findFirstObject addrSubj (PIri "cardano:hasPaymentCredential") g
            pc <- objectToSubject pcObj
            idObj <- findFirstObject pc (PIri "cardano:hasIdentifier") g
            idSubj <- objectToSubject idObj
            case idSubj of
                SBnode n -> Map.lookup n em
                _ -> Nothing
     in fromMaybe bech32 mLabel

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{- | All blank-node objects on @subject pred@, lifted to 'Subject'
values. Non-bnode objects on the same predicate are dropped.
-}
bnodeObjects :: Predicate -> Subject -> Graph -> [Subject]
bnodeObjects p s g = mapMaybe objectToSubject (findAllObjects s p g)

-- | The first blank-node object on @subject pred@, lifted to 'Subject'.
bnodeObject :: Predicate -> Subject -> Graph -> Maybe Subject
bnodeObject p s g = listToMaybe (bnodeObjects p s g)

objectToSubject :: Object -> Maybe Subject
objectToSubject = \case
    OBnode n -> Just (SBnode n)
    OIri n -> Just (SIri n)
    _ -> Nothing

-- | Find the first string-literal object on @subject pred@.
findStringObject :: Predicate -> Subject -> Graph -> Maybe Text
findStringObject p s g = findStringPred p (lookupPreds s g)

findStringPred :: Predicate -> [(Predicate, Object)] -> Maybe Text
findStringPred p preds =
    listToMaybe [v | (p', OStringLit v) <- preds, p == p']

-- | Walk an rdf:first/rdf:rest list head until rdf:nil.
walkRdfList :: Graph -> Subject -> [Subject]
walkRdfList g = go
  where
    go s
        | s == SIri "rdf:nil" = []
        | otherwise =
            let firstHead =
                    findFirstObject s (PIri "rdf:first") g
                        >>= objectToSubject
                tail_ =
                    findFirstObject s (PIri "rdf:rest") g
                        >>= objectToSubject
             in case (firstHead, tail_) of
                    (Just h, Just t) -> h : go t
                    (Just h, Nothing) -> [h]
                    _ -> []

-- | Render a 'Subject' as its source-level surface form.
subjectText :: Subject -> Text
subjectText (SBnode n) = "_:" <> n
subjectText (SIri n) = n

-- | Render an 'Object' as its source-level surface form (debug only).
objectText :: Object -> Text
objectText = \case
    OBnode n -> "_:" <> n
    OIri n -> n
    OStringLit s -> "\"" <> s <> "\""
    OIntLit i -> Text.pack (show i)

-- | Format a lovelace integer as @N.NNNNNN ADA@.
renderAda :: Integer -> Text
renderAda lovelace =
    let (q, r) = lovelace `quotRem` 1_000_000
        sign = if lovelace < 0 then "-" else ""
        wholeAbs = Text.pack (show (abs q))
        fracStr = Text.justifyRight 6 '0' (Text.pack (show (abs r)))
     in sign <> wholeAbs <> "." <> fracStr <> " ADA"

stripCardanoPrefix :: Text -> Text
stripCardanoPrefix t = fromMaybe t (Text.stripPrefix "cardano:" t)

{- | Render an optional field as @\<header\>\<value\>\n@; empty when
the value is 'Nothing'.
-}
renderOptField :: Text -> Maybe Text -> Text
renderOptField _ Nothing = ""
renderOptField header (Just v) = header <> v <> "\n"

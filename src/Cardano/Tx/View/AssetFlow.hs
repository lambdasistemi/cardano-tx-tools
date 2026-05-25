{- |
Module      : Cardano.Tx.View.AssetFlow
Description : asset-flow projection over a canonical Turtle graph.
License     : Apache-2.0

Implements the @asset-flow@ view contract (see @views\/asset-flow.rq@):
a flat TSV summary of asset movement in the transaction, one row per
output asset (ada and native), per mint, and per withdrawal.

Row format (tab-separated, terminated by a newline):

@
\<assetClass\>\\t\<quantity\>\\t\<source\>\\t\<destination\>
@

* @assetClass@: the entity label of the asset (when bound to a
  @cardano:Entity@), or its @cardano:bytesHex@ leaf, or the literal
  @ada@ for output lovelace and withdrawal lovelace.
* @quantity@: the integer amount (lovelace count for ada rows, asset
  quantity for native-asset rows, signed mint quantity for mint rows).
* @source@: the entity label that produced the value (resolved through
  the withdrawal account's identifier for withdrawal rows), or
  @\<mint\>@ for mint rows, or the explicit @\<unknown\>@ placeholder
  when no input UTxO resolution is on the canonical graph.
* @destination@: the entity label of the recipient (resolved through
  the output address' payment credential), or the address bech32, or
  @\<unknown\>@.

Empty-result invariant (FR-008): if the graph has no subject of type
@cardano:Transaction@, the projection returns the empty byte string.
-}
module Cardano.Tx.View.AssetFlow (renderAssetFlow) where

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

-- | Render the asset-flow projection of a canonical Turtle graph.
renderAssetFlow :: Graph -> ByteString
renderAssetFlow g = case findTransactionSubject g of
    Nothing -> mempty
    Just tx ->
        TextEncoding.encodeUtf8 $
            Text.concat (assetFlowRows (entityMap g) g tx)

assetFlowRows :: Map Text Text -> Graph -> Subject -> [Text]
assetFlowRows em g tx =
    concatMap (outputRows em g) (hasObjects (PIri "cardano:hasOutput") tx g)
        <> concatMap (mintRows em g) (hasObjects (PIri "cardano:hasMint") tx g)
        <> concatMap
            (withdrawalRows em g)
            (hasObjects (PIri "cardano:hasWithdrawal") tx g)

----------------------------------------------------------------------
-- Format helpers
----------------------------------------------------------------------

unknownMark :: Text
unknownMark = "<unknown>"

mintMark :: Text
mintMark = "<mint>"

adaLabel :: Text
adaLabel = "ada"

-- | Format one TSV row: @asset\\tqty\\tsource\\tdest\\n@.
formatRow :: Text -> Integer -> Text -> Text -> Text
formatRow asset qty src dst =
    asset
        <> "\t"
        <> Text.pack (show qty)
        <> "\t"
        <> src
        <> "\t"
        <> dst
        <> "\n"

----------------------------------------------------------------------
-- Output rows
----------------------------------------------------------------------

{- | One ada row (when @cardano:lovelace@ is non-zero) plus one row per
asset list entry, in source order. Source is the honest
@\<unknown\>@ placeholder because canonical graphs from @tx-graph@
have no input UTxO resolution.
-}
outputRows :: Map Text Text -> Graph -> Subject -> [Text]
outputRows em g out =
    adaRow <> assetRows
  where
    dest = case findFirstObject out (PIri "cardano:atAddress") g of
        Just (OBnode n) -> resolveAddressLabel g em (SBnode n)
        Just other -> objectText other
        Nothing -> unknownMark
    lovelace = case findFirstObject out (PIri "cardano:lovelace") g of
        Just (OIntLit i) -> i
        _ -> 0
    adaRow
        | lovelace == 0 = []
        | otherwise = [formatRow adaLabel lovelace unknownMark dest]
    assetRows = case bnodeObject (PIri "cardano:hasAssetValue") out g of
        Nothing -> []
        Just listSubj ->
            [ formatRow label qty unknownMark dest
            | a <- walkRdfList g listSubj
            , let label = assetLabel em g a
                  qty = case findFirstObject a (PIri "cardano:quantity") g of
                    Just (OIntLit i) -> i
                    _ -> 0
            ]

----------------------------------------------------------------------
-- Mint rows
----------------------------------------------------------------------

{- | One row per @cardano:hasMint@ entry, marking the source as the
literal @\<mint\>@ token and leaving the destination unknown
(mint receivers are spread across the outputs and the spec
intentionally does not invent a single destination entity).
-}
mintRows :: Map Text Text -> Graph -> Subject -> [Text]
mintRows em g m =
    [formatRow label qty mintMark unknownMark]
  where
    qty = case findFirstObject m (PIri "cardano:quantity") g of
        Just (OIntLit i) -> i
        _ -> 0
    label = case bnodeObject (PIri "cardano:mintsAsset") m g of
        Just a -> assetLabel em g a
        Nothing -> "<missing asset>"

----------------------------------------------------------------------
-- Withdrawal rows
----------------------------------------------------------------------

{- | One ada row per @cardano:hasWithdrawal@ entry, using the
withdrawal account's identifier as the source and leaving the
destination unknown.
-}
withdrawalRows :: Map Text Text -> Graph -> Subject -> [Text]
withdrawalRows em g w =
    [formatRow adaLabel qty src unknownMark]
  where
    qty = case findFirstObject w (PIri "cardano:lovelace") g of
        Just (OIntLit i) -> i
        _ -> 0
    src = case bnodeObject (PIri "cardano:withdrawalAccount") w g of
        Just idSubj -> resolveIdentifierLabel g em idSubj
        Nothing -> unknownMark

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

{- | Map from Identifier bnode name to its @rdfs:label@ as declared by
some @cardano:Entity@ subject.
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
-- Label resolution
----------------------------------------------------------------------

{- | Resolve the asset class label of an @cardano:Asset@-shaped
subject (one that carries a @cardano:hasIdentifier@). Falls back
to a @\<missing asset identifier\>@ marker when the asset has no
identifier link, mirroring the cli-tree projection's honesty rule.
-}
assetLabel :: Map Text Text -> Graph -> Subject -> Text
assetLabel em g a =
    case bnodeObject (PIri "cardano:hasIdentifier") a g of
        Just idSubj -> resolveIdentifierLabel g em idSubj
        Nothing -> "<missing asset identifier>"

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
            pcObj <-
                findFirstObject addrSubj (PIri "cardano:hasPaymentCredential") g
            pc <- objectToSubject pcObj
            idObj <- findFirstObject pc (PIri "cardano:hasIdentifier") g
            idSubj <- objectToSubject idObj
            case idSubj of
                SBnode n -> Map.lookup n em
                _ -> Nothing
     in fromMaybe bech32 mLabel

----------------------------------------------------------------------
-- Graph traversal helpers (duplicated from CliTree; lift to an
-- internal module once a third projection arrives).
----------------------------------------------------------------------

{- | All blank-node / IRI objects on @subject pred@, lifted to
'Subject' values. Non-resource objects are dropped.
-}
hasObjects :: Predicate -> Subject -> Graph -> [Subject]
hasObjects p s g = mapMaybe objectToSubject (findAllObjects s p g)

-- | The first resource object on @subject pred@, lifted to 'Subject'.
bnodeObject :: Predicate -> Subject -> Graph -> Maybe Subject
bnodeObject p s g = listToMaybe (hasObjects p s g)

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

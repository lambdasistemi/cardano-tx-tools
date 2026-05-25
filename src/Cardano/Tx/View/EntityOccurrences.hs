{- |
Module      : Cardano.Tx.View.EntityOccurrences
Description : entity-occurrences projection over a canonical Turtle graph.
License     : Apache-2.0

Implements the @entity-occurrences@ view contract (see
@views\/entity-occurrences.rq@): a flat TSV summary of operator-declared
entities and the number of identifier leaf sites each declaration ties
to that entity.

Row format (tab-separated, terminated by a newline):

@
\<entityLabel\>\\t\<leafSiteCount\>
@

The count is deliberately conservative: only explicit
@cardano:hasIdentifier@ resource links on subjects typed as
@cardano:Entity@ are counted. If the canonical graph does not carry a
declared identifier leaf for an entity, the projection does not invent
one.
-}
module Cardano.Tx.View.EntityOccurrences (renderEntityOccurrences) where

import Data.ByteString (ByteString)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

import Cardano.Tx.View.Turtle (
    Graph,
    Object (..),
    Predicate (..),
    Subject (..),
    lookupPreds,
 )

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

-- | Render the entity-occurrences projection of a canonical Turtle graph.
renderEntityOccurrences :: ByteString -> Graph -> ByteString
renderEntityOccurrences source g =
    TextEncoding.encodeUtf8 $
        Text.concat $
            mapMaybeEntityRow g (entitySubjectsInSourceOrder source)

----------------------------------------------------------------------
-- Row construction
----------------------------------------------------------------------

mapMaybeEntityRow :: Graph -> [Subject] -> [Text]
mapMaybeEntityRow g =
    foldr
        ( \s acc ->
            case entityRow g s of
                Nothing -> acc
                Just row -> row : acc
        )
        []

entityRow :: Graph -> Subject -> Maybe Text
entityRow g subj = do
    let preds = lookupPreds subj g
        count = identifierLeafCount preds
    if isEntity preds && count > 0
        then do
            label <- findStringPred (PIri "rdfs:label") preds
            pure (label <> "\t" <> Text.pack (show count) <> "\n")
        else Nothing

isEntity :: [(Predicate, Object)] -> Bool
isEntity =
    any $ \case
        (PA, OIri "cardano:Entity") -> True
        _ -> False

identifierLeafCount :: [(Predicate, Object)] -> Int
identifierLeafCount =
    length
        . filter
            ( \case
                (PIri "cardano:hasIdentifier", OBnode _) -> True
                (PIri "cardano:hasIdentifier", OIri _) -> True
                _ -> False
            )

findStringPred :: Predicate -> [(Predicate, Object)] -> Maybe Text
findStringPred p =
    foldr
        ( \po acc ->
            case (po, acc) of
                ((p', OStringLit s), Nothing) | p == p' -> Just s
                _ -> acc
        )
        Nothing

----------------------------------------------------------------------
-- Source-order recovery
----------------------------------------------------------------------

{- | Recover declared-entity subject order from the canonical Turtle
source. The 'Graph' index intentionally sorts by subject for lookups;
the view output follows declaration order instead, which is visible in
the source statement stream.
-}
entitySubjectsInSourceOrder :: ByteString -> [Subject]
entitySubjectsInSourceOrder =
    mapMaybe statementSubject
        . filter isEntityStatement
        . statementBlocks
        . Text.lines
        . TextEncoding.decodeUtf8

statementSubject :: Text -> Maybe Subject
statementSubject stmt =
    case Text.words stmt of
        tok : _ -> subjectFromToken tok
        [] -> Nothing

subjectFromToken :: Text -> Maybe Subject
subjectFromToken tok
    | "_:" `Text.isPrefixOf` tok =
        let name = Text.drop 2 tok
         in if Text.null name then Nothing else Just (SBnode name)
    | Text.null tok = Nothing
    | otherwise = Just (SIri tok)

isEntityStatement :: Text -> Bool
isEntityStatement =
    Text.isInfixOf " a cardano:Entity"

statementBlocks :: [Text] -> [Text]
statementBlocks = go [] []
  where
    go acc [] [] = reverse acc
    go acc buf [] = reverse (Text.unlines (reverse buf) : acc)
    go acc [] (line : rest)
        | isSkippable line = go acc [] rest
        | endsWithPeriod line = go (line : acc) [] rest
        | otherwise = go acc [line] rest
    go acc buf (line : rest)
        | endsWithPeriod line =
            go (Text.unlines (reverse (line : buf)) : acc) [] rest
        | otherwise = go acc (line : buf) rest

    isSkippable l =
        let stripped = Text.strip l
         in Text.null stripped
                || Text.isPrefixOf "#" stripped
                || Text.isPrefixOf "@" stripped

    endsWithPeriod t =
        case Text.unsnoc (Text.stripEnd t) of
            Just (_, '.') -> True
            _ -> False

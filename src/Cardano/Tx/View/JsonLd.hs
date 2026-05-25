{- |
Module      : Cardano.Tx.View.JsonLd
Description : JSON-LD projection for tx-view.
License     : Apache-2.0

Renders the canonical Turtle subset parsed by 'Cardano.Tx.View.Turtle'
as deterministic, parseable JSON-LD.

The projection is intentionally bounded to the graph surface this
repository emits and the in-repo Turtle reader accepts. It does not
attempt JSON-LD framing, expansion, compaction beyond CURIE keys, or
RDF dataset normalization. The acceptance contract for #51 is parsed
triple preservation over the supported canonical graph subset, not
byte-equivalence with the existing @tx-graph --format json-ld@ path.
-}
module Cardano.Tx.View.JsonLd (
    renderJsonLd,
) where

import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BSL
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text

import Cardano.Tx.View.Turtle (
    Graph,
    Object (..),
    Predicate (..),
    Subject (..),
 )

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

{- | Render a parsed canonical Turtle graph as JSON-LD.

Shape:

@
{
  "\@context": {
    "cardano": "...cardano#",
    "rdf":     "...rdf-syntax-ns#",
    "rdfs":    "...rdf-schema#",
    "":        "...cardano-tx-tools/fixtures/view#"
  },
  "\@graph": [
    {
      "\@id": "_:tx",
      "\@type": "cardano:Transaction",
      "cardano:hasOutput": [{"\@id": "_:output1"}]
    }
  ]
}
@

An empty graph renders as a parseable JSON-LD document with an empty
@\@graph@ array, satisfying FR-008 for browser consumers.
-}
renderJsonLd :: Graph -> ByteString
renderJsonLd graph =
    BSL.toStrict (Aeson.encode doc) <> "\n"
  where
    doc =
        Object $
            KeyMap.fromList
                [ (Key.fromText "@context", contextValue)
                , (Key.fromText "@graph", graphValue)
                ]
    graphValue =
        Aeson.toJSON $
            map subjectValue $
                Map.toList graph

----------------------------------------------------------------------
-- JSON-LD document pieces
----------------------------------------------------------------------

contextValue :: Value
contextValue =
    Object $
        KeyMap.fromList
            [
                ( Key.fromText "cardano"
                , String "https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#"
                )
            ,
                ( Key.fromText "rdf"
                , String "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                )
            ,
                ( Key.fromText "rdfs"
                , String "http://www.w3.org/2000/01/rdf-schema#"
                )
            ,
                ( Key.fromText ""
                , String "https://lambdasistemi.github.io/cardano-tx-tools/fixtures/view#"
                )
            ]

subjectValue :: (Subject, [(Predicate, Object)]) -> Value
subjectValue (subject, pairs) =
    Object $
        KeyMap.fromList $
            (Key.fromText "@id", String (subjectText subject))
                : typeEntries
                    <> predicateEntries
  where
    (typeObjects, otherPairs) = splitTypes pairs
    typeEntries =
        case typeObjects of
            [] -> []
            objects -> [(Key.fromText "@type", typeObjectsValue objects)]
    predicateEntries =
        [ (Key.fromText predicate, objectsValue objects)
        | (predicate, objects) <- groupPredicateObjects otherPairs
        ]

splitTypes :: [(Predicate, Object)] -> ([Object], [(Text, Object)])
splitTypes = foldr step ([], [])
  where
    step (PA, object) (types, pairs) = (object : types, pairs)
    step (PIri predicate, object) (types, pairs) =
        (types, (predicate, object) : pairs)

groupPredicateObjects :: [(Text, Object)] -> [(Text, [Object])]
groupPredicateObjects = foldr step []
  where
    step (predicate, object) grouped =
        case grouped of
            (predicate', objects) : rest
                | predicate == predicate' ->
                    (predicate', object : objects) : rest
            _ -> (predicate, [object]) : grouped

typeObjectsValue :: [Object] -> Value
typeObjectsValue = \case
    [object] -> String (objectTypeText object)
    objects -> Aeson.toJSON (map (String . objectTypeText) objects)

objectsValue :: [Object] -> Value
objectsValue = \case
    [object] -> objectValue object
    objects -> Aeson.toJSON (map objectValue objects)

objectValue :: Object -> Value
objectValue = \case
    OBnode name ->
        Object $
            KeyMap.fromList
                [(Key.fromText "@id", String ("_:" <> name))]
    OIri name ->
        Object $
            KeyMap.fromList
                [(Key.fromText "@id", String name)]
    OStringLit value -> String value
    OIntLit value -> Number (fromInteger value)

objectTypeText :: Object -> Text
objectTypeText = \case
    OBnode name -> "_:" <> name
    OIri name -> name
    OStringLit value -> value
    OIntLit value -> Text.pack (show value)

subjectText :: Subject -> Text
subjectText = \case
    SBnode name -> "_:" <> name
    SIri name -> name

{- |
Module      : Cardano.Tx.Graph.Rules.Load.Naming
Description : Deterministic bnode-name algorithm for the entity overlay.
License     : Apache-2.0

Implements spec FR-013 / plan D2 — the bnode name attached to each
'EntityIdentifier' is fully determined by:

* the entity that **first** declares the @(leafType, bytesHex)@ pair
  in document order (first-entity-wins on shared identity);
* the leafType, mapped through 'roleSuffix' (only the first character
  lowercased, others preserved verbatim);
* the owning entity's slug.

The composite name is @\\_:\<entitySlug\>_\<roleSuffix\>@ — a Turtle
blank-node label that round-trips through serializers as long as the
@entitySlug@ is alphanumeric (the YAML compiler's @slugify@ already
guarantees this).

For shared identity (two entities reference the same
@(leafType, bytesHex)@), the **second** entity reuses the first
entity's bnode name in its @cardano:hasIdentifier@ triples. The
identifier block itself is emitted exactly once.
-}
module Cardano.Tx.Graph.Rules.Load.Naming (
    -- * Public types
    BnodeName,
    NamingTable,

    -- * Algorithm
    buildNamingTable,
    lookupBnodeName,
    roleSuffix,
) where

import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
 )

import Data.Char (isAsciiUpper)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text

-- | The blank-node local name attached to a @(leafType, bytesHex)@ pair.
type BnodeName = Text

{- | The first-entity-wins resolution table. Maps each
@(leafType, bytesHex)@ to the bnode name produced by its first owning
entity in document order.
-}
type NamingTable = Map (LeafType, Text) BnodeName

{- | Build the first-entity-wins naming table from a list of
'EntityDecl' values in document order. The first entity that
introduces a @(leafType, bytesHex)@ pair owns the bnode name; later
entities referring to the same pair reuse that name.

The bnode name is @\<entitySlug\>_\<roleSuffix leafType\>@ (no
leading @\\_:@ — callers add it when emitting).
-}
buildNamingTable :: [EntityDecl] -> NamingTable
buildNamingTable = foldl insertEntity Map.empty
  where
    insertEntity acc EntityDecl{entitySlug, entityIdentifiers} =
        foldl (insertIdentifier entitySlug) acc entityIdentifiers
    insertIdentifier slug acc EntityIdentifier{entityIdLeafType, entityIdBytesHex} =
        let k = (entityIdLeafType, entityIdBytesHex)
            v = slug <> "_" <> roleSuffix entityIdLeafType
         in Map.insertWith (\_new old -> old) k v acc

{- | Look up the bnode name for an identifier in the table built by
'buildNamingTable'. Returns 'Nothing' if the pair is absent (a
programmer error — callers should always look up identifiers from
the same source they passed to 'buildNamingTable').
-}
lookupBnodeName :: NamingTable -> EntityIdentifier -> Maybe BnodeName
lookupBnodeName table EntityIdentifier{entityIdLeafType, entityIdBytesHex} =
    Map.lookup (entityIdLeafType, entityIdBytesHex) table

{- | Map a 'LeafType' to the role-suffix segment used in the bnode
name. The transform is: only the first character is lowercased; all
other characters are preserved verbatim. The result for each leafType
is pinned by spec FR-013:

* 'PaymentKey'    → @paymentKey@
* 'PaymentScript' → @paymentScript@
* 'StakeKey'      → @stakeKey@
* 'StakeScript'   → @stakeScript@
* 'AssetClass'    → @assetClass@
* 'Policy'        → @policy@
* 'PoolId'        → @poolId@
* 'DRepKey'       → @dRepKey@
* 'DRepScript'    → @dRepScript@
-}
roleSuffix :: LeafType -> Text
roleSuffix = lowerFirst . Text.pack . show
  where
    lowerFirst t = case Text.uncons t of
        Nothing -> t
        Just (c, rest) -> Text.cons (toLowerAscii c) rest
    toLowerAscii c
        | isAsciiUpper c =
            toEnum (fromEnum c + (fromEnum 'a' - fromEnum 'A'))
        | otherwise = c

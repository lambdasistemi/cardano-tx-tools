{- |
Module      : Cardano.Tx.Graph.Rules.Load.Emit.Overlay
Description : Canonical Turtle serializer for the operator-entity overlay.
License     : Apache-2.0

Emits a byte-stable Turtle document containing only the operator-declared
entity overlay (entities + their identifier blank nodes). The byte
shape is pinned by spec FR-012 and FR-013:

* The three Phase A prefix declarations (@cardano:@, @rdfs:@, fixture
  base) in that exact order, then a blank line.
* A header comment block (@# Operator-declared entities (from rules.yaml).@).
* For each entity in source order: a four-line @:slug a cardano:Entity@
  block (label + one @cardano:hasIdentifier _:bnode@ line per
  identifier, two-space indent), then a blank line.
* For each *first-seen* identifier @(leafType, bytesHex)@ pair: a
  three-line @\\_:bnode a cardano:Identifier@ block with @leafType@
  and @bytesHex@ literals, two-space indent. Identifiers shared with
  an earlier entity are NOT re-declared.
* A single trailing newline.

The emitter is total over @['EntityDecl']@ — invalid identifiers
(unknown leafType, etc.) are unreachable here because the YAML
compiler upstream rejects them.
-}
module Cardano.Tx.Graph.Rules.Load.Emit.Overlay (
    emitOverlay,
) where

import Cardano.Tx.Graph.Rules.Load.Naming (
    NamingTable,
    buildNamingTable,
    lookupBnodeName,
 )
import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
 )

import Data.ByteString (ByteString)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

{- | Serialize a list of entity declarations into the canonical
Turtle byte stream the byte-diff golden checks against
@expected.entities.ttl@.

The @fixtureSlug@ argument is the fixture-directory basename and
becomes the local part of the default @:@ prefix's base IRI (e.g.
@02-alice-bob-ada@ → prefix
@\<https://lambdasistemi.github.io/cardano-tx-tools/fixtures/02-alice-bob-ada#\>@).
-}
emitOverlay :: Text -> [EntityDecl] -> ByteString
emitOverlay fixtureSlug entities =
    TextEncoding.encodeUtf8 (renderDocument fixtureSlug entities)

renderDocument :: Text -> [EntityDecl] -> Text
renderDocument fixtureSlug entities =
    let table = buildNamingTable entities
        header = renderHeader fixtureSlug
        (entityBlocks, _) = renderEntities table entities Set.empty
     in header <> entityBlocks

renderHeader :: Text -> Text
renderHeader fixtureSlug =
    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n"
        <> "@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n"
        <> "@prefix :        <https://lambdasistemi.github.io/cardano-tx-tools/fixtures/"
        <> fixtureSlug
        <> "#> .\n"
        <> "\n"
        <> "#\n"
        <> "# Operator-declared entities (from rules.yaml).\n"
        <> "#\n"
        <> "\n"

{- | Render every entity block, accumulating the set of identifier
bnodes that have already been declared so the same blank-node block
is not emitted twice when two entities share an identity.
-}
renderEntities ::
    NamingTable -> [EntityDecl] -> Set Text -> (Text, Set Text)
renderEntities _ [] emitted = ("", emitted)
renderEntities table (entity : rest) emitted =
    let (entityText, emitted') = renderEntity table entity emitted
        (restText, emitted'') = renderEntities table rest emitted'
     in (entityText <> restText, emitted'')

renderEntity ::
    NamingTable -> EntityDecl -> Set Text -> (Text, Set Text)
renderEntity
    table
    EntityDecl{entityName, entitySlug, entityIdentifiers, entityBech32}
    emitted =
        let -- Issue #100: emit @cardano:bech32 "<addr>"@ on the
            -- entity node when the entity was declared via
            -- @from-address:@ (carrying its resolved bech32
            -- string). Skipped for @script:@ / @asset:@ /
            -- @pool:@ / @drep:@ / @keys:@ shapes which have no
            -- single-bech32 representation.
            bechLine = case entityBech32 of
                Just b -> "  cardano:bech32 " <> renderLiteral b <> " ;\n"
                Nothing -> ""
            entityHead =
                ":"
                    <> entitySlug
                    <> " a cardano:Entity ;\n"
                    <> "  rdfs:label "
                    <> renderLiteral entityName
                    <> " ;\n"
                    <> bechLine
            idLines = renderIdentifierLines table entityIdentifiers
            (idBlocksText, emitted') =
                renderEntityIdentifierBlocks table entityIdentifiers emitted
         in ( entityHead <> idLines <> "\n" <> idBlocksText
            , emitted'
            )

{- | Render the @cardano:hasIdentifier _:bnode ;@ continuation lines
attached to an entity's head block. The last line ends with @.@; the
others end with @;@. Two-space indent.
-}
renderIdentifierLines :: NamingTable -> [EntityIdentifier] -> Text
renderIdentifierLines table idents =
    let bnodes = map (resolveBnode table) idents
        terminators = replicate (length bnodes - 1) " ;\n" ++ [" .\n"]
        line bnode term =
            "  cardano:hasIdentifier _:" <> bnode <> term
     in Text.concat (zipWith line bnodes terminators)

{- | Render the per-identifier @\\_:bnode a cardano:Identifier@ block
*only* if the bnode has not been seen before. Threads the seen-set
through the entity's identifier list so subsequent identifiers within
the same entity also skip duplicates (in case the entity itself
declares two pairs that resolve to the same first-seen bnode).
-}
renderEntityIdentifierBlocks ::
    NamingTable ->
    [EntityIdentifier] ->
    Set Text ->
    (Text, Set Text)
renderEntityIdentifierBlocks _ [] emitted = ("", emitted)
renderEntityIdentifierBlocks table (ident : rest) emitted =
    let bnode = resolveBnode table ident
        (thisBlock, emitted') =
            if Set.member bnode emitted
                then ("", emitted)
                else (renderIdentifierBlock bnode ident, Set.insert bnode emitted)
        (restText, emitted'') = renderEntityIdentifierBlocks table rest emitted'
     in (thisBlock <> restText, emitted'')

renderIdentifierBlock :: Text -> EntityIdentifier -> Text
renderIdentifierBlock bnode EntityIdentifier{entityIdLeafType, entityIdBytesHex} =
    "_:"
        <> bnode
        <> " a cardano:Identifier ;\n"
        <> "  cardano:leafType "
        <> renderLiteral (renderLeafType entityIdLeafType)
        <> " ;\n"
        <> "  cardano:bytesHex "
        <> renderLiteral entityIdBytesHex
        <> " .\n"
        <> "\n"

resolveBnode :: NamingTable -> EntityIdentifier -> Text
resolveBnode table ident =
    case lookupBnodeName table ident of
        Just b -> b
        Nothing ->
            -- Unreachable: the naming table is built from the same
            -- identifier list. If this ever fires it indicates a
            -- caller wired the table wrong.
            error
                ( "emitOverlay: identifier missing from naming table "
                    <> show ident
                )

{- | Render a 'Text' value as a Turtle string literal — wrap in double
quotes; the fixtures' names contain no double quotes or backslashes,
so naive wrapping is byte-safe for the current corpus. (A more
permissive escaper lands once a fixture forces it.)
-}
renderLiteral :: Text -> Text
renderLiteral t = "\"" <> t <> "\""

{- | Pin the canonical string form for each 'LeafType' constructor.
This is the literal that appears in @cardano:leafType@ triples and
matches the camelCase tail used by 'roleSuffix' in the naming
algorithm.
-}
renderLeafType :: LeafType -> Text
renderLeafType = \case
    PaymentKey -> "PaymentKey"
    PaymentScript -> "PaymentScript"
    StakeKey -> "StakeKey"
    StakeScript -> "StakeScript"
    AssetClass -> "AssetClass"
    Policy -> "Policy"
    PoolId -> "PoolId"
    DRepKey -> "DRepKey"
    DRepScript -> "DRepScript"
    -- T122c hash leaves are body-walker-only — they don't
    -- appear in the operator-overlay rules path but the pattern
    -- match here stays total so a future overlay extension can
    -- consume them without an exhaustivity warning.
    LtTxId -> "TxId"
    LtDatumHash -> "DatumHash"
    LtScriptHash -> "ScriptHash"
    LtScriptDataHash -> "ScriptDataHash"
    LtAuxiliaryDataHash -> "AuxiliaryDataHash"

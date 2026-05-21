{- |
Module      : Cardano.Tx.Graph.Emit.Serialize.Turtle
Description : Canonical Turtle serializer for the joint emit (private).
License     : Apache-2.0

Private submodule of 'Cardano.Tx.Graph.Emit'. Renders an
'EmittedGraph' value (the typed IR the projection walker
produces) to a byte stream that matches the artisan reference
layout pinned by spec plan D5 / research R4:

* a fixed three-prefix declaration block;
* the operator-entity overlay bytes verbatim (already produced by
  the #48 rules loader);
* a @# Transaction body.@ section header;
* per-input + per-output + address-decomposition subject blocks
  separated by uniform @# Input N@ / @# Output N@ / @# Address
  decompositions — payment + stake credential per leaf.@ headers.

The byte shape is locked by fixture 02's @expected.ttl@ once
the regen ships; T006-T010 keep this serializer GREEN as they
extend the projection walker for new leaves.
-}
module Cardano.Tx.Graph.Emit.Serialize.Turtle (
    renderTurtle,
) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (Builder)
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BSL
import Data.List (intersperse)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

import Cardano.Tx.Graph.Emit.Lookup (BnodeName (..))
import Cardano.Tx.Graph.Emit.Triple (
    BodySection (..),
    Object (..),
    Predicate (..),
    Subject (..),
    SubjectBlock (..),
 )
import Cardano.Tx.Graph.Emit.Vocab (
    cardanoPrefix,
    fixturePrefixBase,
    rdfPrefix,
    rdfsPrefix,
 )

{- | Render the joint Turtle output for a fixture slug + the
emitter's IR.

The structure (research R4):

@
\@prefix cardano: \<…\> .
\@prefix rdfs:    \<…\> .
\@prefix :        \<fixturePrefixBase + slug + \"#\"\> .

<overlay bytes verbatim>

#
# Transaction body.
#

\<_:tx block\>

#
# Input N
#

\<_:input_K block + optional _:resolvedInput_K block\>

#
# Output N
#

\<_:output_K block\>

#
# Address decompositions — payment + stake credential per leaf.
#

\<address blocks…\>
@

The trailing newline is included.
-}
renderTurtle ::
    Text ->
    [(Text, Text)] ->
    ByteString ->
    [BodySection] ->
    ByteString
renderTurtle slug _explicitPrefixes overlayBytes body =
    BSL.toStrict $
        Builder.toLazyByteString $
            mconcat
                [ renderPrefixes slug
                , bsBuilder (stripOverlayPrefixBlock overlayBytes)
                , mconcat (intersperse newline (map renderSection body))
                ]
  where
    bsBuilder = Builder.byteString

{- | Strip the leading @\@prefix …@ block (plus the trailing
blank line) from an overlay byte stream. The loader's overlay
output always starts with the three Phase A prefix declarations;
inlining them under the serializer's own prefix declarations
would duplicate the lines, so we drop the overlay's copy and
keep its body content (the @# Operator-declared entities@
comment + entity subject blocks).

Empty input is passed through unchanged.
-}
stripOverlayPrefixBlock :: ByteString -> ByteString
stripOverlayPrefixBlock bs
    | BS.null bs = bs
    | otherwise =
        let ls = BS8.lines bs
            tail' = dropWhile isPrefixOrEmpty ls
         in BS8.unlines tail'
  where
    isPrefixOrEmpty l =
        BS.null l || "@prefix" `BS.isPrefixOf` l

----------------------------------------------------------------------
-- Prefix declarations
----------------------------------------------------------------------

renderPrefixes :: Text -> Builder
renderPrefixes slug =
    mconcat
        [ prefixLine "cardano:" cardanoPrefix
        , prefixLine "rdf:    " rdfPrefix
        , prefixLine "rdfs:   " rdfsPrefix
        , prefixLine ":       " (fixturePrefixBase <> slug <> "#")
        , newline
        ]
  where
    prefixLine label iri =
        mconcat
            [ text "@prefix "
            , text label
            , text " <"
            , text iri
            , text "> .\n"
            ]

----------------------------------------------------------------------
-- Sections
----------------------------------------------------------------------

renderSection :: BodySection -> Builder
renderSection BodySection{sectionHeader, sectionBlocks} =
    mconcat
        [ sectionHeaderBuilder sectionHeader
        , mconcat (intersperse newline (map renderBlock sectionBlocks))
        ]

sectionHeaderBuilder :: Text -> Builder
sectionHeaderBuilder header =
    mconcat
        [ text "#\n# "
        , text header
        , text "\n#\n\n"
        ]

----------------------------------------------------------------------
-- Subject blocks
----------------------------------------------------------------------

renderBlock :: SubjectBlock -> Builder
renderBlock SubjectBlock{subjectBlockSubject, subjectBlockPredicates} =
    case subjectBlockPredicates of
        [] -> renderSubject subjectBlockSubject <> text ".\n"
        ((p0, o0) : rest) ->
            mconcat
                [ renderSubject subjectBlockSubject
                , text " "
                , renderPredicateObject p0 o0
                , renderRestPredicateObjects rest
                ]

renderRestPredicateObjects :: [(Predicate, Object)] -> Builder
renderRestPredicateObjects = \case
    [] -> text " .\n"
    [(p, o)] ->
        mconcat
            [ text " ;\n  "
            , renderPredicateObject p o
            , text " .\n"
            ]
    ((p, o) : rest) ->
        mconcat
            [ text " ;\n  "
            , renderPredicateObject p o
            , renderRestPredicateObjects rest
            ]

renderPredicateObject :: Predicate -> Object -> Builder
renderPredicateObject p o =
    renderPredicate p <> text " " <> renderObject o

renderSubject :: Subject -> Builder
renderSubject = \case
    SBnode (BnodeName n) -> text "_:" <> text n
    SIri t -> text t

renderPredicate :: Predicate -> Builder
renderPredicate = \case
    PIri t -> text t
    PRdfType -> text "a"

renderObject :: Object -> Builder
renderObject = \case
    OBnode (BnodeName n) -> text "_:" <> text n
    OIri t -> text t
    OStringLit s -> text "\"" <> text s <> text "\""
    OIntLit i -> text (Text.pack (show i))

----------------------------------------------------------------------
-- Builder helpers
----------------------------------------------------------------------

text :: Text -> Builder
text = Builder.byteString . TextEncoding.encodeUtf8

newline :: Builder
newline = text "\n"

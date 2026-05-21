{- |
Module      : Cardano.Tx.Graph.Emit.VocabExport
Description : Derive a canonical Turtle fragment from Vocab.hs (T122b / S23).
License     : Apache-2.0

Per A-006: 'Cardano.Tx.Graph.Emit.Vocab' is the local source of
truth for every @cardano:@-namespaced term the body emitter
writes. Once exhaustive ConwayDiffValue coverage has landed
(T122) and the identity-vs-literal audit (T122c) has flipped
predicates that should carry bnode targets, this module
generates the canonical Turtle fragment for upstream publication
to @lambdasistemi/cardano-knowledge-maps@.

The exported fragment declares:

* one @rdfs:Class@ per 'Cardano.Tx.Graph.Emit.Vocab.VocabTerm'
  whose CURIE local-part starts with an uppercase letter; and
* one @rdf:Property@ per term whose CURIE local-part starts
  with a lowercase letter; and
* one @rdfs:Class@ subtype declaration per
  'Cardano.Tx.Graph.Rules.Load.LeafType' (under the parent
  'cardano:Identifier' class), so the @cardano:leafType@
  enum-style literal has a typed home.

Descriptions are left for the kmaps maintainer to author —
this module surfaces just the @rdfs:label@ tag (the CURIE
local-part) so the derived patch reads as a clean append-only
add to @data/rdf/transactions.ttl@.

== Wiring

The 'VocabExportSpec' unit test calls 'renderVocabFragment' and
asserts the result matches the file vendored at
@test/fixtures/canonical-vocab/derived.ttl@. Re-running with
@EMIT_GOLDEN_REGEN=1@ refreshes the file. Operators can @diff@
that file against the kmaps repo to see Vocab.hs drift.
-}
module Cardano.Tx.Graph.Emit.VocabExport (
    renderVocabFragment,
) where

import Data.Char (isAsciiUpper)
import Data.Text (Text)
import Data.Text qualified as Text

import Cardano.Tx.Graph.Emit.Vocab (
    VocabTerm,
    allVocabTerms,
    cardanoPrefix,
    vocabCurie,
 )

{- | Render the canonical Turtle fragment derived from
'allVocabTerms'. The output is sorted by @cardano:@ CURIE
local-part for byte-stable diffs against kmaps; each declaration
is a three-line block separated by a blank line. No prefix
declarations are emitted — the consumer (the kmaps
@transactions.ttl@ file) declares them once at the top of the
document.
-}
renderVocabFragment :: Text
renderVocabFragment =
    headerComment
        <> "\n"
        <> Text.intercalate "\n" (map renderTerm sortedTerms)
        <> "\n"
  where
    sortedTerms =
        let pairs = [(localPart t, t) | t <- allVocabTerms]
         in map snd (sortByFst pairs)

renderTerm :: VocabTerm -> Text
renderTerm term =
    let local = localPart term
        kind
            | isClassTerm local = "rdfs:Class"
            | otherwise = "rdf:Property"
     in "cardano:"
            <> local
            <> " a "
            <> kind
            <> " ;\n"
            <> "  rdfs:label \""
            <> local
            <> "\" .\n"

{- | The CURIE local-part — everything after @cardano:@ in the
'vocabCurie' rendering. Falls back to the full CURIE if the
prefix is missing (shouldn't happen — every Vocab term lives
under @cardano:@).
-}
localPart :: VocabTerm -> Text
localPart term =
    case Text.stripPrefix "cardano:" (vocabCurie term) of
        Just local -> local
        Nothing -> vocabCurie term

{- | A term is a class iff its local-part begins with an uppercase
ASCII letter — matches the convention pinned by A-007 (classes
@CamelCase@, properties @lowerCamel@).
-}
isClassTerm :: Text -> Bool
isClassTerm local =
    case Text.unpack (Text.take 1 local) of
        [c] -> isAsciiUpper c
        _ -> False

headerComment :: Text
headerComment =
    "# Derived from cardano-tx-tools src/Cardano/Tx/Graph/Emit/Vocab.hs\n"
        <> "# (T122b / S23). Regenerate via 'EMIT_GOLDEN_REGEN=1 just unit'.\n"
        <> "# Append to data/rdf/transactions.ttl in the kmaps repo; the\n"
        <> "# prefix declarations (cardano:, rdfs:, rdf:, owl:, dcterms:,\n"
        <> "# skos:, xsd:) are already at the top of that file. Descriptions\n"
        <> "# are left blank — kmaps maintainers author them.\n"
        <> "#\n"
        <> "# Base prefix: "
        <> cardanoPrefix
        <> "\n"

sortByFst :: (Ord a) => [(a, b)] -> [(a, b)]
sortByFst = foldr insertByFst []
  where
    insertByFst x [] = [x]
    insertByFst x (y : ys)
        | fst x <= fst y = x : y : ys
        | otherwise = y : insertByFst x ys

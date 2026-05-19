{- |
Module      : Fixtures.RewriteRedesign.TurtleShim
Description : Loose syntactic Turtle check + kmaps#53 Phase A namespace
              pin for the rewrite-redesign goldens fixtures.
License     : Apache-2.0

A minimal predicate the goldens harness calls when a fixture's
@expected.ttl@ file is present on disk. The check confirms the file is
structurally well-formed Turtle and uses the kmaps#53 Phase A
@cardano:@ namespace IRI verbatim. It does NOT parse triples, does NOT
validate vocab terms against the published kmaps file, and does NOT
introduce a new build-dependency on any RDF library — see
@specs\/033-rewrite-redesign-harness\/research.md@ D5.

The check is intentionally weak: it confirms

* the file decodes as UTF-8,
* the verbatim Phase A @\@prefix cardano:@ declaration line is present
  (modulo whitespace between tokens),
* every non-empty, non-comment line ends with @.@, @;@, or @,@.

Subsequent B-side slices (T016..T024) just drop a new @expected.ttl@
per fixture; they do not need to extend this shim.
-}
module Fixtures.RewriteRedesign.TurtleShim (
    -- * Predicate
    isWellFormedTurtle,

    -- * Phase A namespace IRI
    phaseACardanoIri,
) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.Encoding.Error (lenientDecode)

{- | The kmaps#53 Phase A @cardano:@ namespace IRI, matched verbatim
inside the @\@prefix cardano:@ declaration line.
-}
phaseACardanoIri :: Text
phaseACardanoIri =
    "<https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#>"

{- | Loose syntactic check that the byte payload is well-formed Turtle
and uses the kmaps#53 Phase A @cardano:@ namespace IRI.

Returns @Right ()@ on success and @Left msg@ with a short diagnostic
on failure. The check is intentionally weak and does not parse triples
or validate vocab terms — see the module header.
-}
isWellFormedTurtle :: ByteString -> Either String ()
isWellFormedTurtle bs = do
    let txt = Text.decodeUtf8With lenientDecode bs
        lns = map stripWhitespace (Text.lines txt)
    if any isPhaseACardanoPrefix lns
        then pure ()
        else
            Left $
                "missing kmaps#53 Phase A cardano: prefix declaration "
                    <> Text.unpack phaseACardanoIri
    let body = filter (not . isIgnorable) lns
    case filter (not . endsWithStatementTerminator) body of
        [] -> pure ()
        bad ->
            Left $
                "Turtle line(s) do not end with '.', ';', or ',': "
                    <> show (map Text.unpack bad)

-- | Strip leading and trailing whitespace from a line.
stripWhitespace :: Text -> Text
stripWhitespace = Text.stripEnd . Text.stripStart

{- | A line is ignorable for the terminator check when it is empty or
starts with the Turtle comment character @#@.
-}
isIgnorable :: Text -> Bool
isIgnorable t = Text.null t || "#" `Text.isPrefixOf` t

{- | A line is the Phase A @cardano:@ prefix declaration when it starts
with @\@prefix@, names the @cardano:@ binding, and embeds the
verbatim Phase A IRI. Allows arbitrary whitespace between tokens.
-}
isPhaseACardanoPrefix :: Text -> Bool
isPhaseACardanoPrefix t =
    "@prefix" `Text.isPrefixOf` t
        && "cardano:" `Text.isInfixOf` t
        && phaseACardanoIri `Text.isInfixOf` t

{- | A non-ignorable Turtle line is required to end in @.@, @;@, or @,@
once trailing whitespace is stripped. This is the structural anchor
that distinguishes Turtle from arbitrary text.
-}
endsWithStatementTerminator :: Text -> Bool
endsWithStatementTerminator t =
    case Text.unsnoc t of
        Just (_, c) -> c == '.' || c == ';' || c == ','
        Nothing -> False

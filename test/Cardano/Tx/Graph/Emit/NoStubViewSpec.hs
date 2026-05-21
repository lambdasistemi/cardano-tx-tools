{- |
Module      : Cardano.Tx.Graph.Emit.NoStubViewSpec
Description : No-stub-triples invariant on every fixture (T109, FR-012).
License     : Apache-2.0

CI gate for spec FR-012 / epic #46 "no-stub SPARQL". The canonical
view lives at @views/no-stub-triples.rq@:

> PREFIX cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#>
> PREFIX rdf:     <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
>
> SELECT ?subj WHERE {
>   ?subj a ?type .
>   FILTER (?type IN (cardano:Input, cardano:Output))
>   FILTER NOT EXISTS {
>     ?subj ?p ?o .
>     FILTER (?p != rdf:type)
>   }
> }

This spec re-implements the same predicate as a line-scanning
structural check over the regenerated @expected.ttl@ of every
fixture under @test/fixtures/rewrite-redesign/@. The view returns
zero rows iff no @cardano:Input@ / @cardano:Output@ subject block
is reduced to only its @rdf:type@ triple.

== Why line-scanning and not a real SPARQL engine

Decision recorded at Q-001 / A-001-sparql-runtime
(see @\/tmp\/epic-046\/tx-70\/subagents\/T109-no-stub-view\/answers\/@).
No SPARQL runtime is on the @cardano-tx-tools@ test classpath; the
view's semantics are a one-line predicate; the Turtle serializer
emits a canonical layout (one statement-start line + indented
continuation lines + a @.@ terminator) so a structural scan
suffices. The @.rq@ file is the contract for downstream RDF
consumers; this spec is the in-repo CI runner. Drift risk is
mitigated by the haddock above quoting the SPARQL verbatim and by
the small (11-file) fixture set.

== Algorithm

The canonical Turtle layout from the in-house serializer (#58
research D5) places each statement-start line at column 0 and each
predicate-object continuation at two-space indent, terminating the
statement with @.@. Within a statement, @rdf:type@ is always
emitted first (as @a@). The block walker therefore:

1. Splits the fixture into statement blocks. A block begins at a
   non-blank, non-comment, non-@\@prefix@, non-indented line and
   continues through every following indented line up to and
   including the first line ending with @.@.
2. For each block, extracts:

       * the subject (first whitespace-separated token of the
         leading line);
       * the predicate list (each predicate is the token before the
         object on the leading line and on every continuation
         line — at most one predicate-object pair per line).

3. Reports the block as a no-stub violation iff:

       * the @rdf:type@ predicate maps to @cardano:Input@ or
         @cardano:Output@;
       * the predicate list has exactly one entry (the @rdf:type@).

Fixture-level RED: any of the 11 fixtures contains at least one
violating block.
-}
module Cardano.Tx.Graph.Emit.NoStubViewSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.FilePath ((</>))

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
 )

-- | All fixtures the body emitter covers (T103-T108 regenerated).
allFixtures :: [String]
allFixtures =
    [ "01-amaru-treasury-swap"
    , "02-alice-bob-ada"
    , "03-multi-asset-transfer"
    , "04-mint-spend-script-overlap"
    , "05-withdrawal-script-stake"
    , "06-stake-pool-delegation"
    , "07-vote-delegation"
    , "08-contingency-disburse"
    , "09-mpfs-facts-request"
    , "10-governance-treasury-withdrawal"
    , "11-amaru-treasury-swap-real"
    ]

spec :: Spec
spec =
    describe
        "Cardano.Tx.Graph.Emit no-stub-triples view (T109, FR-012)"
        $ do
            mapM_ fixtureCase allFixtures
            selfCheck

{- | Self-check: feed the predicate a synthetic two-block buffer
where one block is a known stub and one block is well-formed,
asserting the stub-only block is reported. Guards against a
silently-vacuous predicate (e.g. if 'statementBlocks' or
'predicateOf' regress and stop emitting any blocks).
-}
selfCheck :: Spec
selfCheck =
    it "predicate catches a synthetic stub Input subject" $ do
        let buf =
                TextEncoding.encodeUtf8
                    . Text.unlines
                    $ [ "_:stubInput a cardano:Input ."
                      , ""
                      , "_:goodInput a cardano:Input ;"
                      , "  cardano:fromTxOutRef \"abc#0\" ."
                      ]
        case noStubViolations buf of
            ["_:stubInput"] -> pure ()
            other ->
                expectationFailure $
                    "expected exactly [\"_:stubInput\"], got: "
                        <> show other

{- | One Hspec @it@ per fixture: read the on-disk @expected.ttl@,
extract every statement block, assert no block is a no-stub
violation.
-}
fixtureCase :: String -> Spec
fixtureCase slug = do
    let path = "test/fixtures/rewrite-redesign" </> slug </> "expected.ttl"
    bytes <- runIO (BS.readFile path)
    it (slug <> " — no Input/Output subject has only rdf:type") $ do
        let violations = noStubViolations bytes
        if null violations
            then pure ()
            else
                expectationFailure $
                    "no-stub-triples view returned rows on "
                        <> path
                        <> ": "
                        <> show violations

----------------------------------------------------------------------
-- View predicate (Haskell implementation of views/no-stub-triples.rq)
----------------------------------------------------------------------

{- | Run the no-stub-triples view against a Turtle byte stream and
return the list of offending subjects (the @?subj@ projection of
the canonical SPARQL query, expressed as the raw subject token —
e.g. @"_:input1"@).
-}
noStubViolations :: ByteString -> [Text]
noStubViolations =
    mapMaybe blockViolation
        . statementBlocks
        . Text.lines
        . TextEncoding.decodeUtf8

{- | Pair of (subject, ordered predicate list) for one Turtle
statement block. Predicates are kept in source order; @"a"@ is the
canonical Turtle shorthand for @rdf:type@.
-}
data Block = Block
    { blockSubject :: !Text
    , blockPredicates :: ![Text]
    }
    deriving stock (Eq, Show)

{- | Apply the view predicate to a single block.

A block is a violation iff:

* it has exactly one predicate (the type triple);
* that predicate is the @"a"@ shorthand;
* its object is @cardano:Input@ or @cardano:Output@.

Returns the subject token when the block matches the view, otherwise
@Nothing@. The object is recovered by inspecting the original
leading line — but for the small canonical fixture set, knowing
"this block has only one predicate-object pair AND its predicate
is @a@" already implies the leading line is @<subj> a <obj> .@,
so the helper carries the leading-line object through directly
via the 'Block' shape extracted by 'statementBlocks'.
-}
blockViolation :: (Block, Text) -> Maybe Text
blockViolation (Block{blockSubject, blockPredicates}, typeObject) =
    case blockPredicates of
        ["a"]
            | typeObject == "cardano:Input"
                || typeObject == "cardano:Output" ->
                Just blockSubject
        _ -> Nothing

----------------------------------------------------------------------
-- Turtle statement-block extractor
----------------------------------------------------------------------

{- | Group input lines into Turtle statement blocks.

A block begins at a line that:

* is non-empty after trimming whitespace,
* does NOT start with @#@ (comment / section banner),
* does NOT start with @\@prefix@ or @\@base@ (directive),
* does NOT start with whitespace (continuations are indented two
  spaces in the canonical serializer layout).

A block continues through every following line that DOES start with
whitespace, and ends at the first line whose stripped trailing
non-whitespace character is @.@ (the Turtle statement terminator).
Lines that fail to satisfy any of the above are skipped between
blocks.

The leading line's third whitespace-separated token (the object of
the type-triple, since 'rdf:type' is always emitted first) is
returned alongside the block so 'blockViolation' can read it
without re-parsing.
-}
statementBlocks :: [Text] -> [(Block, Text)]
statementBlocks = go
  where
    go [] = []
    go (line : rest)
        | isStatementStart line =
            let (continuations, after) = collectUntilTerminator line rest
                allLines = line : continuations
                subj = subjectOf line
                preds = mapMaybe predicateOf allLines
                typeObj = typeObjectOf line
             in (Block subj preds, typeObj) : go after
        | otherwise = go rest

    isStatementStart t =
        let trimmed = Text.strip t
         in not (Text.null trimmed)
                && not (Text.isPrefixOf "#" trimmed)
                && not (Text.isPrefixOf "@prefix" trimmed)
                && not (Text.isPrefixOf "@base" trimmed)
                && not (Text.isPrefixOf " " t)
                && not (Text.isPrefixOf "\t" t)

    {- Walk the tail collecting continuation lines until the block
    terminates. The leading statement-start line is given as the
    first argument so a single-statement block (one whose leading
    line is itself the @.@-terminator) returns no continuations and
    consumes nothing from the tail.

    Returns (continuationLines, remainingLines). The terminator
    line is INCLUDED in the continuationLines list (when it's a
    real continuation) so its predicate counts toward the block's
    predicate list.
    -}
    collectUntilTerminator :: Text -> [Text] -> ([Text], [Text])
    collectUntilTerminator leading rest
        | endsWithPeriod leading = ([], rest)
        | otherwise = breakAtTerminator rest

    breakAtTerminator :: [Text] -> ([Text], [Text])
    breakAtTerminator [] = ([], [])
    breakAtTerminator (l : ls)
        | endsWithPeriod l = ([l], ls)
        | otherwise =
            let (cs, rs) = breakAtTerminator ls
             in (l : cs, rs)

    endsWithPeriod t =
        case Text.unsnoc (Text.stripEnd t) of
            Just (_, '.') -> True
            _ -> False

----------------------------------------------------------------------
-- Token extraction
----------------------------------------------------------------------

{- | Subject of a leading statement-block line: the first
whitespace-separated token.
-}
subjectOf :: Text -> Text
subjectOf = firstWord

{- | Object of the type-triple on the leading line. In the canonical
serializer layout, the leading line has the form @<subj> <pred>
<obj> [;|.]@ and the first predicate is always the @rdf:type@
shorthand @"a"@. Therefore the third whitespace-separated token is
the type's object (stripped of any trailing @;@ or @.@).
-}
typeObjectOf :: Text -> Text
typeObjectOf line =
    case Text.words line of
        (_subj : _pred : obj : _) -> stripTrailingPunct obj
        _ -> Text.empty

{- | Predicate of a line: the first non-subject token of a
predicate-object pair. On a leading statement-start line that's
the second whitespace-separated token (after the subject); on a
continuation line it's the first non-blank token.

Returns @Nothing@ for lines that do not carry a predicate (blank
lines, the rare unforeseen layout). For canonical-serializer
output, every block line carries exactly one predicate-object
pair, so the @Nothing@ branch is defensive.
-}
predicateOf :: Text -> Maybe Text
predicateOf line
    | Text.null trimmed = Nothing
    | isLeading =
        case Text.words line of
            (_subj : pred_ : _) -> Just (stripTrailingPunct pred_)
            _ -> Nothing
    | otherwise =
        case Text.words trimmed of
            (pred_ : _) -> Just (stripTrailingPunct pred_)
            _ -> Nothing
  where
    trimmed = Text.strip line
    isLeading =
        not (Text.isPrefixOf " " line || Text.isPrefixOf "\t" line)

-- | First whitespace-separated token of a line (empty if none).
firstWord :: Text -> Text
firstWord = Text.takeWhile (not . isWhiteChar) . Text.dropWhile isWhiteChar
  where
    isWhiteChar c = c == ' ' || c == '\t'

{- | Strip a single trailing @;@ or @.@ from a token. Tokens in the
canonical Turtle serializer never carry both; the punctuation is
separated by a space from preceding content but may follow an
object directly in some emitter lines (defensive).
-}
stripTrailingPunct :: Text -> Text
stripTrailingPunct t =
    case Text.unsnoc t of
        Just (rest, c) | c == ';' || c == '.' -> rest
        _ -> t

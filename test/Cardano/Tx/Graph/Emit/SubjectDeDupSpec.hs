{- |
Module      : Cardano.Tx.Graph.Emit.SubjectDeDupSpec
Description : Subject-uniqueness invariant on the joint Turtle output (T102).
License     : Apache-2.0

Spec invariant US2: no two distinct subject blocks in the emitter's
Turtle output share the same subject node. The body walker's
'introduce' helper (T102, in 'Cardano.Tx.Graph.Emit.Monad') is the
mechanism that enforces this for subjects that may be reached more
than once during the walk — shared addresses (fixture 01), shared
asset classes (fixture 03), or the real-on-chain dup-rich layout
(fixture 11).

This spec parses the joint Turtle output, extracts every subject
node that opens a triple-block (the token preceding the first
predicate-object pair), and asserts the multiset has no duplicates.

The parser is intentionally minimal — it does NOT validate Turtle
syntax; it only walks lines, picks out the leading subject token of
each statement (non-blank, non-comment, non-prefix lines that don't
start with whitespace), and accumulates the set. That's enough to
catch a duplicate subject; deeper Turtle-shape regressions are
caught by 'Cardano.Tx.Graph.EmitGoldenSpec'.

T102 enables this for fixtures 01 + 03 + 11; future slices may add
fixtures with newly-shared subjects (e.g. shared DReps in T103+).
-}
module Cardano.Tx.Graph.Emit.SubjectDeDupSpec (spec) where

import Data.ByteString (ByteString)
import Data.List (group, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.FilePath ((</>))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    EmittedGraph (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl,
    RulesLoadResult (..),
    loadRulesFile,
    rulesEntities,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.S01_AmaruTreasurySwap qualified as S01
import Fixtures.RewriteRedesign.S03_MultiAssetTransfer qualified as S03
import Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal qualified as S11

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
 )

spec :: Spec
spec =
    describe
        "Cardano.Tx.Graph.Emit subject-uniqueness invariant (T102, US2)"
        $ do
            mkCase "01-amaru-treasury-swap" S01.tx
            mkCase "03-multi-asset-transfer" S03.tx
            mkCase "11-amaru-treasury-swap-real" S11.tx

{- | Single fixture case: emit + serialize the joint Turtle, parse
subjects out of it, assert no duplicates.
-}
mkCase :: FilePath -> ConwayTx -> Spec
mkCase slug tx = do
    let dir = "test/fixtures/rewrite-redesign" </> slug
        rulesPath = dir </> "rules.yaml"
    (entities, overlay) <- runIO (loadEntitiesAndOverlay rulesPath)
    it (slug <> " — every subject appears at most once") $ do
        case emit tx emptyUtxo entities of
            Left err ->
                expectationFailure $
                    "emit returned Left: " <> show err
            Right g ->
                let joint = g{graphOverlayTurtle = overlay}
                    bytes = serialize Turtle slug joint
                    subjs = bodySubjects bytes
                    duplicates = duplicatesOf subjs
                 in if null duplicates
                        then pure ()
                        else
                            expectationFailure $
                                "duplicate subject(s) in "
                                    <> slug
                                    <> ": "
                                    <> show duplicates

----------------------------------------------------------------------
-- Subject extraction
----------------------------------------------------------------------

{- | Extract the leading subject token of every body statement.

A body statement is a line that:

* is non-empty after stripping the trailing newline,
* does NOT begin with whitespace (continuation lines start with two
  spaces in the Turtle serializer's layout),
* does NOT begin with @#@ (comment / section header),
* does NOT begin with @\@prefix@ (prefix declaration).

The subject token is the first whitespace-separated word on such a
line — either a bnode reference (@_:name@) or a CURIE (@:name@ or
@cardano:Foo@). The output preserves order of occurrence.

This excludes the @rdfs:label@ literals and the @cardano:bytesHex@
lines etc. — those are predicate-object lines that start with two
spaces.
-}
bodySubjects :: ByteString -> [Text]
bodySubjects bs =
    [ leadToken line
    | line <- Text.lines (TextEncoding.decodeUtf8 bs)
    , isStatementStart line
    ]
  where
    leadToken = Text.takeWhile (/= ' ') . Text.dropWhile (== ' ')

    isStatementStart line =
        not (Text.null line)
            && not (Text.isPrefixOf " " line)
            && not (Text.isPrefixOf "#" line)
            && not (Text.isPrefixOf "@prefix" line)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- | Empty resolved-UTxO map.
emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

-- | Find the elements of a list that appear more than once.
duplicatesOf :: (Ord a) => [a] -> [a]
duplicatesOf xs =
    [ x
    | g <- group (sort xs)
    , length g > 1
    , x : _ <- [g]
    ]

{- | Load entities + overlay bytes from a rules.yaml path. Mirrors
'Cardano.Tx.Graph.EmitGoldenSpec.loadEntitiesAndOverlay'; the two
specs deliberately do not share helpers because the fixture
harness is intentionally minimal.
-}
loadEntitiesAndOverlay ::
    FilePath -> IO ([EntityDecl], ByteString)
loadEntitiesAndOverlay path = do
    result <- loadRulesFile path
    case result of
        Right res@RulesLoadResult{rulesOverlayTurtle} ->
            pure (rulesEntities res, rulesOverlayTurtle)
        Left err ->
            fail $
                "SubjectDeDupSpec.loadEntitiesAndOverlay: "
                    <> path
                    <> ": "
                    <> show err

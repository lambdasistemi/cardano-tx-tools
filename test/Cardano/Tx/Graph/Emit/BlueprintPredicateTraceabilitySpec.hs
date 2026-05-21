{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Tx.Graph.Emit.BlueprintPredicateTraceabilitySpec
Description : Cross-fixture traceability for blueprint-derived
              predicates (T104 / S4, FR-010 / SC-006).
License     : Apache-2.0

T104 / S4 of feature 050 (blueprint-decode typed triples). The existing
@VocabTraceabilitySpec@ strict check is scoped to @cardano:@-namespace
CURIEs only (FR-010); the operator-owned predicates emitted by the
typed walker (@':\<ctor\>_\<field\>'@) are checked here.

Pinned invariant, swept across every fixture in the rewrite-redesign
golden suite (the 11 pre-#50 fixtures + fixture 12 from T103 +
fixture 13 from this slice): __every blueprint-derived predicate
emitted in the fixture's Turtle has a matching @(constructor, field)@
declaration in that fixture's loaded blueprint index__ (FR-010 /
SC-006).

Per fixture, the spec runs 'emit' + 'serialize' against the
@rulesEntities@ + @rulesBlueprints@ from the on-disk @rules.yaml@,
extracts the set of @':\<X\>_\<Y\>'@ predicate IRIs from the emitted
Turtle, computes the declared-name set by walking @rulesBlueprints@
with the walker's title-resolution rules (top-constructor
@schemaTitle@ → @validatorTitle@ → @"_0"@; nested-constructor
hardcoded @"_0"@ — see
'Cardano.Tx.Graph.Emit.Project.openValueAsObject'), and asserts the
emitted set is a subset of the declared set. The 'EmittedGraph' is
serialized __without__ the entity overlay so the scan only sees
walker-minted IRIs — the overlay's default-namespace subjects
(@':amaru_swap_v2'@ and similar) would otherwise contaminate the
emitted set with names that are intentionally not declared in
@rulesBlueprints@.

For fixtures whose @rules.yaml@ declares no @blueprints:@ section the
declared set is empty; the emitted set must then also be empty. This
is the operational form of SC-003 (no typed predicates leak into the
no-blueprint path) and FR-018 (back-compat byte-stability on the
pre-#50 fixtures).

The spec.md FR-010 wording is __set-equality__; the load-bearing
direction (and the one SC-006 articulates) is __subset__: emitted ⊆
declared. The reverse containment cannot hold in general — a
blueprint with an @anyOf@ schema declares both branches' fields, but
the walker only mints predicates along the actually decoded branch.
The subset direction is what catches a stray @':\<X\>_\<Y\>'@
predicate; that is the property T105 (decode-failure path) will
continue to lean on.

Pre-T104 this spec fails to compile because
'Fixtures.RewriteRedesign.S13BlueprintPassthrough' does not yet exist;
that compile failure is the load-bearing RED.
-}
module Cardano.Tx.Graph.Emit.BlueprintPredicateTraceabilitySpec (spec) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Char (isAlpha, isAlphaNum)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))

import Cardano.Ledger.Hashes (ScriptHash)

import Cardano.Tx.Blueprint (
    Blueprint,
    BlueprintArgument (..),
    BlueprintSchema (..),
    BlueprintSchemaKind (..),
    BlueprintValidator (..),
    blueprintValidators,
    resolveBlueprintSchema,
 )
import Cardano.Tx.Graph.Emit (
    EmitFormat (Turtle),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl,
    loadRulesFile,
    rulesBlueprints,
    rulesEntities,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.Helpers (stubTxIn, stubTxOutMA)
import Fixtures.RewriteRedesign.S01_AmaruTreasurySwap qualified as S01
import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02
import Fixtures.RewriteRedesign.S03_MultiAssetTransfer qualified as S03
import Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap qualified as S04
import Fixtures.RewriteRedesign.S05_WithdrawalScriptStake qualified as S05
import Fixtures.RewriteRedesign.S06_StakePoolDelegation qualified as S06
import Fixtures.RewriteRedesign.S07_VoteDelegation qualified as S07
import Fixtures.RewriteRedesign.S08_ContingencyDisburse qualified as S08
import Fixtures.RewriteRedesign.S09_MpfsFactsRequest qualified as S09
import Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal qualified as S10
import Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal qualified as S11
import Fixtures.RewriteRedesign.S12BlueprintTyped qualified as S12
import Fixtures.RewriteRedesign.S13BlueprintPassthrough qualified as S13

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
 )

-- ---------------------------------------------------------------------------
-- Top-level spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
    describe
        "Cardano.Tx.Graph.Emit blueprint-predicate traceability \
        \(T104 / S4, FR-010 / SC-006)"
        $ mapM_ traceabilityFixture allFixtures

-- ---------------------------------------------------------------------------
-- Fixture enumeration
-- ---------------------------------------------------------------------------

{- | Every rewrite-redesign fixture covered by the cross-fixture
traceability sweep. The slug + 'ConwayTx' columns mirror
'Cardano.Tx.Graph.EmitGoldenSpec.allFixtures' (the wider byte-diff
coverage); duplicated locally so the FR-010 / SC-006 assertion reads
at the seam without depending on EmitGoldenSpec's enumeration being
exported.
-}
allFixtures :: [(String, ConwayTx)]
allFixtures =
    [ ("01-amaru-treasury-swap", S01.tx)
    , ("02-alice-bob-ada", S02.tx)
    , ("03-multi-asset-transfer", S03.tx)
    , ("04-mint-spend-script-overlap", S04.tx)
    , ("05-withdrawal-script-stake", S05.tx)
    , ("06-stake-pool-delegation", S06.tx)
    , ("07-vote-delegation", S07.tx)
    , ("08-contingency-disburse", S08.tx)
    , ("09-mpfs-facts-request", S09.tx)
    , ("10-governance-treasury-withdrawal", S10.tx)
    , ("11-amaru-treasury-swap-real", S11.tx)
    , ("12-blueprint-typed", S12.tx)
    , ("13-blueprint-passthrough", S13.tx)
    ]

{- | Per-fixture 'it' block: load rules, run 'emit', scan the
serialized Turtle for ':\<X\>_\<Y\>' predicates, walk the loaded
blueprint index, assert the emitted set is a subset of the declared
set.
-}
traceabilityFixture :: (String, ConwayTx) -> Spec
traceabilityFixture (slug, tx) = do
    let rulesPath =
            "test/fixtures/rewrite-redesign" </> slug </> "rules.yaml"
    (entities, blueprints) <- runIO (loadRules rulesPath)
    it
        ( slug
            <> " — every :<X>_<Y> predicate traces to a blueprint declaration"
        )
        $ case emit tx (fixtureUtxo slug) entities blueprints of
            Left err ->
                expectationFailure $ "emit returned Left " <> show err
            Right g ->
                let bytes = serialize Turtle slug g
                    emitted = extractEmittedPredicates bytes
                    declared = declaredPredicatesForBlueprints blueprints
                    stray = emitted `Set.difference` declared
                 in unless (Set.null stray) $
                        expectationFailure $
                            "stray blueprint-derived predicate(s) emitted by "
                                <> slug
                                <> " not declared in rulesBlueprints:\n"
                                <> "  stray    = "
                                <> show (Set.toAscList stray)
                                <> "\n"
                                <> "  emitted  = "
                                <> show (Set.toAscList emitted)
                                <> "\n"
                                <> "  declared = "
                                <> show (Set.toAscList declared)

-- ---------------------------------------------------------------------------
-- Per-fixture UTxO + rules loader (mirrors EmitGoldenSpec)
-- ---------------------------------------------------------------------------

{- | Per-fixture resolved-UTxO. Mirrors
'Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo' — fixture 11 is the
only fixture that ships a resolved input (the multi-asset treasury
input); every other fixture uses the empty map. Fixture 13's body
shape (T104 driver's domain) determines whether it needs a resolved
input — the current default keeps it empty; if the driver lands a
shape requiring resolution, this branch updates in lockstep.
-}
fixtureUtxo :: String -> ResolvedUTxO
fixtureUtxo = \case
    "11-amaru-treasury-swap-real" ->
        Map.singleton
            (stubTxIn 2)
            ( stubTxOutMA
                1_137_000_000_000
                [(S11.swapUsdmPolicy, S11.swapUsdmName, 2_500_000_000)]
            )
    _ -> Map.empty

{- | Load rules.yaml; surface load errors as a fatal IO failure so
the per-fixture 'it' block sees a populated entity + blueprint
list.
-}
loadRules ::
    FilePath -> IO ([EntityDecl], [(ScriptHash, Blueprint, Text)])
loadRules path = do
    res <- loadRulesFile path
    case res of
        Right r -> pure (rulesEntities r, rulesBlueprints r)
        Left err ->
            fail $
                "BlueprintPredicateTraceabilitySpec.loadRules: "
                    <> path
                    <> ": "
                    <> show err

-- ---------------------------------------------------------------------------
-- Turtle scanning: ':<X>_<Y>' predicate IRIs the walker minted.
-- ---------------------------------------------------------------------------

{- | Extract the set of default-namespace CURIE local names from the
emitted Turtle that contain at least one underscore — i.e. names
shaped @\<ctor\>_\<field\>@ minted by
'Cardano.Tx.Graph.Emit.Blueprint.blueprintFieldPredicate'. Skips
@\@prefix …@ declaration lines, comment lines, blank-node
references (@_:foo@), and any tokens inside double-quoted string
literals. Names are returned without the leading colon.
-}
extractEmittedPredicates :: ByteString -> Set Text
extractEmittedPredicates bs =
    Set.fromList
        [ Text.pack name
        | bsLine <- BS8.lines bs
        , let line = BS8.unpack bsLine
        , not ("@prefix" `isPrefix` line)
        , not ("#" `isPrefix` line)
        , name <- scanDefaultPrefixLocals line
        , '_' `elem` name
        ]
  where
    isPrefix p s = take (length p) s == p

{- | Walk a single line of Turtle content and yield the local name of
each default-prefix CURIE (@:local@) it contains. Mirrors the
string-aware tokenizer in
'Cardano.Tx.Graph.Emit.VocabTraceabilitySpec.scanCuries', restricted
to the default-prefix arm and returning the local name instead of
the (empty) prefix.
-}
scanDefaultPrefixLocals :: String -> [String]
scanDefaultPrefixLocals = go False
  where
    go _ [] = []
    -- toggle inString on every quote (escapes are not used in the
    -- walker's literals, so a flat toggle is sufficient).
    go inString ('"' : rest) = go (not inString) rest
    go True (_ : rest) = go True rest
    -- blank-node reference: skip the "_:NAME"
    go False ('_' : ':' : rest) = go False (dropName rest)
    -- default-prefix CURIE: ":local" not preceded by a name char
    go False (':' : rest)
        | startsLocal rest =
            let (name, after) = spanIdent rest
             in name : go False after
        | otherwise = go False rest
    -- named-prefix CURIE: skip "name:local"
    go False (c : rest)
        | isAlpha c || c == '_' =
            let (_, after) = spanIdent (c : rest)
             in case after of
                    (':' : after')
                        | startsLocal after' ->
                            go False (dropName after')
                    _ -> go False after
        | otherwise = go False rest

    spanIdent =
        span (\c -> isAlphaNum c || c == '_' || c == '-')

    startsLocal [] = False
    startsLocal (c : _) = isAlphaNum c || c == '_'

    dropName =
        dropWhile (\c -> isAlphaNum c || c == '_' || c == '-')

-- ---------------------------------------------------------------------------
-- Declared-set walk over the blueprint index.
-- ---------------------------------------------------------------------------

{- | Set of declared predicate names — rendered as
@\<ctor\>_\<field\>@ — across every blueprint in the loaded index.
Each blueprint contributes the union of its validators' datum and
redeemer argument walks, following the walker's title-resolution
rules (see 'Cardano.Tx.Graph.Emit.Project.topConstructorTitle' and
'Cardano.Tx.Graph.Emit.Project.openValueAsObject'):

* Top-level constructor title — the resolved argument schema's
  @schemaTitle@; on miss, the matched validator's @validatorTitle@;
  on second miss, @"_0"@.
* Nested constructor / @anyOf@ branch title — hardcoded @"_0"@.
* Field title — the field schema's @schemaTitle@; on miss, the
  FR-008 @"field\<n\>"@ fallback (zero-indexed).
-}
declaredPredicatesForBlueprints ::
    [(ScriptHash, Blueprint, Text)] -> Set Text
declaredPredicatesForBlueprints =
    Set.unions . map (\(_, bp, _) -> declaredForBlueprint bp)

{- | Union of all @\<ctor\>_\<field\>@ predicate names reachable from
this blueprint's validators.
-}
declaredForBlueprint :: Blueprint -> Set Text
declaredForBlueprint blueprint =
    Set.unions
        [ argumentDeclared blueprint validator argument
        | validator <- blueprintValidators blueprint
        , argument <-
            foldMap pure (validatorDatum validator)
                <> foldMap pure (validatorRedeemer validator)
        ]

{- | Resolve the validator argument's schema, derive the top
constructor title, and walk from there.
-}
argumentDeclared ::
    Blueprint ->
    BlueprintValidator ->
    BlueprintArgument ->
    Set Text
argumentDeclared blueprint validator argument =
    let resolved =
            case resolveBlueprintSchema blueprint (argumentSchema argument) of
                Right s -> s
                Left _ -> argumentSchema argument
        topTitle =
            fromMaybe
                (fromMaybe "_0" (validatorTitle validator))
                (schemaTitle resolved)
     in walkSchema blueprint topTitle resolved

{- | Walk a schema node, yielding the set of declared
@\<ctor\>_\<field\>@ names. The first argument is the constructor
title to use when this node is itself a constructor whose fields
are emitted; nested constructors / anyOf branches recurse with
@"_0"@ to match the walker's hardcoded fallback.
-}
walkSchema :: Blueprint -> Text -> BlueprintSchema -> Set Text
walkSchema blueprint ctorTitle schema =
    case schemaKind schema of
        SchemaConstructor _ fields ->
            Set.unions
                ( zipWith
                    (fieldDeclared blueprint ctorTitle)
                    [0 ..]
                    fields
                )
        SchemaAnyOf alternatives ->
            -- Each alternative is treated as its own (nested)
            -- constructor; the walker assigns "_0" to every nested
            -- constructor regardless of the branch's declared title.
            Set.unions (map (resolveAndWalk blueprint "_0") alternatives)
        SchemaList items ->
            -- List positions are not blueprint-predicate sites in
            -- the current walker (OpenArray emits an opaque OBnode).
            -- Recurse anyway so a future walker extension that grows
            -- list-element predicates is caught by the same
            -- invariant.
            Set.unions (map (resolveAndWalk blueprint "_0") items)
        SchemaListOf item ->
            resolveAndWalk blueprint "_0" item
        SchemaReference _ ->
            -- A bare reference at this point is only reachable when
            -- 'resolveBlueprintSchema' failed upstream; treat it as
            -- a terminal node contributing nothing.
            Set.empty
        SchemaInteger -> Set.empty
        SchemaBytes -> Set.empty
        SchemaData -> Set.empty

{- | Resolve a sub-schema and recurse with the supplied constructor
title (always @"_0"@ for nested positions).
-}
resolveAndWalk :: Blueprint -> Text -> BlueprintSchema -> Set Text
resolveAndWalk blueprint ctorTitle schema =
    case resolveBlueprintSchema blueprint schema of
        Right resolved -> walkSchema blueprint ctorTitle resolved
        Left _ -> walkSchema blueprint ctorTitle schema

{- | Contribution of a single field within a constructor: the
@\<ctorTitle\>_\<fieldTitle\>@ pair plus any nested predicates
reached through the field's schema.
-}
fieldDeclared ::
    Blueprint -> Text -> Int -> BlueprintSchema -> Set Text
fieldDeclared blueprint ctorTitle position fieldSchema =
    let fieldName =
            fromMaybe
                (Text.pack ("field" <> show position))
                (schemaTitle fieldSchema)
        directPredicate = ctorTitle <> "_" <> fieldName
     in Set.insert
            directPredicate
            (resolveAndWalk blueprint "_0" fieldSchema)

{- |
Module      : Cardano.Tx.Graph.Rules.Load
Description : Operator-authored rules-graph loader (Turtle + YAML sugar).
License     : Apache-2.0

Loads operator-authored rule files describing the entity overlay that the
graph emitter (#58) and downstream waves (reasoner #49, blueprint #50,
views #51) compose against. Two input formats are accepted:

* Canonical Turtle (@.ttl@) using the kmaps Phase A @cardano:@ namespace.
* YAML sugar (@.yaml@/@.yml@) extending the 044 grammar with
  @entities:@, @blueprints:@, @collapse:@ at the top level and a new
  @imports:@ key for composition.

Both formats compose via @owl:imports@ / @imports:@; cycles are detected.

See @specs\/048-rules-loader\/@ for the full specification.

This module exposes the public type surface, the high-level
'loadRulesFile' entrypoint, the YAML compiler's in-memory
'parseRulesYamlText' helper (T002), and the structural Turtle
parser's in-memory 'parseRulesTurtleText' helper (T006). The
cross-file imports resolver lands in a later slice.
-}
module Cardano.Tx.Graph.Rules.Load (
    -- * Public API
    loadRulesFile,
    parseRulesYamlText,
    parseRulesTurtleText,

    -- * Result + warnings
    RulesLoadResult (..),
    RulesLoadWarning (..),

    -- * Parsed entities
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    Attestation (..),

    -- * Errors
    RulesLoadError (..),

    -- * Diagnostic rendering (CLI surface)
    renderRulesLoadError,
    renderRulesLoadWarning,
) where

import Cardano.Tx.Blueprint (Blueprint)
import Cardano.Tx.Graph.Rules.Load.Emit.Overlay (emitOverlay)
import Cardano.Tx.Graph.Rules.Load.Parse.Turtle (parseRulesTurtleText)
import Cardano.Tx.Graph.Rules.Load.Parse.Yaml (parseRulesYamlText)
import Cardano.Tx.Graph.Rules.Load.Resolve.Imports (
    dedupAcrossFiles,
    dedupBlueprints,
    resolveImports,
 )
import Cardano.Tx.Graph.Rules.Load.Types (
    Attestation (..),
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
    RulesLoadWarning (..),
 )

import Cardano.Ledger.Hashes (ScriptHash)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath (takeBaseName, takeDirectory, takeExtension)

{- | Successful loader result. Carries the in-memory triple set, the
serialized operator-entity overlay (canonical Turtle bytes), the
deduped in-memory entity list, and any non-fatal warnings accumulated
during the load.

The 'rulesEntities' field exposes the same @['EntityDecl']@ value the
loader feeds into the overlay serializer ('emitOverlay'), so a
downstream consumer (e.g. the body emitter introduced by #58 / spec
FR-010) can build a credential lookup table directly from typed
entity declarations without re-parsing the @rulesOverlayTurtle@
bytes.
-}
data RulesLoadResult = RulesLoadResult
    { rulesOverlayTurtle :: !ByteString
    -- ^ The canonical Turtle byte stream the byte-diff golden checks
    -- against @expected.entities.ttl@.
    , rulesWarnings :: ![RulesLoadWarning]
    -- ^ Non-fatal warnings (e.g. cross-file duplicate entity URIs,
    -- first-wins blueprint registrations).
    , rulesEntities :: ![EntityDecl]
    -- ^ Deduped operator-declared entities in source order across the
    -- imports closure, the same list serialized into
    -- 'rulesOverlayTurtle'. Downstream consumers (body emitter #58)
    -- use this typed view to build credential → entity lookups
    -- without re-parsing the overlay Turtle.
    , rulesBlueprints :: ![(ScriptHash, Blueprint, Text)]
    -- ^ The loaded blueprint index, in source order across the imports
    -- closure, post-first-wins-dedup on 'ScriptHash' collisions. Each
    -- entry pairs the script hash that registers the blueprint with
    -- the parsed CIP-57 'Blueprint' value and the blueprint's
    -- preamble title (kept for diagnostic messages and predicate
    -- naming downstream, per spec FR-001 / FR-008). The blueprint
    -- emitter (#50 T101+) consults this list when an output's
    -- payment-credential script hash matches a registered blueprint.
    , rulesAttestations :: ![Attestation]
    -- ^ Off-chain attestations declared under the @attestations:@
    -- top-level block (issue #105). Each entry pins an
    -- IPFS-anchored artefact to an operator-named entity by slug.
    -- The overlay emitter renders one @cardano:Attestation@ block
    -- per entry.
    }
    deriving stock (Eq, Show)

{- | Load a rules file by path.

The file extension dispatches the parser:

* @.ttl@ — canonical Turtle (T006).
* @.yaml@, @.yml@ — YAML sugar (T002 onwards; the YAML compiler is
  available in-memory via 'parseRulesYamlText'; the file-loading and
  serializer plumbing lands with T003+).

Any other extension returns 'UnsupportedExtension'.

Both parsers feed the same in-memory @['EntityDecl']@ shape into the
shared serializer, so authoring the same rules content as YAML or as
Turtle produces byte-equal overlay output (the co-equality
requirement, spec SC-005).
-}
loadRulesFile :: FilePath -> IO (Either RulesLoadError RulesLoadResult)
loadRulesFile path = case takeExtension path of
    ".ttl" -> loadWithResolver path
    ".yaml" -> loadWithResolver path
    ".yml" -> loadWithResolver path
    _ -> pure (Left (UnsupportedExtension path))

{- | The shared @.yaml@/@.yml@/@.ttl@ dispatch: drive the imports
resolver over the top-level file, then serialize the flattened
@['EntityDecl']@ via 'emitOverlay'. The fixture-slug for the default
IRI prefix is the basename of the parent directory (e.g.
@.../02-alice-bob-ada/rules.yaml@ → @02-alice-bob-ada@). Both the
YAML and Turtle authoring paths funnel through the same resolver
(T007), so composed import graphs work uniformly across formats.

Single-file inputs (no @owl:imports@ / @imports:@) round-trip
identically to the pre-T007 surface — the resolver's DFS terminates
after one node and emits its entities verbatim.

The two re-exports 'parseRulesYamlText' and 'parseRulesTurtleText'
remain available for callers that only want the in-memory entity
shape without filesystem effects (no resolver pass).
-}
loadWithResolver :: FilePath -> IO (Either RulesLoadError RulesLoadResult)
loadWithResolver path = do
    eResolved <- resolveImports path
    pure $ case eResolved of
        Left err -> Left err
        Right (entities, blueprints, attestations) -> do
            (dedupedBlueprints, blueprintWarnings) <-
                dedupBlueprints blueprints
            let fixtureSlug = Text.pack (takeBaseName (takeDirectory path))
                (dedupedEntities, entityWarnings) = dedupAcrossFiles entities
                bytes =
                    emitOverlay fixtureSlug dedupedEntities attestations
            Right
                RulesLoadResult
                    { rulesOverlayTurtle = bytes
                    , rulesWarnings = entityWarnings <> blueprintWarnings
                    , rulesEntities = dedupedEntities
                    , rulesBlueprints = dedupedBlueprints
                    , rulesAttestations = attestations
                    }

----------------------------------------------------------------------
-- Diagnostic rendering (CLI surface)
----------------------------------------------------------------------

{- | Render a 'RulesLoadError' as a single human-readable line for the
@tx-graph@ executable's stderr. The variants that carry a file path
and a 1-based line number are formatted as @\<file\>:\<line\>:
\<variant\> \<details\>@ so editors and CI log scrapers can hyperlink
back to the offending location. Variants with cross-file provenance
(imports, cycles) render their full file paths in the same line.

The format is deliberately stable but not part of the public API
contract — the executable's tests assert on substring presence
(variant tag + key payload), not on exact byte-equality.
-}
renderRulesLoadError :: RulesLoadError -> String
renderRulesLoadError = \case
    UnsupportedExtension path ->
        "UnsupportedExtension: " <> path
    NotImplemented msg ->
        "NotImplemented: " <> Text.unpack msg
    ParserError file line msg ->
        file <> ":" <> show line <> ": ParserError: " <> Text.unpack msg
    EntityZeroIdentifiers file line name ->
        file
            <> ":"
            <> show line
            <> ": EntityZeroIdentifiers: entity "
            <> show (Text.unpack name)
            <> " declares no identifier shapes"
    BadBech32 file line raw ->
        file
            <> ":"
            <> show line
            <> ": BadBech32: "
            <> show (Text.unpack raw)
    BadPolicyHex file line raw ->
        file
            <> ":"
            <> show line
            <> ": BadPolicyHex: "
            <> show (Text.unpack raw)
    EntityNameSlugEmpty file line raw ->
        file
            <> ":"
            <> show line
            <> ": EntityNameSlugEmpty: "
            <> show (Text.unpack raw)
    EntityNameSlugLeadingDigit file line raw ->
        file
            <> ":"
            <> show line
            <> ": EntityNameSlugLeadingDigit: "
            <> show (Text.unpack raw)
    BlueprintRefsUnknownScript file line name ->
        file
            <> ":"
            <> show line
            <> ": BlueprintRefsUnknownScript: "
            <> show (Text.unpack name)
    MissingImport importer imported ->
        "MissingImport: "
            <> importer
            <> " -> "
            <> imported
    AbsoluteImport importer raw ->
        "AbsoluteImport: "
            <> importer
            <> " -> "
            <> show (Text.unpack raw)
    HttpsImport importer raw ->
        "HttpsImport: "
            <> importer
            <> " -> "
            <> show (Text.unpack raw)
    RulesImportCycle cyc ->
        "RulesImportCycle: " <> renderCycle cyc
    BlueprintFileMissing file line raw ->
        file
            <> ":"
            <> show line
            <> ": BlueprintFileMissing: "
            <> Text.unpack raw
    BlueprintParseError file line raw msg ->
        file
            <> ":"
            <> show line
            <> ": BlueprintParseError: "
            <> Text.unpack raw
            <> ": "
            <> Text.unpack msg
    AbsoluteBlueprintPath file line raw ->
        file
            <> ":"
            <> show line
            <> ": AbsoluteBlueprintPath: "
            <> show (Text.unpack raw)
    HttpsBlueprintPath file line raw ->
        file
            <> ":"
            <> show line
            <> ": HttpsBlueprintPath: "
            <> show (Text.unpack raw)
    DuplicateBlueprintPredicate file line predName ->
        file
            <> ":"
            <> show line
            <> ": DuplicateBlueprintPredicate: "
            <> Text.unpack predName
  where
    renderCycle = \case
        [] -> "<empty cycle>"
        (p : ps) -> foldl (\acc q -> acc <> " -> " <> q) p ps

{- | Render a 'RulesLoadWarning' as a single human-readable line for the
@tx-graph@ executable's stderr. The format mirrors
'renderRulesLoadError' for consistency: a variant tag and the
key payload.
-}
renderRulesLoadWarning :: RulesLoadWarning -> String
renderRulesLoadWarning = \case
    DuplicateEntityAcrossFiles slug kept dropped ->
        "DuplicateEntityAcrossFiles: entity "
            <> show (Text.unpack slug)
            <> " kept from "
            <> kept
            <> ", dropped from "
            <> dropped
    DuplicateBlueprintForScript file line entity ->
        file
            <> ":"
            <> show line
            <> ": DuplicateBlueprintForScript: "
            <> show (Text.unpack entity)

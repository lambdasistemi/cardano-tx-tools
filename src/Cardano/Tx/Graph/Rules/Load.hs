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

    -- * Errors
    RulesLoadError (..),
) where

import Cardano.Tx.Graph.Rules.Load.Emit.Overlay (emitOverlay)
import Cardano.Tx.Graph.Rules.Load.Parse.Turtle (parseRulesTurtleText)
import Cardano.Tx.Graph.Rules.Load.Parse.Yaml (parseRulesYamlText)
import Cardano.Tx.Graph.Rules.Load.Resolve.Imports (
    dedupAcrossFiles,
    resolveImports,
 )
import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
    RulesLoadWarning (..),
 )

import Data.ByteString (ByteString)
import Data.Text qualified as Text
import System.FilePath (takeBaseName, takeDirectory, takeExtension)

{- | Successful loader result. Carries the in-memory triple set, the
serialized operator-entity overlay (canonical Turtle bytes), and any
non-fatal warnings accumulated during the load.

Later slices populate the fields; the scaffold is uninhabited from the
outside in this slice (constructors not exposed yet beyond the public
type).
-}
data RulesLoadResult = RulesLoadResult
    { rulesOverlayTurtle :: !ByteString
    -- ^ The canonical Turtle byte stream the byte-diff golden checks
    -- against @expected.entities.ttl@.
    , rulesWarnings :: ![RulesLoadWarning]
    -- ^ Non-fatal warnings (e.g. cross-file duplicate entity URIs).
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
    eEntities <- resolveImports path
    pure $ case eEntities of
        Left err -> Left err
        Right entities ->
            let fixtureSlug = Text.pack (takeBaseName (takeDirectory path))
                (deduped, warnings) = dedupAcrossFiles entities
                bytes = emitOverlay fixtureSlug deduped
             in Right
                    RulesLoadResult
                        { rulesOverlayTurtle = bytes
                        , rulesWarnings = warnings
                        }

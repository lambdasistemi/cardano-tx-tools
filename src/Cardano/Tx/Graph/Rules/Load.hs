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
'loadRulesFile' entrypoint, and the YAML compiler's in-memory
'parseRulesYamlText' helper (T002). The Turtle parser, the Turtle
serializer, and the cross-file imports resolver land in later slices.
-}
module Cardano.Tx.Graph.Rules.Load (
    -- * Public API
    loadRulesFile,
    parseRulesYamlText,

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
import Cardano.Tx.Graph.Rules.Load.Parse.Yaml (parseRulesYamlText)
import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
 )

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
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

-- | Non-fatal warnings the loader can emit while still returning a 'Right'.
data RulesLoadWarning
    = -- | The same entity URI was declared in two imported files. The
      -- first declaration is kept; the second is dropped (per spec US6).
      DuplicateEntityAcrossFiles !Text !FilePath !FilePath
    deriving stock (Eq, Show)

{- | Load a rules file by path.

The file extension dispatches the parser:

* @.ttl@ — canonical Turtle (T006 will implement).
* @.yaml@, @.yml@ — YAML sugar (T002 onwards; the YAML compiler is
  available in-memory via 'parseRulesYamlText'; the file-loading and
  serializer plumbing lands with T003+).

Any other extension returns 'UnsupportedExtension'.

The scaffold returns 'NotImplemented' for the two supported extensions;
later slices replace the right-hand side with real parsing.
-}
loadRulesFile :: FilePath -> IO (Either RulesLoadError RulesLoadResult)
loadRulesFile path = case takeExtension path of
    ".ttl" -> pure (Left (NotImplemented "turtle"))
    ".yaml" -> loadYaml path
    ".yml" -> loadYaml path
    _ -> pure (Left (UnsupportedExtension path))

{- | Helper for the @.yaml@/@.yml@ dispatch: read the file from disk,
parse via 'parseRulesYamlText', serialize via 'emitOverlay', and wrap
the bytes in 'RulesLoadResult'. The fixture-slug for the default IRI
prefix is the basename of the parent directory (e.g.
@.../02-alice-bob-ada/rules.yaml@ → @02-alice-bob-ada@).
-}
loadYaml :: FilePath -> IO (Either RulesLoadError RulesLoadResult)
loadYaml path = do
    blob <- BS.readFile path
    pure $ case parseRulesYamlText blob of
        Left err -> Left err
        Right entities ->
            let fixtureSlug = Text.pack (takeBaseName (takeDirectory path))
                bytes = emitOverlay fixtureSlug entities
             in Right
                    RulesLoadResult
                        { rulesOverlayTurtle = bytes
                        , rulesWarnings = []
                        }

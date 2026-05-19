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

This scaffold module exposes the public type surface and a 'loadRulesFile'
function. The actual parsing, serialization, and import resolution land in
later slices (T002..T011); right now 'loadRulesFile' returns
@Left UnsupportedExtension@ for unknown extensions and
@Left NotImplemented@ for the two supported extensions.
-}
module Cardano.Tx.Graph.Rules.Load (
    -- * Public API
    loadRulesFile,

    -- * Result + warnings
    RulesLoadResult (..),
    RulesLoadWarning (..),

    -- * Errors
    RulesLoadError (..),
) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import System.FilePath (takeExtension)

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

{- | Structured errors the loader returns via 'Left'. Each constructor
carries enough provenance (file path, line number, offending string)
that the @tx-graph@ CLI and a future LSP can render a hyperlinked
diagnostic.
-}
data RulesLoadError
    = -- | The file's extension is not @.ttl@, @.yaml@, or @.yml@.
      UnsupportedExtension !FilePath
    | -- | Scaffold-only sentinel. Later slices replace this with concrete
      -- error variants per spec FR-018 / Key Entities.
      NotImplemented !Text
    deriving stock (Eq, Show)

{- | Load a rules file by path.

The file extension dispatches the parser:

* @.ttl@ — canonical Turtle (T006 will implement).
* @.yaml@, @.yml@ — YAML sugar (T002 onwards will implement).

Any other extension returns 'UnsupportedExtension'.

The scaffold returns 'NotImplemented' for the two supported extensions;
later slices replace the right-hand side with real parsing.
-}
loadRulesFile :: FilePath -> IO (Either RulesLoadError RulesLoadResult)
loadRulesFile path = pure $ case takeExtension path of
    ".ttl" -> Left (NotImplemented "turtle")
    ".yaml" -> Left (NotImplemented "yaml")
    ".yml" -> Left (NotImplemented "yaml")
    _ -> Left (UnsupportedExtension path)

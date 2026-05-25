{- |
Module      : Cardano.Tx.View
Description : Packaged-view dispatcher for the tx-view executable.
License     : Apache-2.0

Public API of the in-repo view runner. Loads a canonical Turtle
graph file produced by @tx-graph@, dispatches on a named view, and
returns the projected byte stream.

The runner ships @cli-tree@ and @asset-flow@ in #51's first two
behaviour slices; subsequent slices add @entity-occurrences@ and
@json-ld@ under the same dispatcher.

The packaged @.rq@ files under @views\/@ are the vendor-neutral
contracts (see plan D-002 and the no-stub-triples precedent under
'Cardano.Tx.Graph.Emit.NoStubViewSpec'); the Haskell projection layer
in this module and its private submodules is the in-repo execution
engine.
-}
module Cardano.Tx.View (
    -- * View names
    ViewName (..),
    parseViewName,
    renderViewName,
    knownViewNames,

    -- * Errors
    ViewError (..),
    renderViewError,

    -- * Runner
    renderView,
) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text

import Cardano.Tx.View.AssetFlow (renderAssetFlow)
import Cardano.Tx.View.CliTree (renderCliTree)
import Cardano.Tx.View.EntityOccurrences (renderEntityOccurrences)
import Cardano.Tx.View.Turtle (parseTurtle)

----------------------------------------------------------------------
-- View names
----------------------------------------------------------------------

{- | The packaged view names recognised by @tx-view@. Future slices
extend this enumeration as new @views\/\<name\>.rq@ contracts ship.
-}
data ViewName
    = -- | The @cli-tree@ projection.
      CliTree
    | -- | The @asset-flow@ projection.
      AssetFlow
    | -- | The @entity-occurrences@ projection.
      EntityOccurrences
    deriving stock (Eq, Show)

-- | Parse a CLI string into a 'ViewName', or report it as unknown.
parseViewName :: String -> Either ViewError ViewName
parseViewName = \case
    "cli-tree" -> Right CliTree
    "asset-flow" -> Right AssetFlow
    "entity-occurrences" -> Right EntityOccurrences
    other -> Left (UnknownView (Text.pack other))

-- | Inverse of 'parseViewName' — the canonical CLI surface name.
renderViewName :: ViewName -> Text
renderViewName = \case
    CliTree -> "cli-tree"
    AssetFlow -> "asset-flow"
    EntityOccurrences -> "entity-occurrences"

-- | The list of view names this build recognises.
knownViewNames :: [Text]
knownViewNames = ["cli-tree", "asset-flow", "entity-occurrences"]

----------------------------------------------------------------------
-- Errors
----------------------------------------------------------------------

-- | Structured error surface of the view runner.
data ViewError
    = -- | The CLI passed a @--view NAME@ value the dispatcher does
      --   not recognise; carries the offending name.
      UnknownView !Text
    | -- | The Turtle reader rejected the input graph; carries the
      --   reader's diagnostic.
      TurtleParseError !Text
    deriving stock (Eq, Show)

-- | Render a 'ViewError' as a single-line stderr diagnostic.
renderViewError :: ViewError -> Text
renderViewError = \case
    UnknownView name ->
        "tx-view: unknown --view name: "
            <> name
            <> " (known views: "
            <> Text.intercalate ", " knownViewNames
            <> ")"
    TurtleParseError msg ->
        "tx-view: malformed Turtle graph: " <> msg

----------------------------------------------------------------------
-- Runner
----------------------------------------------------------------------

{- | Run a packaged view against a canonical Turtle graph byte stream.
Returns the rendered byte stream on success or a structured
'ViewError' on failure.

Per FR-008, an empty result is success: when a view's projection
matches no rows, the returned ByteString is empty.
-}
renderView :: ViewName -> ByteString -> Either ViewError ByteString
renderView view bs = do
    graph <- case parseTurtle bs of
        Right g -> Right g
        Left err -> Left (TurtleParseError err)
    pure $ case view of
        CliTree -> renderCliTree graph
        AssetFlow -> renderAssetFlow graph
        EntityOccurrences -> renderEntityOccurrences bs graph

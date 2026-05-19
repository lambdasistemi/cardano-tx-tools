{- |
Module      : Cardano.Tx.Graph.Rules.Load.Resolve.Imports
Description : DFS resolver for @owl:imports@ / @imports:@ composition.
License     : Apache-2.0

Walks a rules file's import graph and produces a flat
@['EntityDecl']@ list spanning the file's transitive closure.

== Inputs

* The top-level file's absolute path on disk.

== Outputs

* @'Right' [EntityDecl]@ — entities flattened in
  reverse-post-order (children before parents). Diamond imports are
  loaded exactly once.
* @'Left' 'RulesLoadError'@ — structured failure (missing import,
  absolute path, HTTPS URI, or any parse-level error bubbled up from
  the per-file parsers).

== Algorithm

Three-state DFS (White / Grey / Black) over the import graph.
White nodes are absent from the visit map; Grey marks an
in-progress frontier (the DFS-active path); Black marks a fully
loaded subtree. A second-visit to a Grey node is a back-edge —
the loader surfaces 'RulesImportCycle' carrying the cycle path
in DFS-entry order, with the revisited node appended at the end
so the cycle reads naturally (e.g. @[a, b, a]@ for a two-file
cycle @a → b → a@; @[a, a]@ for a self-import).

For each node:

1. Canonicalize the importer's path (so duplicate references to the
   same physical file deduplicate even when authored as different
   relative path strings).
2. If the canonical path is Black in the visit map, return @[]@
   (the diamond-merge step — the file's entities were emitted on
   the first visit).
3. If the canonical path is Grey in the visit map, abort with
   'RulesImportCycle' whose payload is the suffix of the active
   DFS path starting at the revisited node, with the revisited
   node appended at the end (the cycle, in cycle order).
4. Mark the path Grey, then read and parse the file (dispatch on
   extension).
5. For each raw import string:

    * Reject @http://@ / @https://@ as 'HttpsImport' (default-offline,
      FR-017 / analyzer N4).
    * Reject @file://@ as 'AbsoluteImport' (the constitution forbids
      absolute imports — every relative path is resolved against the
      importer's directory).
    * Reject any other absolute filesystem path as 'AbsoluteImport'.
    * Otherwise, resolve the relative path against the importer's
      directory; stat it; if the resolved file does not exist surface
      'MissingImport'; else recurse, appending the importer's
      canonical path to the active DFS path.

6. Once every child returns, mark the path Black and accumulate the
   file's own entities **after** its children, so a parent file's
   entities appear after the entities it imports — the reverse-
   post-order property the loader's overlap-detector (downstream)
   and the cross-file dup warning (T010) rely on.

The function is total: a DAG terminates after one visit per node,
and a back-edge is detected and surfaced as 'RulesImportCycle'
before any infinite recursion can occur.
-}
module Cardano.Tx.Graph.Rules.Load.Resolve.Imports (
    resolveImports,
) where

import Cardano.Tx.Graph.Rules.Load.Parse.Turtle (
    parseRulesTurtleImportsWithFile,
 )
import Cardano.Tx.Graph.Rules.Load.Parse.Yaml (
    parseRulesYamlImportsWithFile,
 )
import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    RulesLoadError (..),
 )

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import Control.Monad.Trans.State.Strict (StateT, evalStateT, get, modify')
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (canonicalizePath, doesFileExist)
import System.FilePath (
    isAbsolute,
    takeDirectory,
    takeExtension,
    (</>),
 )

{- | Tri-state colour of a node in the DFS visit map. White is the
absence of a key (no entry in the map); 'Grey' is the in-progress
frontier (the active DFS path); 'Black' is a fully loaded subtree.
A revisit to a 'Grey' node is a back-edge — the loader surfaces
'RulesImportCycle' carrying the cycle path.
-}
data VisitState
    = Grey
    | Black
    deriving stock (Eq, Show)

-- | The DFS visit map keyed by canonical path.
type VisitMap = Map FilePath VisitState

{- | Resolve a top-level rules file's full import graph into a flat
@['EntityDecl']@ list. Entities are returned in DFS post-order
(children before parents); diamond imports are loaded exactly once.

The argument is the file path the operator invoked the loader with;
it can be either absolute or relative — the resolver canonicalizes
it before the DFS starts so the visited-set comparison is reliable.
-}
resolveImports ::
    FilePath -> IO (Either RulesLoadError [EntityDecl])
resolveImports topPath = do
    -- The caller's path may be relative — canonicalize once so the
    -- visit-map keys are consistent across the DFS.
    canonicalTop <- canonicalizePath topPath
    runExceptT (evalStateT (dfs [] canonicalTop) Map.empty)

{- | DFS over the import graph. The 'StateT' tracks the tri-state
visit map keyed by canonical path; the 'ExceptT' threads the first
structured error up to the caller.

The @activePath@ argument is the DFS-entry-ordered list of canonical
paths currently on the active frontier (the Grey nodes). On a
'Grey' revisit, the back-edge handler slices @activePath@ from the
revisited node onward and appends the revisited node so the cycle
payload reads naturally (e.g. @[a, b, a]@).

The @canonicalPath@ argument doubles as the importer the
diagnostic-bearing 'MissingImport' / 'AbsoluteImport' / 'HttpsImport'
errors carry when one of its imports is rejected.
-}
dfs ::
    [FilePath] ->
    FilePath ->
    StateT
        VisitMap
        (ExceptT RulesLoadError IO)
        [EntityDecl]
dfs activePath canonicalPath = do
    visited <- get
    case Map.lookup canonicalPath visited of
        Just Black -> pure []
        Just Grey ->
            lift
                ( throwE
                    (RulesImportCycle (cyclePath activePath canonicalPath))
                )
        Nothing -> do
            modify' (Map.insert canonicalPath Grey)
            (imports, ownEntities) <- parseFile canonicalPath
            let activePath' = activePath <> [canonicalPath]
            childEntities <-
                traverse (resolveChild activePath' canonicalPath) imports
            modify' (Map.insert canonicalPath Black)
            -- Reverse-post-order: children before parent.
            pure (concat childEntities <> ownEntities)

{- | Build the cycle-path payload for a 'RulesImportCycle'.

Given the active DFS path (in DFS-entry order) and the canonical
path of the revisited Grey node, return the suffix of the active
path starting at the revisited node with the revisited node
appended at the end. The result reads as a closed loop:
@start, hop_1, …, hop_k, start@.

By invariant @revisited@ is on the active path whenever this
function is called from the DFS back-edge handler (Grey means
in-progress on the current frontier), so @dropWhile (/= revisited)
activePath@ is non-empty. The defensive fallback @[revisited,
revisited]@ guards the impossible "not on path" case so the loader
cannot return an empty cycle list under any future refactor.
-}
cyclePath :: [FilePath] -> FilePath -> [FilePath]
cyclePath activePath revisited =
    case dropWhile (/= revisited) activePath of
        [] -> [revisited, revisited]
        xs -> xs <> [revisited]

{- | Parse the file at @canonicalPath@, dispatching on its extension.
Bubbles up the per-parser 'RulesLoadError' on a malformed file.
-}
parseFile ::
    FilePath ->
    StateT
        VisitMap
        (ExceptT RulesLoadError IO)
        ([Text], [EntityDecl])
parseFile path = do
    blob <- liftIO (BS.readFile path)
    case takeExtension path of
        ".ttl" -> liftEither (parseRulesTurtleImportsWithFile path blob)
        ".yaml" -> liftEither (parseRulesYamlImportsWithFile path blob)
        ".yml" -> liftEither (parseRulesYamlImportsWithFile path blob)
        _ -> liftEither (Left (UnsupportedExtension path))
  where
    liftEither = lift . ExceptT . pure

{- | Resolve one raw import string against its importer's directory
and recurse. Performs the URI / absolute / missing-file checks
listed in the module header.
-}
resolveChild ::
    [FilePath] ->
    FilePath ->
    Text ->
    StateT
        VisitMap
        (ExceptT RulesLoadError IO)
        [EntityDecl]
resolveChild activePath importer importRaw
    | isHttpsLike importRaw =
        throw (HttpsImport importer importRaw)
    | isFileUri importRaw =
        throw (AbsoluteImport importer importRaw)
    | isAbsolute (Text.unpack importRaw) =
        throw (AbsoluteImport importer importRaw)
    | otherwise = do
        let relPath = Text.unpack importRaw
            importerDir = takeDirectory importer
            resolvedRaw = importerDir </> relPath
        exists <- liftIO (doesFileExist resolvedRaw)
        if not exists
            then throw (MissingImport importer resolvedRaw)
            else do
                canonicalChild <- liftIO (canonicalizePath resolvedRaw)
                dfs activePath canonicalChild
  where
    throw = lift . throwE

{- | True for HTTP(S) URIs. The default-offline rule (FR-017 /
analyzer N4) forbids the loader from following these.
-}
isHttpsLike :: Text -> Bool
isHttpsLike t =
    Text.isPrefixOf "https://" t || Text.isPrefixOf "http://" t

-- | True for @file://@ URIs. Treated as absolute (analyzer N2).
isFileUri :: Text -> Bool
isFileUri = Text.isPrefixOf "file://"

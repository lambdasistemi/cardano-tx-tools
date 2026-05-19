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

DFS, three-state-ready but only two states (White / Black) are used
in this slice — the Grey state used to detect back-edges in the
cycle-detection pass is reserved for T008. Every test in this slice
authors only DAG inputs; a cycle would diverge through @readFile@.

For each node:

1. Canonicalize the importer's path (so duplicate references to the
   same physical file deduplicate even when authored as different
   relative path strings).
2. If the canonical path is already in the visited set, return @[]@
   (the diamond-merge step — the file's entities were emitted on the
   first visit).
3. Mark the path visited.
4. Read and parse the file (dispatch on extension).
5. For each raw import string:

    * Reject @http://@ / @https://@ as 'HttpsImport' (default-offline,
      FR-017 / analyzer N4).
    * Reject @file://@ as 'AbsoluteImport' (the constitution forbids
      absolute imports — every relative path is resolved against the
      importer's directory).
    * Reject any other absolute filesystem path as 'AbsoluteImport'.
    * Otherwise, resolve the relative path against the importer's
      directory; stat it; if the resolved file does not exist surface
      'MissingImport'; else recurse.

6. Accumulate the file's own entities **after** its children, so a
   parent file's entities appear after the entities it imports — the
   reverse-post-order property the loader's overlap-detector
   (downstream) and the cross-file dup warning (T010) rely on.

The function is total in the absence of cycles. Cycle detection is
deferred to T008; a back-edge in this slice produces unbounded
recursion.
-}
module Cardano.Tx.Graph.Rules.Load.Resolve.Imports (
    resolveImports,
) where

import Cardano.Tx.Graph.Rules.Load.Parse.Turtle (
    parseRulesTurtleImports,
 )
import Cardano.Tx.Graph.Rules.Load.Parse.Yaml (
    parseRulesYamlImports,
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
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (canonicalizePath, doesFileExist)
import System.FilePath (
    isAbsolute,
    takeDirectory,
    takeExtension,
    (</>),
 )

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
    -- visited-set keys are consistent across the DFS.
    canonicalTop <- canonicalizePath topPath
    runExceptT (evalStateT (dfs canonicalTop) Set.empty)

{- | DFS over the import graph. The 'StateT' tracks the visited set
keyed by canonical path; the 'ExceptT' threads the first structured
error up to the caller. The two-state White / Black scheme is
sufficient for DAG inputs — Grey (in-progress) for cycle detection
is T008's surface.

The @canonicalPath@ argument doubles as the importer the
diagnostic-bearing 'MissingImport' / 'AbsoluteImport' / 'HttpsImport'
errors carry when one of its imports is rejected.
-}
dfs ::
    FilePath ->
    StateT
        (Set FilePath)
        (ExceptT RulesLoadError IO)
        [EntityDecl]
dfs canonicalPath = do
    visited <- get
    if Set.member canonicalPath visited
        then pure []
        else do
            modify' (Set.insert canonicalPath)
            (imports, ownEntities) <- parseFile canonicalPath
            childEntities <- traverse (resolveChild canonicalPath) imports
            -- Reverse-post-order: children before parent.
            pure (concat childEntities <> ownEntities)

{- | Parse the file at @canonicalPath@, dispatching on its extension.
Bubbles up the per-parser 'RulesLoadError' on a malformed file.
-}
parseFile ::
    FilePath ->
    StateT
        (Set FilePath)
        (ExceptT RulesLoadError IO)
        ([Text], [EntityDecl])
parseFile path = do
    blob <- liftIO (BS.readFile path)
    case takeExtension path of
        ".ttl" -> liftEither (parseRulesTurtleImports blob)
        ".yaml" -> liftEither (parseRulesYamlImports blob)
        ".yml" -> liftEither (parseRulesYamlImports blob)
        _ -> liftEither (Left (UnsupportedExtension path))
  where
    liftEither = lift . ExceptT . pure

{- | Resolve one raw import string against its importer's directory
and recurse. Performs the URI / absolute / missing-file checks
listed in the module header.
-}
resolveChild ::
    FilePath ->
    Text ->
    StateT
        (Set FilePath)
        (ExceptT RulesLoadError IO)
        [EntityDecl]
resolveChild importer importRaw
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
                dfs canonicalChild
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

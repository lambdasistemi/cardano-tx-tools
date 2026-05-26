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
    dedupAcrossFiles,
    dedupBlueprints,
    blueprintPredicates,
    ResolvedBlueprint,
) where

import Cardano.Tx.Blueprint (
    Blueprint (..),
    BlueprintArgument (..),
    BlueprintPreamble (..),
    BlueprintSchema (..),
    BlueprintSchemaKind (..),
    BlueprintValidator (..),
    parseBlueprintJSON,
 )
import Cardano.Tx.Graph.Rules.Load.Parse.Turtle (
    parseRulesTurtleImportsWithFile,
 )
import Cardano.Tx.Graph.Rules.Load.Parse.Yaml (
    BlueprintStub (..),
    parseRulesYamlImportsWithFile,
 )
import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    RulesLoadError (..),
    RulesLoadWarning (..),
 )

import Cardano.Ledger.Hashes (ScriptHash)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import Control.Monad.Trans.State.Strict (StateT, evalStateT, get, modify')
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
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

{- | A blueprint-index entry produced by the resolver's IO stage,
paired with its originating 'BlueprintStub' so downstream dedup can
attach file:line provenance to the warnings and errors it emits.
-}
type ResolvedBlueprint = (BlueprintStub, ScriptHash, Blueprint, Text)

{- | Resolve a top-level rules file's full import graph into a flat
@['EntityDecl']@ list plus a flat list of resolved blueprint entries
(each entry pairs the loaded @(ScriptHash, 'Blueprint', title)@ triple
with the 'BlueprintStub' it came from, so 'dedupBlueprints' can mint
its warnings and errors with the operator-typed source position).
Entities and blueprints are returned in DFS post-order (children
before parents); diamond imports are loaded exactly once.

The argument is the file path the operator invoked the loader with;
it can be either absolute or relative — the resolver canonicalizes
it before the DFS starts so the visited-set comparison is reliable.

For each @blueprints:@ stub produced by the per-file parser, the
resolver performs the IO stage: resolves the @datum:@ relative path
against the rules.yaml's directory, reads the file, and parses it
via 'parseBlueprintJSON'. A missing file becomes
'BlueprintFileMissing'; an aeson decode failure becomes
'BlueprintParseError'. Successfully-loaded entries are appended to
the result in source order — first-wins dedup and predicate-
collision detection happen downstream in 'dedupBlueprints'.
-}
resolveImports ::
    FilePath ->
    IO (Either RulesLoadError ([EntityDecl], [ResolvedBlueprint]))
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
        ([EntityDecl], [ResolvedBlueprint])
dfs activePath canonicalPath = do
    visited <- get
    case Map.lookup canonicalPath visited of
        Just Black -> pure ([], [])
        Just Grey ->
            lift
                ( throwE
                    (RulesImportCycle (cyclePath activePath canonicalPath))
                )
        Nothing -> do
            modify' (Map.insert canonicalPath Grey)
            (imports, ownEntities, ownStubs) <- parseFile canonicalPath
            ownBlueprints <- traverse loadBlueprintStub ownStubs
            let activePath' = activePath <> [canonicalPath]
            children <-
                traverse (resolveChild activePath' canonicalPath) imports
            modify' (Map.insert canonicalPath Black)
            -- Reverse-post-order: children before parent.
            let childEntities = concatMap fst children
                childBlueprints = concatMap snd children
            pure
                ( childEntities <> ownEntities
                , childBlueprints <> ownBlueprints
                )

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

Turtle files do not carry @blueprints:@ entries; their stub list is
always empty.
-}
parseFile ::
    FilePath ->
    StateT
        VisitMap
        (ExceptT RulesLoadError IO)
        ([Text], [EntityDecl], [BlueprintStub])
parseFile path = do
    blob <- liftIO (BS.readFile path)
    case takeExtension path of
        ".ttl" ->
            liftEither $
                fmap
                    (\(imp, ents) -> (imp, ents, []))
                    (parseRulesTurtleImportsWithFile path blob)
        ".yaml" -> liftEither (parseRulesYamlImportsWithFile path blob)
        ".yml" -> liftEither (parseRulesYamlImportsWithFile path blob)
        _ -> liftEither (Left (UnsupportedExtension path))
  where
    liftEither = lift . ExceptT . pure

{- | IO half of blueprint loading. Resolves the stub's raw @datum:@
path against the rules.yaml's directory, reads the JSON, and parses
it via 'parseBlueprintJSON'. Errors:

* file does not exist → 'BlueprintFileMissing';
* aeson decode failure → 'BlueprintParseError'.

The third tuple element of the success result is the blueprint's
preamble title — preserved for predicate naming and diagnostic
messages per the brief.
-}
loadBlueprintStub ::
    BlueprintStub ->
    StateT
        VisitMap
        (ExceptT RulesLoadError IO)
        ResolvedBlueprint
loadBlueprintStub stub@BlueprintStub{stubRulesFile, stubLine, stubScriptHash, stubDatumRaw} = do
    let importerDir = takeDirectory stubRulesFile
        resolved = importerDir </> Text.unpack stubDatumRaw
    exists <- liftIO (doesFileExist resolved)
    if not exists
        then
            lift
                ( throwE
                    ( BlueprintFileMissing
                        stubRulesFile
                        stubLine
                        stubDatumRaw
                    )
                )
        else do
            blob <- liftIO (LBS.readFile resolved)
            case parseBlueprintJSON blob of
                Left err ->
                    lift
                        ( throwE
                            ( BlueprintParseError
                                stubRulesFile
                                stubLine
                                stubDatumRaw
                                (Text.pack err)
                            )
                        )
                Right bp ->
                    pure
                        ( stub
                        , stubScriptHash
                        , bp
                        , preambleTitle (blueprintPreamble bp)
                        )

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
        ([EntityDecl], [ResolvedBlueprint])
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

{- | Enumerate every @\<ConstructorTitle\>_\<FieldTitle\>@ predicate
name a blueprint would mint, in source-order-equivalent traversal
order (preorder over the resolved schema tree reachable from the
validators' datum and redeemer arguments).

For each 'SchemaConstructor':

* The constructor's title is @schemaTitle@ if present, otherwise
  @"_\<index\>"@ (the FR-008 fallback for an unnamed constructor).
* Each field's title is the field schema's @schemaTitle@ if present,
  otherwise @"field\<n\>"@ at 0-based position @n@.
* The minted predicate's local part is
  @\<ctor\>_\<field\>@.

Walks recurse into constructor fields, @anyOf@ alternatives, fixed-
position @SchemaList@ items, and @SchemaListOf@ items so nested
constructors contribute their own predicates.

@$ref@ nodes are resolved through 'resolveBlueprintSchema'; a
resolution failure (cyclic or dangling reference) drops the
sub-tree silently — those failures surface at the emitter slice
when the failing argument is actually walked.
-}
blueprintPredicates :: Blueprint -> [Text]
blueprintPredicates bp =
    concatMap validatorPredicates (blueprintValidators bp)
  where
    validatorPredicates v =
        maybe [] argPredicates (validatorDatum v)
            <> maybe [] argPredicates (validatorRedeemer v)
    argPredicates arg = walkSchema Set.empty (argumentSchema arg)

    -- Walk a schema tree in preorder, following @$ref@ nodes through
    -- the blueprint's definitions map and enumerating one predicate per
    -- @(constructor, field)@ pair encountered. The @seen@ set tracks
    -- definition names currently on the resolution path so a cyclic
    -- reference terminates rather than diverging.
    walkSchema :: Set Text -> BlueprintSchema -> [Text]
    walkSchema seen schema = case schemaKind schema of
        SchemaReference ref
            | Set.member ref seen -> []
            | otherwise -> case Map.lookup ref (blueprintDefinitions bp) of
                Nothing -> []
                Just def -> walkSchema (Set.insert ref seen) def
        SchemaConstructor index fields ->
            let ctorName = case schemaTitle schema of
                    Just t -> t
                    Nothing -> Text.pack ("_" <> show index)
                here =
                    [ ctorName <> "_" <> fieldName idx fieldSchema
                    | (idx, fieldSchema) <- zip [0 :: Int ..] fields
                    ]
                nested = concatMap (walkSchema seen) fields
             in here <> nested
        SchemaAnyOf alts -> concatMap (walkSchema seen) alts
        SchemaList fields -> concatMap (walkSchema seen) fields
        SchemaListOf item -> walkSchema seen item
        SchemaMap keySchema valueSchema ->
            walkSchema seen keySchema <> walkSchema seen valueSchema
        SchemaInteger -> []
        SchemaBytes -> []
        SchemaData -> []
    fieldName idx s = case schemaTitle s of
        Just t -> t
        Nothing -> Text.pack ("field" <> show idx)

{- | Deduplicate a flat blueprint-index list keyed by 'ScriptHash',
emitting first-wins warnings + a hard predicate-collision error.

Strategy:

1. Walk the list in source order. For each entry, look up its
   'ScriptHash' in the accumulating map:

    * Not seen → keep the entry, add its predicates to the
      accumulating set, recurse.
    * Seen → drop the second entry and emit
      'DuplicateBlueprintForScript' (first-wins per spec Edge Case
      5 / D-001f / A-001). The warning's payload uses the
      corresponding 'BlueprintStub' for the dropped declaration so
      it carries the rules.yaml path, line, and entity name.

2. Before each entry's predicates are added to the accumulating set,
   check whether any of them is already present:

    * Yes, registered by the SAME 'Blueprint' value (issue #101):
      accept the new registration. The same parameterised contract
      can be deployed under multiple script hashes (one per
      operator-named scope), and the typed-decode predicates are
      derived deterministically from the schema — so two scope
      bindings of the same blueprint produce identical predicate
      URIs. Keep the second 'ScriptHash' binding so the decoder
      finds the blueprint via either scope's hash at emit time.
    * Yes, registered by a DIFFERENT 'Blueprint' value: hard error
      ('DuplicateBlueprintPredicate', D-001b / A-001). A true
      predicate-URI collision across distinct schemas is a config
      bug; the error's payload carries the colliding entry's
      rules.yaml path, line, and the predicate name.

The function consumes the stub list in parallel with the
loaded-blueprint list so the diagnostic payloads can name the
operator-authored source position; the two lists are produced in
lockstep by the resolver.
-}
dedupBlueprints ::
    [ResolvedBlueprint] ->
    Either RulesLoadError ([(ScriptHash, Blueprint, Text)], [RulesLoadWarning])
dedupBlueprints =
    go Set.empty Map.empty [] []
  where
    go ::
        Set ScriptHash ->
        Map Text Blueprint ->
        [(ScriptHash, Blueprint, Text)] ->
        [RulesLoadWarning] ->
        [ResolvedBlueprint] ->
        Either RulesLoadError ([(ScriptHash, Blueprint, Text)], [RulesLoadWarning])
    go _ _ kept warns [] = Right (reverse kept, reverse warns)
    go seenHashes seenPreds kept warns ((stub, sh, bp, title) : rest)
        | Set.member sh seenHashes =
            let w =
                    DuplicateBlueprintForScript
                        (stubRulesFile stub)
                        (stubLine stub)
                        (stubScriptName stub)
             in go seenHashes seenPreds kept (w : warns) rest
        | otherwise =
            case firstCollision seenPreds bp (blueprintPredicates bp) of
                Just predName ->
                    Left $
                        DuplicateBlueprintPredicate
                            (stubRulesFile stub)
                            (stubLine stub)
                            predName
                Nothing ->
                    let newPreds =
                            foldr
                                (`Map.insert` bp)
                                seenPreds
                                (blueprintPredicates bp)
                     in go
                            (Set.insert sh seenHashes)
                            newPreds
                            ((sh, bp, title) : kept)
                            warns
                            rest
    -- Return the first predicate from the new blueprint that is
    -- already in the accumulating map under a DIFFERENT
    -- 'Blueprint' value (in the new blueprint's enumeration order,
    -- which is the source-equivalent preorder). Same-blueprint
    -- collisions are silently skipped — they encode the
    -- "shared blueprint across N scripts" pattern, issue #101.
    firstCollision :: Map Text Blueprint -> Blueprint -> [Text] -> Maybe Text
    firstCollision seen bp = \case
        [] -> Nothing
        (p : ps) ->
            case Map.lookup p seen of
                Just bp' | bp' /= bp -> Just p
                _ -> firstCollision seen bp ps

{- | Deduplicate an 'EntityDecl' list by 'entitySlug' while emitting a
'DuplicateEntityAcrossFiles' warning for every entity-slug collision
that spans two different source files.

Spec FR-011 / US6: when two imported files declare the same entity
slug, the loader does not attempt to infer additive vs conflicting
intent. The first declaration in source order wins; the second is
dropped from the output; the warning names both files so the
operator can locate the duplication and resolve it explicitly.

Source order is the resolver's reverse-post-order (children before
parents), which is what 'resolveImports' returns. The first-wins
rule applied to that order means: a file appears in the output
exactly once even when reachable via multiple import paths
(handled by the DFS diamond merge), and a slug declared in two
distinct files surfaces the warning at the second file's site.

Same-file dups (e.g. two @- name: foo@ entries in one YAML file)
are passed through unchanged here — the per-file parsers are the
single source of truth for that case, and a future hard-error
slice (FR-009 follow-up) will surface them upstream of the
resolver. The cross-file relaxation pinned by FR-011 fires only
when @entitySourceFile@ differs.
-}
dedupAcrossFiles ::
    [EntityDecl] -> ([EntityDecl], [RulesLoadWarning])
dedupAcrossFiles = go Map.empty [] []
  where
    -- @seen@ records the first-seen 'entitySourceFile' per slug;
    -- @kept@ accumulates the deduplicated 'EntityDecl' list in
    -- reverse source order; @warns@ accumulates the warning list
    -- in reverse emission order. Both are reversed in the base case
    -- so the caller observes source order.
    go ::
        Map Text FilePath ->
        [EntityDecl] ->
        [RulesLoadWarning] ->
        [EntityDecl] ->
        ([EntityDecl], [RulesLoadWarning])
    go _ kept warns [] = (reverse kept, reverse warns)
    go seen kept warns (d : rest) =
        let slug = entitySlug d
            src = entitySourceFile d
         in case Map.lookup slug seen of
                Nothing ->
                    go (Map.insert slug src seen) (d : kept) warns rest
                Just firstSrc
                    | firstSrc == src ->
                        -- Same-file dup — not the cross-file case.
                        -- Keep the declaration as-is; a future
                        -- single-file dup error variant will fire
                        -- upstream in the per-file parser.
                        go seen (d : kept) warns rest
                    | otherwise ->
                        let w =
                                DuplicateEntityAcrossFiles
                                    slug
                                    firstSrc
                                    src
                         in go seen kept (w : warns) rest

{- |
Module      : Cardano.Tx.Graph.Rules.Load.Parse.Yaml
Description : YAML compiler for the operator-authored rules-loader.
License     : Apache-2.0

Decodes a @rules.yaml@ blob into an in-memory @['EntityDecl']@ list.
Handles the five basic entity shapes — @from-address: \<bech32\>@,
@script: \<hex\>@, @asset: { policy, name }@, @pool: \<bech32\>@,
@drep: \<CIP-129 bech32\>@ — and the compound-key shape
@keys: [LeafType, …] + bytes: \<hex\>@ (fixture-04's cross-leaf
identity surface), producing, per entity, one or more
@(leafType, bytesHex)@ identifier pairs that the Turtle serializer
folds into canonical @cardano:Identifier@ blank nodes.

@imports:@ is ignored for now (composition lands with T007/T008).

@blueprints:@ is **shape-validated** at the top level — each entry
must be an object carrying a @script: \<name\>@ key whose value
names an entity declared in the same file *and* using the
@script:@ shape (i.e. that entity carries a 'PaymentScript'
identifier). The @datum:@ field is a path string that the loader
accepts verbatim; resolution against the filesystem lives in a
later slice. A reference to an unknown or non-script entity name
returns 'BlueprintRefsUnknownScript'.

@collapse:@ is silently accepted — it is the view-collapse surface
owned by #51 and the overlay serializer does not emit triples for
it. The parser only verifies the value is a list (so a typed key
is not misread as a different shape).

The slug algorithm:

* lowercase the @name:@ field;
* rewrite every character outside @[a-z0-9]@ to @_@;
* collapse runs of @_@ into a single @_@;
* trim leading and trailing @_@.

An empty slug or a slug that starts with a digit is rejected with
'EntityNameSlugEmpty' / 'EntityNameSlugLeadingDigit'. (Turtle's
PN_LOCAL allows leading digits, but bnode local-parts like @_:0foo@
are stylistically ambiguous — see spec edge cases.)

== Source-line provenance (T009)

The parser threads a 'Ctx' record (file path + per-entity / per-
blueprint source lines) through every error producer site. Lines
are 1-based to match every editor and LSP. The mapping is
computed by 'entityNameLines' and 'blueprintScriptLines', which
pre-scan the raw byte blob for @^\\s*- name:@ and @^\\s*- script:@
lines respectively, in source order. The walk over the parsed
'Aeson.Value' then zips entities and blueprints with their source
lines via list-index alignment.

YAML decode failures (libyaml-level parse errors) extract the line
number from the libyaml 'YamlMark' (which is 0-based; we add 1).
-}
module Cardano.Tx.Graph.Rules.Load.Parse.Yaml (
    parseRulesYamlText,
    parseRulesYamlImports,
    parseRulesYamlImportsWithFile,
    slugify,
    BlueprintStub (..),
) where

import Cardano.Tx.Graph.Rules.Load.Bech32 (
    decodeDrepCip129,
    decodePoolBech32,
    decomposeFromAddress,
 )
import Cardano.Tx.Graph.Rules.Load.Types (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
 )

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.Ledger.Hashes (ScriptHash (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Char (isAsciiLower, isDigit)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Text.Encoding.Error (lenientDecode)
import Data.Yaml qualified as Yaml
import System.FilePath (isAbsolute)
import Text.Libyaml qualified as Libyaml

{- | The placeholder file path attached to errors when the caller uses
the in-memory entry point ('parseRulesYamlText' /
'parseRulesYamlImports') with no real file path. The
'Cardano.Tx.Graph.Rules.Load.loadRulesFile' entrypoint threads the
real path through 'parseRulesYamlImportsWithFile'.
-}
inMemoryFile :: FilePath
inMemoryFile = "<in-memory>"

{- | Per-parse-call context: source file path plus the 1-based source
line of every entity's @- name:@ key and every blueprint entry's
@- script:@ key (in source order). The walk over the parsed
'Aeson.Value' indexes into these lists to attach a real source line
to each error.

When the parser has no per-entity line (e.g. for top-level shape
errors like @entities: must be a list@), it falls back to line 1
('topLevelLine') — the start of the document.
-}
data Ctx = Ctx
    { ctxFile :: !FilePath
    , ctxEntityLines :: ![Int]
    , ctxBlueprintLines :: ![Int]
    }

-- | The fallback line for an error with no per-entity context.
topLevelLine :: Int
topLevelLine = 1

{- | Parse a @rules.yaml@ byte blob into the in-memory entity list.

Returns @Right []@ for an empty document or one lacking an @entities:@
key (composition via @imports:@ is a later slice). Otherwise walks
each @entities:@ entry, computes its slug, dispatches on the
@from-address@ / @script@ / @asset@ shape, and produces one or more
'EntityIdentifier' values per entity.

Any structural failure (invalid YAML, non-string name, malformed
bech32, bad hex) surfaces as a 'RulesLoadError' via 'Left'.

The in-memory entry point uses @\<in-memory\>@ as the source file in
every error. For real file-path provenance, drive
'Cardano.Tx.Graph.Rules.Load.loadRulesFile' (which threads the file
path through 'parseRulesYamlImportsWithFile').

The in-memory entry points discard the blueprint stub list; the
file-aware 'parseRulesYamlImportsWithFile' threads it through to the
resolver for IO loading + JSON parsing.
-}
parseRulesYamlText :: ByteString -> Either RulesLoadError [EntityDecl]
parseRulesYamlText = fmap (\(_, ents, _) -> ents) . parseRulesYamlImports

{- | Parse a @rules.yaml@ byte blob into the raw @imports:@ list (in
source order), the in-memory entity list, and the blueprint stub
list. Uses the placeholder @\<in-memory\>@ file path — see
'parseRulesYamlImportsWithFile' for the file-aware variant used by
the imports resolver.

Returns @Right ([], [], [])@ for an empty document. Each element of
the returned import list is the raw operator-authored string — the
resolver applies its own absolute/HTTPS/missing-file checks. Each
'BlueprintStub' captures one @blueprints:@ entry's metadata so the
resolver can do the file-read + JSON-parse step in IO.
-}
parseRulesYamlImports ::
    ByteString ->
    Either RulesLoadError ([Text], [EntityDecl], [BlueprintStub])
parseRulesYamlImports = parseRulesYamlImportsWithFile inMemoryFile

{- | Variant of 'parseRulesYamlImports' that takes the source 'FilePath'
so every 'RulesLoadError' carries real (file, line) provenance. Used
by 'Cardano.Tx.Graph.Rules.Load.Resolve.Imports.resolveImports'.

The third element of the result is the list of 'BlueprintStub' values
extracted from this file's @blueprints:@ section, in source order.
The stubs carry just enough metadata (rules.yaml path, source line,
script entity name, decoded 'ScriptHash', raw @datum:@ path string)
for the resolver's IO stage to load + parse each blueprint JSON and
the post-resolver dedup stage to apply first-wins + predicate
collision detection.
-}
parseRulesYamlImportsWithFile ::
    FilePath ->
    ByteString ->
    Either RulesLoadError ([Text], [EntityDecl], [BlueprintStub])
parseRulesYamlImportsWithFile file blob =
    let ctx =
            Ctx
                { ctxFile = file
                , ctxEntityLines = entityNameLines blob
                , ctxBlueprintLines = blueprintScriptLines blob
                }
     in case Yaml.decodeEither' blob of
            Left err ->
                Left $
                    ParserError
                        file
                        (yamlParseExceptionLine err)
                        (Text.pack ("YAML decode failed: " <> show err))
            Right val -> walkTop ctx val

{- | Extract a 1-based source line from a 'Yaml.ParseException'. The
libyaml-level 'YamlMark' is 0-based; we add 1. Any other exception
shape falls back to 'topLevelLine' (line 1) — there is no source
position to surface.
-}
yamlParseExceptionLine :: Yaml.ParseException -> Int
yamlParseExceptionLine = \case
    Yaml.InvalidYaml (Just (Libyaml.YamlParseException _ _ mark)) ->
        Libyaml.yamlLine mark + 1
    Yaml.InvalidYaml (Just (Libyaml.YamlException _)) -> topLevelLine
    Yaml.InvalidYaml Nothing -> topLevelLine
    _ -> topLevelLine

walkTop ::
    Ctx ->
    Aeson.Value ->
    Either RulesLoadError ([Text], [EntityDecl], [BlueprintStub])
walkTop ctx = \case
    Aeson.Null -> Right ([], [], [])
    Aeson.Object obj -> do
        imports <- parseImportsKey ctx obj
        entities <- case KeyMap.lookup (Key.fromText "entities") obj of
            Nothing -> Right []
            Just Aeson.Null -> Right []
            Just (Aeson.Array arr) ->
                traverseWithLines
                    (parseEntity ctx)
                    (foldr (:) [] arr)
                    (ctxEntityLines ctx)
            Just other ->
                Left $
                    ParserError
                        (ctxFile ctx)
                        topLevelLine
                        ( "entities: must be a list, got: "
                            <> typeName other
                        )
        -- @blueprints:@ is shape-validated AND parsed into stubs at
        -- parse time. The stub carries the script entity's decoded
        -- 'ScriptHash' and the raw @datum:@ path string; the
        -- resolver's IO stage does the file-read + JSON-parse step.
        stubs <- validateBlueprints ctx entities obj
        -- @collapse:@ is silently accepted (typed-list shape only;
        -- triples are emitted by #51, not the overlay serializer).
        validateCollapse ctx obj
        Right (imports, entities, stubs)
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                topLevelLine
                ("top-level YAML must be an object, got: " <> typeName other)

{- | Walk a parsed list with its parallel source-line list, calling
@k@ with each element's 1-based line number. Missing line entries
fall back to 'topLevelLine'.

The pre-scan of @- name:@ lines is best-effort: if it produces
fewer lines than there are entities (e.g. an exotic indented form
the scanner doesn't match), the extras fall back to 'topLevelLine'
so the traversal still terminates.
-}
traverseWithLines ::
    (Int -> a -> Either RulesLoadError b) -> [a] -> [Int] -> Either RulesLoadError [b]
traverseWithLines _ [] _ = Right []
traverseWithLines k (x : xs) (ln : lns) = do
    y <- k ln x
    ys <- traverseWithLines k xs lns
    pure (y : ys)
traverseWithLines k (x : xs) [] = do
    y <- k topLevelLine x
    ys <- traverseWithLines k xs []
    pure (y : ys)

{- | Walk the top-level @imports:@ value (a list of relative file paths).
Returns @[]@ when the key is absent or null; surfaces a
'ParserError' for a non-list shape or a non-string entry. The
resolver applies its own absolute / HTTPS / missing-file checks
against the strings returned here.
-}
parseImportsKey ::
    Ctx -> KeyMap.KeyMap Aeson.Value -> Either RulesLoadError [Text]
parseImportsKey ctx obj = case KeyMap.lookup (Key.fromText "imports") obj of
    Nothing -> Right []
    Just Aeson.Null -> Right []
    Just (Aeson.Array arr) ->
        traverse (parseImportEntry ctx) (foldr (:) [] arr)
    Just other ->
        Left $
            ParserError
                (ctxFile ctx)
                topLevelLine
                ( "imports: must be a list of relative paths, got: "
                    <> typeName other
                )

parseImportEntry :: Ctx -> Aeson.Value -> Either RulesLoadError Text
parseImportEntry ctx = \case
    Aeson.String t -> Right t
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                topLevelLine
                ( "imports[]: entry must be a string path, got: "
                    <> typeName other
                )

{- | A 'blueprints:' entry distilled into the metadata the resolver
needs for its IO stage. Built by the pure YAML walker; consumed by
'Cardano.Tx.Graph.Rules.Load.Resolve.Imports.resolveImports'.

Each stub carries the rules.yaml path + 1-based source line of the
@- script:@ key so the IO stage can mint
'BlueprintFileMissing' / 'BlueprintParseError' diagnostics with
operator-friendly file:line provenance, the script entity's decoded
'ScriptHash' (used as the index key + for first-wins dedup), the
raw operator-authored @datum:@ path (preserved verbatim for error
messages and to drive the resolver's relative-path resolution
against the importer's directory), and the entity name (used by
the 'DuplicateBlueprintForScript' warning's payload).
-}
data BlueprintStub = BlueprintStub
    { stubRulesFile :: !FilePath
    -- ^ Absolute path of the rules.yaml that declared this blueprint.
    , stubLine :: !Int
    -- ^ 1-based source line of the @- script:@ key.
    , stubScriptName :: !Text
    -- ^ The operator-typed entity name (verbatim from @script:@).
    , stubScriptHash :: !ScriptHash
    -- ^ The decoded script hash for the referenced entity's
    -- @PaymentScript@ identifier — used as the
    -- 'rulesBlueprints' index key and the first-wins dedup key.
    , stubDatumRaw :: !Text
    -- ^ Raw @datum:@ path string the operator authored (relative
    -- to the rules.yaml's directory unless rejected by the
    -- absolute / @file://@ / @http(s)://@ policy check).
    }
    deriving stock (Eq, Show)

{- | Walk the top-level @blueprints:@ value (a list of objects) and
produce a 'BlueprintStub' per entry. Triggers:

* 'BlueprintRefsUnknownScript' on a dangling or non-script reference
  in the @script:@ field;
* 'AbsoluteBlueprintPath' on an absolute filesystem @datum:@ path or
  a @file://@ URI;
* 'HttpsBlueprintPath' on an @http(s)://@ URI in @datum:@;
* 'ParserError' on a structural shape error (non-list, non-object
  entry, missing @script:@ or @datum:@ field, non-string value).

The resolver's IO stage (see
'Cardano.Tx.Graph.Rules.Load.Resolve.Imports.resolveImports') is the
one that mints 'BlueprintFileMissing' / 'BlueprintParseError' once
each stub's @datum:@ file is actually read off disk.
-}
validateBlueprints ::
    Ctx ->
    [EntityDecl] ->
    KeyMap.KeyMap Aeson.Value ->
    Either RulesLoadError [BlueprintStub]
validateBlueprints ctx entities obj =
    case KeyMap.lookup (Key.fromText "blueprints") obj of
        Nothing -> Right []
        Just Aeson.Null -> Right []
        Just (Aeson.Array arr) ->
            walk (foldr (:) [] arr) (ctxBlueprintLines ctx)
        Just other ->
            Left $
                ParserError
                    (ctxFile ctx)
                    topLevelLine
                    ( "blueprints: must be a list, got: "
                        <> typeName other
                    )
  where
    walk [] _ = Right []
    walk (x : xs) (ln : lns) = do
        stub <- validateBlueprintEntry ctx ln entities x
        rest <- walk xs lns
        pure (stub : rest)
    walk (x : xs) [] = do
        stub <- validateBlueprintEntry ctx topLevelLine entities x
        rest <- walk xs []
        pure (stub : rest)

validateBlueprintEntry ::
    Ctx ->
    Int ->
    [EntityDecl] ->
    Aeson.Value ->
    Either RulesLoadError BlueprintStub
validateBlueprintEntry ctx ln entities = \case
    Aeson.Object o -> do
        refName <- requireScriptName ctx ln o
        scriptHash <-
            maybe
                (Left (BlueprintRefsUnknownScript (ctxFile ctx) ln refName))
                Right
                (lookupScriptHash entities refName)
        datumRaw <- requireDatumPath ctx ln o
        validateBlueprintDatumPath ctx ln datumRaw
        Right
            BlueprintStub
                { stubRulesFile = ctxFile ctx
                , stubLine = ln
                , stubScriptName = refName
                , stubScriptHash = scriptHash
                , stubDatumRaw = datumRaw
                }
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ( "blueprints[]: entry must be an object, got: "
                    <> typeName other
                )

requireScriptName ::
    Ctx -> Int -> KeyMap.KeyMap Aeson.Value -> Either RulesLoadError Text
requireScriptName ctx ln o = case KeyMap.lookup (Key.fromText "script") o of
    Nothing ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                "blueprints[]: entry is missing the 'script:' field"
    Just (Aeson.String t) -> Right t
    Just other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ( "blueprints[].script: must be a string, got: "
                    <> typeName other
                )

requireDatumPath ::
    Ctx -> Int -> KeyMap.KeyMap Aeson.Value -> Either RulesLoadError Text
requireDatumPath ctx ln o = case KeyMap.lookup (Key.fromText "datum") o of
    Nothing ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                "blueprints[]: entry is missing the 'datum:' field"
    Just (Aeson.String t) -> Right t
    Just other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ( "blueprints[].datum: must be a string path, got: "
                    <> typeName other
                )

{- | Enforce the filesystem-only / default-offline policy on a
@blueprints:@ entry's @datum: \<path\>@ string. Mirrors the
@owl:imports@ policy applied in
'Cardano.Tx.Graph.Rules.Load.Resolve.Imports.resolveChild': reject
@http(s)://@ as 'HttpsBlueprintPath', reject @file://@ and absolute
filesystem paths as 'AbsoluteBlueprintPath'. Relative paths fall
through to the IO stage which resolves them against the importer's
directory.
-}
validateBlueprintDatumPath ::
    Ctx -> Int -> Text -> Either RulesLoadError ()
validateBlueprintDatumPath ctx ln raw
    | Text.isPrefixOf "http://" raw || Text.isPrefixOf "https://" raw =
        Left (HttpsBlueprintPath (ctxFile ctx) ln raw)
    | Text.isPrefixOf "file://" raw =
        Left (AbsoluteBlueprintPath (ctxFile ctx) ln raw)
    | isAbsolute (Text.unpack raw) =
        Left (AbsoluteBlueprintPath (ctxFile ctx) ln raw)
    | otherwise = Right ()

{- | Find the script hash for an operator-typed entity name. Looks for
an entity whose 'entityName' matches @refName@ verbatim (not the
slug) and which carries a 'PaymentScript' identifier shape.

Decodes the identifier's lowercase hex bytes back into a 28-byte
'ScriptHash'. Returns 'Nothing' for a dangling reference, a
non-script entity, or the impossible case of a malformed hex
payload (the per-entity parser already validates the hex shape at
the @script:@ key, so the only realistic 'Nothing' path is the
unknown-name path).
-}
lookupScriptHash :: [EntityDecl] -> Text -> Maybe ScriptHash
lookupScriptHash entities refName = do
    EntityDecl{entityIdentifiers} <-
        find ((== refName) . entityName) entities
    EntityIdentifier{entityIdBytesHex} <-
        find ((== PaymentScript) . entityIdLeafType) entityIdentifiers
    bytes <-
        case Base16.decode (TextEncoding.encodeUtf8 entityIdBytesHex) of
            Right b | BS.length b == 28 -> Just b
            _ -> Nothing
    ScriptHash <$> hashFromBytes bytes
  where
    find p = foldr (\x acc -> if p x then Just x else acc) Nothing

{- | Walk the top-level @collapse:@ value. The view-collapse surface
is owned by #51; the loader only enforces the list shape so a
mistyped @collapse:@ value is caught at parse time rather than
silently swallowed.
-}
validateCollapse ::
    Ctx -> KeyMap.KeyMap Aeson.Value -> Either RulesLoadError ()
validateCollapse ctx obj =
    case KeyMap.lookup (Key.fromText "collapse") obj of
        Nothing -> Right ()
        Just Aeson.Null -> Right ()
        Just (Aeson.Array _) -> Right ()
        Just other ->
            Left $
                ParserError
                    (ctxFile ctx)
                    topLevelLine
                    ( "collapse: must be a list, got: "
                        <> typeName other
                    )

parseEntity ::
    Ctx -> Int -> Aeson.Value -> Either RulesLoadError EntityDecl
parseEntity ctx ln = \case
    Aeson.Object obj -> do
        name <- requireName ctx ln obj
        slug <- slugifyOrError ctx ln name
        (mBech32, idents) <- parseShape ctx ln slug obj
        Right
            EntityDecl
                { entityName = name
                , entitySlug = slug
                , entityIdentifiers = idents
                , entityBech32 = mBech32
                , entitySourceFile = ctxFile ctx
                }
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("entity entry must be an object, got: " <> typeName other)

requireName ::
    Ctx -> Int -> KeyMap.KeyMap Aeson.Value -> Either RulesLoadError Text
requireName ctx ln obj = case KeyMap.lookup (Key.fromText "name") obj of
    Just (Aeson.String t)
        | not (Text.null t) -> Right t
    Just other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("entity name: must be a non-empty string, got: " <> typeName other)
    Nothing ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                "entity is missing the required 'name:' field"

slugifyOrError :: Ctx -> Int -> Text -> Either RulesLoadError Text
slugifyOrError ctx ln name = do
    let s = slugify name
    if Text.null s
        then Left (EntityNameSlugEmpty (ctxFile ctx) ln name)
        else case Text.uncons s of
            Just (c, _)
                | isDigit c ->
                    Left (EntityNameSlugLeadingDigit (ctxFile ctx) ln name)
            _ -> Right s

{- | Pure slug algorithm: lowercase the input, rewrite every character
outside @[a-z0-9]@ to @_@, collapse runs of @_@, trim leading and
trailing @_@. Exported so future slices (Turtle serializer in T003,
overlap-detector in T005) can apply the same transform without an
import-cycle through 'parseRulesYamlText'.
-}
slugify :: Text -> Text
slugify =
    trimUnderscores
        . collapseUnderscores
        . Text.map normalizeChar
        . Text.toLower
  where
    normalizeChar c
        | isAsciiLower c || isDigit c = c
        | otherwise = '_'

collapseUnderscores :: Text -> Text
collapseUnderscores t =
    let (chunk, rest) = Text.span (== '_') t
     in case Text.uncons rest of
            Nothing
                | Text.null chunk -> Text.empty
                | otherwise -> Text.singleton '_'
            Just (_, _)
                | Text.null chunk -> takeNonUnderscore rest
                | otherwise -> Text.cons '_' (takeNonUnderscore rest)
  where
    takeNonUnderscore s =
        let (run, more) = Text.span (/= '_') s
         in run <> collapseUnderscores more

trimUnderscores :: Text -> Text
trimUnderscores = Text.dropAround (== '_')

----------------------------------------------------------------------
-- Shape dispatch
----------------------------------------------------------------------

{- | Pick the one identifier shape present in an entity's keymap.

Five basic shapes — @from-address@, @script@, @asset@, @pool@,
@drep@ — and one compound shape — @keys: + bytes:@ — are accepted.

* Exactly one basic shape and no compound keys → dispatch to
  'parseSingleShape'.
* @keys:@ and @bytes:@ together and no basic shape → dispatch to
  'parseCompoundKey' (yields N identifiers sharing the @bytes:@
  payload, one per @keys:@ leafType).
* Zero shapes (no basic key and no compound key) →
  'EntityZeroIdentifiers'.
* Any other combination — multiple basic shapes, basic + compound mix,
  orphan @keys:@ without @bytes:@, orphan @bytes:@ without @keys:@ —
  → 'ParserError'.
-}
parseShape ::
    Ctx ->
    Int ->
    Text ->
    KeyMap.KeyMap Aeson.Value ->
    Either RulesLoadError (Maybe Text, [EntityIdentifier])
parseShape ctx ln slug obj =
    let basicShapes =
            catMaybes
                [ ("from-address",) <$> KeyMap.lookup (Key.fromText "from-address") obj
                , ("script",) <$> KeyMap.lookup (Key.fromText "script") obj
                , ("asset",) <$> KeyMap.lookup (Key.fromText "asset") obj
                , ("pool",) <$> KeyMap.lookup (Key.fromText "pool") obj
                , ("drep",) <$> KeyMap.lookup (Key.fromText "drep") obj
                ]
        mKeys = KeyMap.lookup (Key.fromText "keys") obj
        mBytes = KeyMap.lookup (Key.fromText "bytes") obj
     in case (basicShapes, mKeys, mBytes) of
            ([], Nothing, Nothing) ->
                Left (EntityZeroIdentifiers (ctxFile ctx) ln slug)
            ([(k, v)], Nothing, Nothing) -> parseSingleShape ctx ln slug k v
            ([], Just keysV, Just bytesV) -> do
                idents <- parseCompoundKey ctx ln slug keysV bytesV
                Right (Nothing, idents)
            ([], Just _, Nothing) ->
                Left $
                    ParserError
                        (ctxFile ctx)
                        ln
                        ( "entity "
                            <> slug
                            <> " declares 'keys:' without 'bytes:'"
                        )
            ([], Nothing, Just _) ->
                Left $
                    ParserError
                        (ctxFile ctx)
                        ln
                        ( "entity "
                            <> slug
                            <> " declares 'bytes:' without 'keys:'"
                        )
            (many, mK, mB) ->
                let labels =
                        map fst many
                            <> ["keys" | Just _ <- [mK]]
                            <> ["bytes" | Just _ <- [mB]]
                 in Left $
                        ParserError
                            (ctxFile ctx)
                            ln
                            ( "entity "
                                <> slug
                                <> " declares multiple identifier shapes: "
                                <> Text.intercalate ", " labels
                            )

{- | Parse a single-shape entity. Returns the entity's identifiers
plus a 'Just' bech32 for the @from-address@ shape (so the
overlay emitter can publish a @cardano:bech32@ triple on the
entity node, issue #100) or 'Nothing' for the other shapes.
-}
parseSingleShape ::
    Ctx ->
    Int ->
    Text ->
    Text ->
    Aeson.Value ->
    Either RulesLoadError (Maybe Text, [EntityIdentifier])
parseSingleShape ctx ln _slug "from-address" v = case v of
    Aeson.String bech32 -> do
        idents <- decomposeFromAddress (ctxFile ctx) ln bech32
        Right (Just bech32, idents)
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("from-address: must be a bech32 string, got: " <> typeName other)
parseSingleShape ctx ln _slug "script" v = case v of
    Aeson.String hex -> do
        validated <- validateScriptHex ctx ln hex
        Right (Nothing, [EntityIdentifier PaymentScript validated])
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("script: must be a 56-character hex string, got: " <> typeName other)
parseSingleShape ctx ln _slug "asset" v = do
    idents <- parseAsset ctx ln v
    Right (Nothing, idents)
parseSingleShape ctx ln _slug "pool" v = case v of
    Aeson.String bech32 -> do
        idents <- decodePoolBech32 (ctxFile ctx) ln bech32
        Right (Nothing, idents)
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("pool: must be a pool1 bech32 string, got: " <> typeName other)
parseSingleShape ctx ln _slug "drep" v = case v of
    Aeson.String bech32 -> do
        idents <- decodeDrepCip129 (ctxFile ctx) ln bech32
        Right (Nothing, idents)
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("drep: must be a CIP-129 bech32 string, got: " <> typeName other)
parseSingleShape ctx ln _ k _ =
    Left $
        ParserError
            (ctxFile ctx)
            ln
            ("unknown identifier shape key: " <> k)

parseAsset ::
    Ctx -> Int -> Aeson.Value -> Either RulesLoadError [EntityIdentifier]
parseAsset ctx ln = \case
    Aeson.Object o -> do
        policyVal <-
            requireField
                ctx
                ln
                o
                "policy"
                "asset.policy: must be a 56-char hex string"
        nameVal <-
            requireField
                ctx
                ln
                o
                "name"
                "asset.name: must be an ASCII string"
        policy <- case policyVal of
            Aeson.String t -> validatePolicyHex ctx ln t
            other ->
                Left $
                    ParserError
                        (ctxFile ctx)
                        ln
                        ("asset.policy: must be a string, got: " <> typeName other)
        name <- case nameVal of
            Aeson.String t -> Right t
            other ->
                Left $
                    ParserError
                        (ctxFile ctx)
                        ln
                        ("asset.name: must be a string, got: " <> typeName other)
        let nameHex =
                TextEncoding.decodeUtf8
                    (Base16.encode (TextEncoding.encodeUtf8 name))
        Right [EntityIdentifier AssetClass (policy <> nameHex)]
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("asset: must be an object with 'policy' and 'name', got: " <> typeName other)

requireField ::
    Ctx ->
    Int ->
    KeyMap.KeyMap Aeson.Value ->
    Text ->
    Text ->
    Either RulesLoadError Aeson.Value
requireField ctx ln obj fieldName missingMsg =
    case KeyMap.lookup (Key.fromText fieldName) obj of
        Just v -> Right v
        Nothing -> Left (ParserError (ctxFile ctx) ln missingMsg)

{- | Parse the compound-key shape (@keys: [LeafType, …] + bytes: \<hex\>@).
Produces N 'EntityIdentifier' values, one per leafType in the
@keys:@ list, all sharing the validated 28-byte @bytes:@ payload.
The cross-leaf identity surface is owned downstream by the naming
table (first-entity-wins on @(leafType, bytesHex)@).
-}
parseCompoundKey ::
    Ctx ->
    Int ->
    Text ->
    Aeson.Value ->
    Aeson.Value ->
    Either RulesLoadError [EntityIdentifier]
parseCompoundKey ctx ln slug keysV bytesV = do
    leaves <- parseKeysList ctx ln slug keysV
    bytesHex <- case bytesV of
        Aeson.String t -> validateHash28 ctx ln t BadPolicyHex
        other ->
            Left $
                ParserError
                    (ctxFile ctx)
                    ln
                    ("bytes: must be a 56-char hex string, got: " <> typeName other)
    Right [EntityIdentifier lt bytesHex | lt <- leaves]

{- | Parse the @keys:@ list value as a non-empty list of 'LeafType'
constructor names. Surfaces a 'ParserError' on an empty list, a
non-array value, or any unknown leafType label.
-}
parseKeysList ::
    Ctx ->
    Int ->
    Text ->
    Aeson.Value ->
    Either RulesLoadError [LeafType]
parseKeysList ctx ln slug = \case
    Aeson.Array arr ->
        case foldr (:) [] arr of
            [] ->
                Left $
                    ParserError
                        (ctxFile ctx)
                        ln
                        ( "entity "
                            <> slug
                            <> " declares an empty 'keys:' list"
                        )
            xs -> traverse (parseLeafTypeValue ctx ln) xs
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("keys: must be a list of leafType names, got: " <> typeName other)

parseLeafTypeValue ::
    Ctx -> Int -> Aeson.Value -> Either RulesLoadError LeafType
parseLeafTypeValue ctx ln = \case
    Aeson.String t -> case parseLeafType t of
        Just lt -> Right lt
        Nothing ->
            Left $
                ParserError
                    (ctxFile ctx)
                    ln
                    ("keys: unknown leafType label: " <> t)
    other ->
        Left $
            ParserError
                (ctxFile ctx)
                ln
                ("keys: leafType must be a string, got: " <> typeName other)

-- | Reverse of @show@ for 'LeafType'. Pinned by spec FR-013.
parseLeafType :: Text -> Maybe LeafType
parseLeafType = \case
    "PaymentKey" -> Just PaymentKey
    "PaymentScript" -> Just PaymentScript
    "StakeKey" -> Just StakeKey
    "StakeScript" -> Just StakeScript
    "AssetClass" -> Just AssetClass
    "Policy" -> Just Policy
    "PoolId" -> Just PoolId
    "DRepKey" -> Just DRepKey
    "DRepScript" -> Just DRepScript
    _ -> Nothing

{- | Validate a 56-char hex value used in a @script:@ shape.
Reuses 'BadPolicyHex' for the error variant — both @script:@ and
@asset.policy:@ carry a 28-byte hex hash with identical
validation semantics, and the spec's error enum currently lists
only the policy variant.
-}
validateScriptHex :: Ctx -> Int -> Text -> Either RulesLoadError Text
validateScriptHex ctx ln hex = validateHash28 ctx ln hex BadPolicyHex

-- | Validate a 56-char hex value used as an @asset.policy:@ value.
validatePolicyHex :: Ctx -> Int -> Text -> Either RulesLoadError Text
validatePolicyHex ctx ln hex = validateHash28 ctx ln hex BadPolicyHex

validateHash28 ::
    Ctx ->
    Int ->
    Text ->
    (FilePath -> Int -> Text -> RulesLoadError) ->
    Either RulesLoadError Text
validateHash28 ctx ln hex mkErr =
    let lowered = Text.toLower hex
     in if Text.length lowered /= 56
            then Left (mkErr (ctxFile ctx) ln hex)
            else case Base16.decode (TextEncoding.encodeUtf8 lowered) of
                Right bs | BS.length bs == 28 -> Right lowered
                _ -> Left (mkErr (ctxFile ctx) ln hex)

typeName :: Aeson.Value -> Text
typeName = \case
    Aeson.Null -> "null"
    Aeson.Bool _ -> "boolean"
    Aeson.Number _ -> "number"
    Aeson.String _ -> "string"
    Aeson.Array _ -> "array"
    Aeson.Object _ -> "object"

----------------------------------------------------------------------
-- Source-line pre-scan
----------------------------------------------------------------------

{- | Pre-scan the raw byte blob and return the 1-based source line of
each entity's @- name:@ key (in source order).

The scan matches lines whose first non-space character is @-@
followed by a key whose unquoted first identifier is @name@:

@
  - name: alice
@

Lines whose @- @ prefix is followed by a different key (e.g.
@- script:@ under @blueprints:@) are ignored. Lines whose @name:@
appears without a leading @- @ (continuation @name:@ inside a flow
mapping, for instance) are also ignored — only the list-element
introducer counts.

The scanner is a heuristic. If it returns fewer entries than the
parser sees in the decoded 'Aeson.Value', the parser falls back to
'topLevelLine' for the trailing entities (see 'traverseWithLines').
This keeps the loader total under exotic authoring forms.
-}
entityNameLines :: ByteString -> [Int]
entityNameLines = lineIndicesMatchingDashKey "name"

{- | Sibling of 'entityNameLines' for blueprint entries: returns the
1-based source line of each blueprint's @- script:@ key.
-}
blueprintScriptLines :: ByteString -> [Int]
blueprintScriptLines = lineIndicesMatchingDashKey "script"

{- | Scan a raw YAML byte blob for lines whose leading non-space content
is @- <key>:@ with the supplied key name. Returns the 1-based source
line of each match in source order.
-}
lineIndicesMatchingDashKey :: Text -> ByteString -> [Int]
lineIndicesMatchingDashKey key blob =
    [ ln
    | (ln, line) <- zip [1 ..] (Text.lines text)
    , matchesDashKey key line
    ]
  where
    text = TextEncoding.decodeUtf8With lenientDecode blob

{- | True iff @line@'s first non-space content is @- <key>:@ (with
optional space between @-@ and the key, and any value after the
colon).
-}
matchesDashKey :: Text -> Text -> Bool
matchesDashKey key line =
    case Text.uncons (Text.stripStart line) of
        Just ('-', afterDash) ->
            let body = Text.stripStart afterDash
                (head_, rest) = Text.break (== ':') body
             in head_ == key && not (Text.null rest)
        _ -> False

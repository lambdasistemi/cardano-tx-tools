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

@imports:@, @blueprints:@, and @collapse:@ keys are ignored for now —
the loader returns just the entity list and lets later slices wire
them in.

The slug algorithm:

* lowercase the @name:@ field;
* rewrite every character outside @[a-z0-9]@ to @_@;
* collapse runs of @_@ into a single @_@;
* trim leading and trailing @_@.

An empty slug or a slug that starts with a digit is rejected with
'EntityNameSlugEmpty' / 'EntityNameSlugLeadingDigit'. (Turtle's
PN_LOCAL allows leading digits, but bnode local-parts like @_:0foo@
are stylistically ambiguous — see spec edge cases.)
-}
module Cardano.Tx.Graph.Rules.Load.Parse.Yaml (
    parseRulesYamlText,
    slugify,
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
import Data.Yaml qualified as Yaml

{- | The placeholder file path attached to T002 error variants. T003
threads the real file path through when @loadRulesFile@ runs.
-}
inMemoryFile :: FilePath
inMemoryFile = "<in-memory>"

{- | The placeholder line number attached to T002 error variants. T009
tightens the surface to real line numbers from the YAML parser.
-}
inMemoryLine :: Int
inMemoryLine = 0

{- | Parse a @rules.yaml@ byte blob into the in-memory entity list.

Returns @Right []@ for an empty document or one lacking an @entities:@
key (composition via @imports:@ is a later slice). Otherwise walks
each @entities:@ entry, computes its slug, dispatches on the
@from-address@ / @script@ / @asset@ shape, and produces one or more
'EntityIdentifier' values per entity.

Any structural failure (invalid YAML, non-string name, malformed
bech32, bad hex) surfaces as a 'RulesLoadError' via 'Left'.
-}
parseRulesYamlText :: ByteString -> Either RulesLoadError [EntityDecl]
parseRulesYamlText blob =
    case Yaml.decodeEither' blob of
        Left err ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    (Text.pack ("YAML decode failed: " <> show err))
        Right val -> walkTop val

walkTop :: Aeson.Value -> Either RulesLoadError [EntityDecl]
walkTop = \case
    Aeson.Null -> Right []
    Aeson.Object obj ->
        case KeyMap.lookup (Key.fromText "entities") obj of
            Nothing -> Right []
            Just Aeson.Null -> Right []
            Just (Aeson.Array arr) ->
                traverse parseEntity (foldr (:) [] arr)
            Just other ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
                        ( "entities: must be a list, got: "
                            <> typeName other
                        )
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("top-level YAML must be an object, got: " <> typeName other)

parseEntity :: Aeson.Value -> Either RulesLoadError EntityDecl
parseEntity = \case
    Aeson.Object obj -> do
        name <- requireName obj
        slug <- slugifyOrError name
        idents <- parseShape slug obj
        Right
            EntityDecl
                { entityName = name
                , entitySlug = slug
                , entityIdentifiers = idents
                }
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("entity entry must be an object, got: " <> typeName other)

requireName :: KeyMap.KeyMap Aeson.Value -> Either RulesLoadError Text
requireName obj = case KeyMap.lookup (Key.fromText "name") obj of
    Just (Aeson.String t)
        | not (Text.null t) -> Right t
    Just other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("entity name: must be a non-empty string, got: " <> typeName other)
    Nothing ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                "entity is missing the required 'name:' field"

slugifyOrError :: Text -> Either RulesLoadError Text
slugifyOrError name = do
    let s = slugify name
    if Text.null s
        then Left (EntityNameSlugEmpty inMemoryFile inMemoryLine name)
        else case Text.uncons s of
            Just (c, _) | isDigit c -> Left (EntityNameSlugLeadingDigit inMemoryFile inMemoryLine name)
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
    Text -> KeyMap.KeyMap Aeson.Value -> Either RulesLoadError [EntityIdentifier]
parseShape slug obj =
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
            ([], Nothing, Nothing) -> Left (EntityZeroIdentifiers slug)
            ([(k, v)], Nothing, Nothing) -> parseSingleShape slug k v
            ([], Just keysV, Just bytesV) ->
                parseCompoundKey slug keysV bytesV
            ([], Just _, Nothing) ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
                        ( "entity "
                            <> slug
                            <> " declares 'keys:' without 'bytes:'"
                        )
            ([], Nothing, Just _) ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
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
                            inMemoryFile
                            inMemoryLine
                            ( "entity "
                                <> slug
                                <> " declares multiple identifier shapes: "
                                <> Text.intercalate ", " labels
                            )

parseSingleShape ::
    Text -> Text -> Aeson.Value -> Either RulesLoadError [EntityIdentifier]
parseSingleShape _slug "from-address" v = case v of
    Aeson.String bech32 ->
        decomposeFromAddress inMemoryFile inMemoryLine bech32
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("from-address: must be a bech32 string, got: " <> typeName other)
parseSingleShape _slug "script" v = case v of
    Aeson.String hex -> do
        validated <- validateScriptHex hex
        Right [EntityIdentifier PaymentScript validated]
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("script: must be a 56-character hex string, got: " <> typeName other)
parseSingleShape _slug "asset" v = parseAsset v
parseSingleShape _slug "pool" v = case v of
    Aeson.String bech32 -> decodePoolBech32 inMemoryFile inMemoryLine bech32
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("pool: must be a pool1 bech32 string, got: " <> typeName other)
parseSingleShape _slug "drep" v = case v of
    Aeson.String bech32 -> decodeDrepCip129 inMemoryFile inMemoryLine bech32
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("drep: must be a CIP-129 bech32 string, got: " <> typeName other)
parseSingleShape _ k _ =
    Left $
        ParserError
            inMemoryFile
            inMemoryLine
            ("unknown identifier shape key: " <> k)

parseAsset :: Aeson.Value -> Either RulesLoadError [EntityIdentifier]
parseAsset = \case
    Aeson.Object o -> do
        policyVal <-
            requireField o "policy" "asset.policy: must be a 56-char hex string"
        nameVal <-
            requireField o "name" "asset.name: must be an ASCII string"
        policy <- case policyVal of
            Aeson.String t -> validatePolicyHex t
            other ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
                        ("asset.policy: must be a string, got: " <> typeName other)
        name <- case nameVal of
            Aeson.String t -> Right t
            other ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
                        ("asset.name: must be a string, got: " <> typeName other)
        let nameHex =
                TextEncoding.decodeUtf8
                    (Base16.encode (TextEncoding.encodeUtf8 name))
        Right [EntityIdentifier AssetClass (policy <> nameHex)]
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("asset: must be an object with 'policy' and 'name', got: " <> typeName other)

requireField ::
    KeyMap.KeyMap Aeson.Value ->
    Text ->
    Text ->
    Either RulesLoadError Aeson.Value
requireField obj fieldName missingMsg =
    case KeyMap.lookup (Key.fromText fieldName) obj of
        Just v -> Right v
        Nothing -> Left (ParserError inMemoryFile inMemoryLine missingMsg)

{- | Parse the compound-key shape (@keys: [LeafType, …] + bytes: \<hex\>@).
Produces N 'EntityIdentifier' values, one per leafType in the
@keys:@ list, all sharing the validated 28-byte @bytes:@ payload.
The cross-leaf identity surface is owned downstream by the naming
table (first-entity-wins on @(leafType, bytesHex)@).
-}
parseCompoundKey ::
    Text ->
    Aeson.Value ->
    Aeson.Value ->
    Either RulesLoadError [EntityIdentifier]
parseCompoundKey slug keysV bytesV = do
    leaves <- parseKeysList slug keysV
    bytesHex <- case bytesV of
        Aeson.String t -> validateHash28 t BadPolicyHex
        other ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    ("bytes: must be a 56-char hex string, got: " <> typeName other)
    Right [EntityIdentifier lt bytesHex | lt <- leaves]

{- | Parse the @keys:@ list value as a non-empty list of 'LeafType'
constructor names. Surfaces a 'ParserError' on an empty list, a
non-array value, or any unknown leafType label.
-}
parseKeysList ::
    Text -> Aeson.Value -> Either RulesLoadError [LeafType]
parseKeysList slug = \case
    Aeson.Array arr ->
        case foldr (:) [] arr of
            [] ->
                Left $
                    ParserError
                        inMemoryFile
                        inMemoryLine
                        ( "entity "
                            <> slug
                            <> " declares an empty 'keys:' list"
                        )
            xs -> traverse parseLeafTypeValue xs
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
                ("keys: must be a list of leafType names, got: " <> typeName other)

parseLeafTypeValue :: Aeson.Value -> Either RulesLoadError LeafType
parseLeafTypeValue = \case
    Aeson.String t -> case parseLeafType t of
        Just lt -> Right lt
        Nothing ->
            Left $
                ParserError
                    inMemoryFile
                    inMemoryLine
                    ("keys: unknown leafType label: " <> t)
    other ->
        Left $
            ParserError
                inMemoryFile
                inMemoryLine
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
validateScriptHex :: Text -> Either RulesLoadError Text
validateScriptHex hex = validateHash28 hex BadPolicyHex

-- | Validate a 56-char hex value used as an @asset.policy:@ value.
validatePolicyHex :: Text -> Either RulesLoadError Text
validatePolicyHex hex = validateHash28 hex BadPolicyHex

validateHash28 ::
    Text ->
    (FilePath -> Int -> Text -> RulesLoadError) ->
    Either RulesLoadError Text
validateHash28 hex mkErr =
    let lowered = Text.toLower hex
     in if Text.length lowered /= 56
            then Left (mkErr inMemoryFile inMemoryLine hex)
            else case Base16.decode (TextEncoding.encodeUtf8 lowered) of
                Right bs | BS.length bs == 28 -> Right lowered
                _ -> Left (mkErr inMemoryFile inMemoryLine hex)

typeName :: Aeson.Value -> Text
typeName = \case
    Aeson.Null -> "null"
    Aeson.Bool _ -> "boolean"
    Aeson.Number _ -> "number"
    Aeson.String _ -> "string"
    Aeson.Array _ -> "array"
    Aeson.Object _ -> "object"

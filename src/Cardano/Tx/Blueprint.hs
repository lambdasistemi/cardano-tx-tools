{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.Tx.Blueprint
Description : Plutus blueprint parsing for transaction diffs.

This module parses the CIP-0057 subset needed by the TxDiff blueprint
boundary: validators, datum and redeemer argument schemas, definitions, and
the Plutus data schema forms needed to name constructor fields.
-}
module Cardano.Tx.Blueprint (
    Blueprint (..),
    BlueprintArgument (..),
    BlueprintArgumentKind (..),
    BlueprintArgumentSelector (..),
    BlueprintDataError (..),
    BlueprintDiff (..),
    BlueprintFallbackReason (..),
    BlueprintMatchError (..),
    BlueprintPreamble (..),
    BlueprintSchema (..),
    BlueprintSchemaKind (..),
    BlueprintValidator (..),
    blueprintDataDecoder,
    decodeBlueprintData,
    decodeBlueprintDataWith,
    diffBlueprintArgumentData,
    diffBlueprintData,
    matchBlueprintArgument,
    parseBlueprintJSON,
    resolveBlueprintSchema,
) where

import Data.Aeson (
    FromJSON (..),
    Object,
    eitherDecode,
    withObject,
    (.:),
    (.:?),
    (.=),
 )
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser, parseEither, (.!=))
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding

import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerLow)
import Cardano.Tx.Diff (
    DiffChange (..),
    DiffNode (..),
    DiffPath (..),
    OpenValue (..),
    TxDiffDataKind (..),
    TxDiffDataSelector (..),
    diffOpenValue,
 )
import PlutusCore.Data qualified as PLC

data Blueprint = Blueprint
    { blueprintPreamble :: BlueprintPreamble
    , blueprintValidators :: [BlueprintValidator]
    , blueprintDefinitions :: Map Text BlueprintSchema
    }
    deriving stock (Eq, Show)

data BlueprintPreamble = BlueprintPreamble
    { preambleTitle :: Text
    , preamblePlutusVersion :: Text
    }
    deriving stock (Eq, Show)

data BlueprintValidator = BlueprintValidator
    { validatorTitle :: Maybe Text
    , validatorDatum :: Maybe BlueprintArgument
    , validatorRedeemer :: Maybe BlueprintArgument
    }
    deriving stock (Eq, Show)

data BlueprintArgument = BlueprintArgument
    { argumentTitle :: Maybe Text
    , argumentSchema :: BlueprintSchema
    }
    deriving stock (Eq, Show)

data BlueprintArgumentKind
    = BlueprintDatum
    | BlueprintRedeemer
    deriving stock (Eq, Show)

data BlueprintArgumentSelector = BlueprintArgumentSelector
    { selectorValidatorTitle :: Maybe Text
    , selectorArgumentKind :: BlueprintArgumentKind
    }
    deriving stock (Eq, Show)

data BlueprintMatchError
    = BlueprintArgumentMissing
    | BlueprintArgumentAmbiguous [Text]
    | BlueprintDefinitionMissing Text
    | BlueprintDefinitionCycle Text
    deriving stock (Eq, Show)

data BlueprintDiff
    = BlueprintDiffDecoded DiffNode
    | BlueprintDiffFallback BlueprintFallbackReason DiffNode
    deriving stock (Eq, Show)

data BlueprintFallbackReason
    = BlueprintMatchFallback BlueprintMatchError
    | BlueprintDataFallback BlueprintDataError
    deriving stock (Eq, Show)

data BlueprintDataError
    = BlueprintDataTypeMismatch Text
    | BlueprintConstructorMismatch
        { expectedConstructorIndex :: Integer
        , actualConstructorIndex :: Integer
        }
    | BlueprintFieldCountMismatch
        { expectedFieldCount :: Int
        , actualFieldCount :: Int
        }
    | BlueprintUnresolvedReference Text
    | -- | A @$ref@ resolved back to itself without consuming any
      -- 'Data' in between — a genuinely non-productive definition
      -- cycle, distinct from the (now-supported) recursion that
      -- unfolds only as deep as the finite on-chain 'Data'. Carries
      -- the offending definition name.
      BlueprintReferenceCycle Text
    deriving stock (Eq, Show)

data BlueprintSchema = BlueprintSchema
    { schemaTitle :: Maybe Text
    , schemaKind :: BlueprintSchemaKind
    }
    deriving stock (Eq, Show)

data BlueprintSchemaKind
    = SchemaInteger
    | SchemaBytes
    | SchemaConstructor Integer [BlueprintSchema]
    | SchemaAnyOf [BlueprintSchema]
    | SchemaList [BlueprintSchema]
    | SchemaListOf BlueprintSchema
    | -- | CIP-57 @"dataType": "map"@ — a Plutus 'PLC.Map' payload whose keys
      -- match the first sub-schema and values the second. Decodes as
      -- @OpenArray [OpenObject {"key" -> k, "value" -> v}, ...]@ so the
      -- typed-emit walker treats each entry as a named-field record.
      SchemaMap BlueprintSchema BlueprintSchema
    | SchemaData
    | SchemaReference Text
    deriving stock (Eq, Show)

parseBlueprintJSON :: LBS.ByteString -> Either String Blueprint
parseBlueprintJSON =
    eitherDecode

blueprintDataDecoder ::
    [Blueprint] -> TxDiffDataSelector -> Data ConwayEra -> Either Text OpenValue
blueprintDataDecoder blueprints selector =
    decodeMatchingBlueprintArgument
        blueprints
        (blueprintArgumentSelector selector)

decodeMatchingBlueprintArgument ::
    [Blueprint] ->
    BlueprintArgumentSelector ->
    Data ConwayEra ->
    Either Text OpenValue
decodeMatchingBlueprintArgument blueprints selector datum =
    case matches of
        [] ->
            Left (Text.pack (show (BlueprintMatchFallback BlueprintArgumentMissing)))
        _ ->
            case decodedMatches of
                [(_, value)] ->
                    Right value
                [] ->
                    Left (Text.intercalate "; " failedMatches)
                multiple ->
                    Left $
                        Text.pack $
                            show $
                                BlueprintMatchFallback $
                                    BlueprintArgumentAmbiguous (map fst multiple)
  where
    matches =
        matchingArguments blueprints selector
    attempts =
        [ ( matchLabel blueprint validator
          , -- Resolve @$ref@s on demand against the blueprint's
            -- definitions while walking the (finite) 'Data', instead
            -- of eagerly unfolding the whole schema up front. A
            -- recursive definition (e.g. the SundaeSwap
            -- @MultisigScript@ cycle) then only unfolds as deep as the
            -- data actually goes, so finite payloads decode and a
            -- spurious 'BlueprintDefinitionCycle' is never raised
            -- before any data is consulted.
            case decodeBlueprintDataWith
                (blueprintDefinitions blueprint)
                (argumentSchema argument)
                datum of
                Left err ->
                    Left (Text.pack (show (BlueprintDataFallback err)))
                Right value ->
                    Right value
          )
        | (blueprint, validator, argument) <- matches
        ]
    decodedMatches =
        [ (label, value)
        | (label, Right value) <- attempts
        ]
    failedMatches =
        [ label <> ": " <> reason
        | (label, Left reason) <- attempts
        ]

blueprintArgumentSelector :: TxDiffDataSelector -> BlueprintArgumentSelector
blueprintArgumentSelector selector =
    BlueprintArgumentSelector
        { selectorValidatorTitle = txDiffDataValidatorTitle selector
        , selectorArgumentKind =
            txDiffBlueprintArgumentKind (txDiffDataKind selector)
        }

txDiffBlueprintArgumentKind :: TxDiffDataKind -> BlueprintArgumentKind
txDiffBlueprintArgumentKind TxDiffDatum =
    BlueprintDatum
txDiffBlueprintArgumentKind TxDiffRedeemer =
    BlueprintRedeemer

decodeBlueprintData ::
    BlueprintSchema -> Data ConwayEra -> Either BlueprintDataError OpenValue
decodeBlueprintData =
    decodeBlueprintDataWith Map.empty

{- | Like 'decodeBlueprintData', but carries the blueprint's
@definitions@ so a 'SchemaReference' encountered mid-walk is resolved
per-occurrence against the (finite) 'Data' rather than requiring a
fully pre-resolved schema. This is what lets a RECURSIVE definition
(the SundaeSwap @MultisigScript@ cycle) decode: the @$ref@ only
unfolds as deep as the data actually goes. A reference that resolves
back to itself with no 'Data' consumed in between still fails, with
'BlueprintReferenceCycle'.

'decodeBlueprintData' is the @definitions@-free wrapper kept for
callers that already pre-resolve their schema (e.g. the graph-emit
walker via 'resolveBlueprintSchema'); on a ref-free schema both
behave identically.
-}
decodeBlueprintDataWith ::
    Map Text BlueprintSchema ->
    BlueprintSchema ->
    Data ConwayEra ->
    Either BlueprintDataError OpenValue
decodeBlueprintDataWith definitions schema (Data value) =
    decodeBlueprintValue definitions Set.empty schema value

diffBlueprintData ::
    BlueprintSchema ->
    Data ConwayEra ->
    Data ConwayEra ->
    Either BlueprintDataError DiffNode
diffBlueprintData schema left right = do
    leftOpen <- decodeBlueprintData schema left
    rightOpen <- decodeBlueprintData schema right
    pure (diffOpenValue leftOpen rightOpen)

diffBlueprintArgumentData ::
    [Blueprint] ->
    BlueprintArgumentSelector ->
    Data ConwayEra ->
    Data ConwayEra ->
    BlueprintDiff
diffBlueprintArgumentData blueprints selector left right =
    case matchBlueprintArgument blueprints selector of
        Left err ->
            BlueprintDiffFallback
                (BlueprintMatchFallback err)
                (rawBlueprintDataDiff left right)
        Right schema ->
            case diffBlueprintData schema left right of
                Left err ->
                    BlueprintDiffFallback
                        (BlueprintDataFallback err)
                        (rawBlueprintDataDiff left right)
                Right diff ->
                    BlueprintDiffDecoded diff

rawBlueprintDataDiff :: Data ConwayEra -> Data ConwayEra -> DiffNode
rawBlueprintDataDiff left right
    | left == right =
        DiffNode
            (DiffPath [])
            (DiffSame (Just (rawBlueprintDataValue left)))
    | otherwise =
        DiffNode
            (DiffPath [])
            ( DiffChanged
                (rawBlueprintDataValue left)
                (rawBlueprintDataValue right)
            )

rawBlueprintDataValue :: Data ConwayEra -> Aeson.Value
rawBlueprintDataValue datum =
    Aeson.object
        [ "cbor" .= hexText (serialize' (eraProtVerLow @ConwayEra) datum)
        ]

{- | Walk a 'PLC.Data' value against a schema, resolving any
'SchemaReference' on demand against @definitions@ as it is reached.

@seen@ tracks the references followed since the last 'Data' node was
consumed; it is the cycle guard. Following a reference adds it to
@seen@ and recurses on the SAME 'Data' value, so a definition that
resolves back to itself with no data progress (e.g. @A -> $ref A@)
is caught and reported as 'BlueprintReferenceCycle'. Whenever a
structural node ('PLC.Constr' / 'PLC.List' / 'PLC.Map') is matched and
we descend into its (strictly smaller) children, @seen@ is reset to
empty — a recursive definition therefore unfolds only as deep as the
finite data actually goes. @anyOf@ does not consume data, so it
threads @seen@ through unchanged.
-}
decodeBlueprintValue ::
    Map Text BlueprintSchema ->
    Set.Set Text ->
    BlueprintSchema ->
    PLC.Data ->
    Either BlueprintDataError OpenValue
decodeBlueprintValue definitions seen schema value =
    case schemaKind schema of
        SchemaInteger ->
            case value of
                PLC.I integer ->
                    Right (OpenInteger integer)
                _ ->
                    Left (BlueprintDataTypeMismatch "integer")
        SchemaBytes ->
            case value of
                PLC.B bytes ->
                    Right (OpenBytes (hexText bytes))
                _ ->
                    Left (BlueprintDataTypeMismatch "bytes")
        SchemaConstructor expectedIndex fields ->
            case value of
                PLC.Constr actualIndex values
                    | actualIndex /= expectedIndex ->
                        Left
                            BlueprintConstructorMismatch
                                { expectedConstructorIndex = expectedIndex
                                , actualConstructorIndex = actualIndex
                                }
                    | length fields /= length values ->
                        Left
                            BlueprintFieldCountMismatch
                                { expectedFieldCount = length fields
                                , actualFieldCount = length values
                                }
                    | otherwise ->
                        OpenObject . Map.fromList
                            <$> traverse
                                decodeField
                                (zip [0 :: Int ..] (zip fields values))
                _ ->
                    Left (BlueprintDataTypeMismatch "constructor")
        SchemaAnyOf alternatives ->
            decodeAnyOf definitions seen alternatives value
        SchemaList fields ->
            case value of
                PLC.List values
                    | length fields /= length values ->
                        Left
                            BlueprintFieldCountMismatch
                                { expectedFieldCount = length fields
                                , actualFieldCount = length values
                                }
                    | otherwise ->
                        OpenArray
                            <$> traverse
                                (uncurry decodeChild)
                                (zip fields values)
                _ ->
                    Left (BlueprintDataTypeMismatch "list")
        SchemaListOf item ->
            case value of
                PLC.List values ->
                    OpenArray <$> traverse (decodeChild item) values
                _ ->
                    Left (BlueprintDataTypeMismatch "list")
        SchemaMap keySchema valueSchema ->
            case value of
                PLC.Map entries ->
                    OpenArray
                        <$> traverse (decodeMapEntry keySchema valueSchema) entries
                _ ->
                    Left (BlueprintDataTypeMismatch "map")
        SchemaData ->
            Right (plutusDataOpenValue value)
        SchemaReference reference
            | reference `Set.member` seen ->
                Left (BlueprintReferenceCycle reference)
            | otherwise ->
                case Map.lookup reference definitions of
                    Nothing ->
                        Left (BlueprintUnresolvedReference reference)
                    Just definition ->
                        -- Keep the outer field title (e.g. @"owner"@)
                        -- when following the @$ref@, mirroring
                        -- 'resolveBlueprintSchema'.
                        let inheritedTitle =
                                case schemaTitle schema of
                                    Just _ -> schemaTitle schema
                                    Nothing -> schemaTitle definition
                            titled =
                                definition{schemaTitle = inheritedTitle}
                         in decodeBlueprintValue
                                definitions
                                (Set.insert reference seen)
                                titled
                                value
  where
    -- A child of a matched 'Data' node: the cycle guard resets
    -- because the data has progressed to a strictly smaller value.
    decodeChild = decodeBlueprintValue definitions Set.empty
    decodeField (index, (fieldSchema, fieldValue)) = do
        decodedValue <- decodeChild fieldSchema fieldValue
        pure (fieldName index fieldSchema, decodedValue)
    decodeMapEntry kSchema vSchema (k, v) = do
        decodedKey <- decodeChild kSchema k
        decodedValue <- decodeChild vSchema v
        pure $
            OpenObject $
                Map.fromList
                    [ ("key", decodedKey)
                    , ("value", decodedValue)
                    ]

decodeAnyOf ::
    Map Text BlueprintSchema ->
    Set.Set Text ->
    [BlueprintSchema] ->
    PLC.Data ->
    Either BlueprintDataError OpenValue
decodeAnyOf definitions seen alternatives value =
    case successes of
        [decoded] ->
            Right decoded
        [] ->
            case alternatives of
                firstAlternative : _ ->
                    decodeBlueprintValue definitions seen firstAlternative value
                [] ->
                    Left (BlueprintDataTypeMismatch "anyOf")
        _ ->
            Left (BlueprintDataTypeMismatch "ambiguous anyOf")
  where
    successes =
        [ decoded
        | alternative <- alternatives
        , Right decoded <-
            [decodeBlueprintValue definitions seen alternative value]
        ]

plutusDataOpenValue :: PLC.Data -> OpenValue
plutusDataOpenValue (PLC.I integer) =
    OpenInteger integer
plutusDataOpenValue (PLC.B bytes) =
    OpenBytes (hexText bytes)
plutusDataOpenValue (PLC.List values) =
    OpenArray (map plutusDataOpenValue values)
plutusDataOpenValue (PLC.Map entries) =
    OpenArray
        [ OpenObject $
            Map.fromList
                [ ("key", plutusDataOpenValue key)
                , ("value", plutusDataOpenValue itemValue)
                ]
        | (key, itemValue) <- entries
        ]
plutusDataOpenValue (PLC.Constr index fields) =
    OpenObject $
        Map.fromList
            [ ("constructor", OpenInteger index)
            , ("fields", OpenArray (map plutusDataOpenValue fields))
            ]

fieldName :: Int -> BlueprintSchema -> Text
fieldName index schema =
    case schemaTitle schema of
        Just title ->
            title
        Nothing ->
            "field" <> Text.pack (show index)

hexText :: BS.ByteString -> Text
hexText =
    TextEncoding.decodeUtf8 . Base16.encode

matchBlueprintArgument ::
    [Blueprint] ->
    BlueprintArgumentSelector ->
    Either BlueprintMatchError BlueprintSchema
matchBlueprintArgument blueprints selector =
    case matchingArguments blueprints selector of
        [] ->
            Left BlueprintArgumentMissing
        [(blueprint, _, argument)] ->
            resolveBlueprintSchema blueprint (argumentSchema argument)
        matches ->
            Left $
                BlueprintArgumentAmbiguous
                    [ matchLabel blueprint validator
                    | (blueprint, validator, _) <- matches
                    ]

matchingArguments ::
    [Blueprint] ->
    BlueprintArgumentSelector ->
    [(Blueprint, BlueprintValidator, BlueprintArgument)]
matchingArguments blueprints selector =
    [ (blueprint, validator, argument)
    | blueprint <- blueprints
    , validator <- blueprintValidators blueprint
    , validatorMatches selector validator
    , Just argument <- [selectedArgument selector validator]
    ]

validatorMatches ::
    BlueprintArgumentSelector -> BlueprintValidator -> Bool
validatorMatches selector validator =
    case selectorValidatorTitle selector of
        Nothing ->
            True
        Just title ->
            validatorTitle validator == Just title

selectedArgument ::
    BlueprintArgumentSelector -> BlueprintValidator -> Maybe BlueprintArgument
selectedArgument selector =
    case selectorArgumentKind selector of
        BlueprintDatum ->
            validatorDatum
        BlueprintRedeemer ->
            validatorRedeemer

matchLabel :: Blueprint -> BlueprintValidator -> Text
matchLabel blueprint validator =
    case validatorTitle validator of
        Just title ->
            title
        Nothing ->
            preambleTitle (blueprintPreamble blueprint)

resolveBlueprintSchema ::
    Blueprint -> BlueprintSchema -> Either BlueprintMatchError BlueprintSchema
resolveBlueprintSchema blueprint =
    go Set.empty
  where
    go seen schema =
        case schemaKind schema of
            SchemaReference reference
                | reference `Set.member` seen ->
                    Left (BlueprintDefinitionCycle reference)
                | otherwise ->
                    case Map.lookup reference (blueprintDefinitions blueprint) of
                        Nothing ->
                            Left (BlueprintDefinitionMissing reference)
                        Just definition ->
                            -- A constructor field can attach a semantic title
                            -- (e.g. @"recipient"@) at the outer schema node and
                            -- nest the @$ref@ inside a @"schema"@ wrapper. When
                            -- following the @$ref@, keep the outer title — it
                            -- names the field through to 'decodeBlueprintValue'
                            -- and pins the typed predicate
                            -- (@:SwapOrder_recipient@ vs the definition title
                            -- @:SwapOrder_Credential@). T103 / A-001
                            -- correction-in-passing alongside the field-wrapper
                            -- parser fix.
                            let inheritedTitle =
                                    case schemaTitle schema of
                                        Just _ -> schemaTitle schema
                                        Nothing -> schemaTitle definition
                                titled =
                                    definition{schemaTitle = inheritedTitle}
                             in go (Set.insert reference seen) titled
            SchemaConstructor index fields ->
                BlueprintSchema (schemaTitle schema)
                    . SchemaConstructor index
                    <$> traverse (go seen) fields
            SchemaAnyOf alternatives ->
                BlueprintSchema (schemaTitle schema)
                    . SchemaAnyOf
                    <$> traverse (go seen) alternatives
            SchemaList fields ->
                BlueprintSchema (schemaTitle schema)
                    . SchemaList
                    <$> traverse (go seen) fields
            SchemaListOf item ->
                BlueprintSchema (schemaTitle schema)
                    . SchemaListOf
                    <$> go seen item
            SchemaMap keySchema valueSchema ->
                BlueprintSchema (schemaTitle schema)
                    <$> ( SchemaMap
                            <$> go seen keySchema
                            <*> go seen valueSchema
                        )
            SchemaInteger ->
                Right schema
            SchemaBytes ->
                Right schema
            SchemaData ->
                Right schema

instance FromJSON Blueprint where
    parseJSON =
        withObject "Blueprint" $ \value ->
            Blueprint
                <$> value .: "preamble"
                <*> value .:? "validators" .!= []
                <*> parseBlueprintDefinitions value

parseBlueprintDefinitions :: Object -> Parser (Map Text BlueprintSchema)
parseBlueprintDefinitions value = do
    definitions <- value .:? "definitions" .!= KeyMap.empty
    -- Surface parse failures instead of silently dropping the definition.
    -- A dropped definition turns into a downstream
    -- `BlueprintDefinitionMissing` when any `$ref` follows it, which is
    -- invisible to the operator until typed-emit runs against the blueprint
    -- on a real datum / redeemer. Failing at parse time means the
    -- rules-loader surfaces a `BlueprintParseError` immediately.
    Map.fromList <$> traverse parseEntry (KeyMap.toList definitions)
  where
    parseEntry (key, definitionValue) =
        case parseEither parseJSON definitionValue of
            Right schema ->
                pure (Key.toText key, schema)
            Left err ->
                fail
                    ( "blueprint definition "
                        <> Text.unpack (Key.toText key)
                        <> ": "
                        <> err
                    )

instance FromJSON BlueprintPreamble where
    parseJSON =
        withObject "BlueprintPreamble" $ \value ->
            BlueprintPreamble
                <$> value .: "title"
                <*> value .: "plutusVersion"

instance FromJSON BlueprintValidator where
    parseJSON =
        withObject "BlueprintValidator" $ \value ->
            BlueprintValidator
                <$> value .:? "title"
                <*> value .:? "datum"
                <*> value .:? "redeemer"

instance FromJSON BlueprintArgument where
    parseJSON =
        withObject "BlueprintArgument" $ \value ->
            BlueprintArgument
                <$> value .:? "title"
                <*> value .: "schema"

instance FromJSON BlueprintSchema where
    parseJSON =
        withObject "BlueprintSchema" $ \value -> do
            title <- value .:? "title"
            -- CIP-57 lets a constructor field wrap its inner schema under a
            -- @\"schema\"@ key, e.g.
            -- @{ \"title\": \"recipient\", \"schema\": { \"$ref\": \"...\" } }@.
            -- Honour the wrapping by reading the inner schema's kind when the
            -- key is present; the outer field's @\"title\"@ still names the
            -- BlueprintSchema. Without this unwrap a wrapped field decodes as
            -- 'SchemaData' (the no-@dataType@ fallback), which produces a
            -- generic @{ constructor, fields }@ OpenObject and undoes the
            -- typed-emission contract — surfaced by fixture
            -- @12-blueprint-typed@'s SwapOrder.recipient field. T103 / A-001
            -- walker-extension correction-in-passing.
            wrapped <-
                value
                    .:? "schema" ::
                    Parser (Maybe BlueprintSchema)
            kind <- case wrapped of
                Just inner -> pure (schemaKind inner)
                Nothing -> schemaKindFromObject value
            pure
                BlueprintSchema
                    { schemaTitle = title
                    , schemaKind = kind
                    }

schemaKindFromObject ::
    Object -> Parser BlueprintSchemaKind
schemaKindFromObject value = do
    reference <- value .:? "$ref"
    case reference of
        Just ref ->
            SchemaReference <$> definitionReference ref
        Nothing ->
            schemaKindBody value

schemaKindBody :: Object -> Parser BlueprintSchemaKind
schemaKindBody value = do
    alternatives <- value .:? "anyOf"
    case alternatives of
        Just schemas ->
            pure (SchemaAnyOf schemas)
        Nothing -> do
            dataType <- value .:? "dataType"
            case dataType :: Maybe Text of
                Nothing ->
                    pure SchemaData
                Just "integer" ->
                    pure SchemaInteger
                Just "bytes" ->
                    pure SchemaBytes
                Just "constructor" ->
                    SchemaConstructor
                        <$> value .: "index"
                        <*> value .:? "fields" .!= []
                Just "list" ->
                    listSchemaKind value
                Just "map" ->
                    SchemaMap
                        <$> value .: "keys"
                        <*> value .: "values"
                Just unknown ->
                    fail
                        ( "unsupported Plutus blueprint dataType: "
                            <> Text.unpack unknown
                        )

listSchemaKind :: Object -> Parser BlueprintSchemaKind
listSchemaKind value = do
    items <- value .:? "items"
    case items of
        Nothing ->
            pure (SchemaListOf anyDataSchema)
        Just (Aeson.Array itemValues) ->
            SchemaList <$> traverse parseJSON (toList itemValues)
        Just itemValue ->
            SchemaListOf <$> parseJSON itemValue

anyDataSchema :: BlueprintSchema
anyDataSchema =
    BlueprintSchema
        { schemaTitle = Nothing
        , schemaKind = SchemaData
        }

definitionReference :: Text -> Parser Text
definitionReference reference =
    case Text.stripPrefix "#/definitions/" reference of
        Just definition
            | not (Text.null definition) ->
                pure (jsonPointerToken definition)
        _ ->
            fail
                ( "unsupported Plutus blueprint reference: "
                    <> Text.unpack reference
                )

jsonPointerToken :: Text -> Text
jsonPointerToken =
    Text.replace "~0" "~" . Text.replace "~1" "/"

{-# LANGUAGE OverloadedStrings #-}

module Cardano.Tx.BlueprintSpec (spec) where

import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as LBS8
import Data.Map.Strict qualified as Map
import Test.Hspec

import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Tx.Blueprint (
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
 )
import Cardano.Tx.Diff (
    DiffChange (..),
    DiffNode (..),
    DiffPath (..),
    OpenValue (..),
    TxDiffDataKind (..),
    TxDiffDataSelector (..),
 )
import PlutusCore.Data qualified as PLC

spec :: Spec
spec =
    describe "Plutus blueprints" $ do
        it "parses validators, datum and redeemer schemas, and definitions" $ do
            parseBlueprintJSON blueprintJson
                `shouldBe` Right
                    Blueprint
                        { blueprintPreamble =
                            BlueprintPreamble
                                { preambleTitle = "Swap orders"
                                , preamblePlutusVersion = "v3"
                                }
                        , blueprintValidators =
                            [ BlueprintValidator
                                { validatorTitle = Just "swap"
                                , validatorDatum =
                                    Just
                                        BlueprintArgument
                                            { argumentTitle = Just "Order datum"
                                            , argumentSchema =
                                                BlueprintSchema
                                                    { schemaTitle = Nothing
                                                    , schemaKind =
                                                        SchemaReference
                                                            "OrderDatum"
                                                    }
                                            }
                                , validatorRedeemer =
                                    Just
                                        BlueprintArgument
                                            { argumentTitle =
                                                Just "Order redeemer"
                                            , argumentSchema =
                                                BlueprintSchema
                                                    { schemaTitle = Nothing
                                                    , schemaKind =
                                                        SchemaConstructor
                                                            1
                                                            [ BlueprintSchema
                                                                { schemaTitle =
                                                                    Just "amount"
                                                                , schemaKind =
                                                                    SchemaInteger
                                                                }
                                                            , BlueprintSchema
                                                                { schemaTitle =
                                                                    Just "asset"
                                                                , schemaKind =
                                                                    SchemaBytes
                                                                }
                                                            ]
                                                    }
                                            }
                                }
                            ]
                        , blueprintDefinitions =
                            Map.singleton
                                "OrderDatum"
                                BlueprintSchema
                                    { schemaTitle = Just "Order datum"
                                    , schemaKind =
                                        SchemaConstructor
                                            0
                                            [ BlueprintSchema
                                                { schemaTitle = Just "owner"
                                                , schemaKind = SchemaBytes
                                                }
                                            ]
                                    }
                        }

        it "matches a validator datum schema and resolves local definitions" $
            case parseBlueprintJSON blueprintJson of
                Left err ->
                    expectationFailure err
                Right blueprint ->
                    matchBlueprintArgument
                        [blueprint]
                        BlueprintArgumentSelector
                            { selectorValidatorTitle = Just "swap"
                            , selectorArgumentKind = BlueprintDatum
                            }
                        `shouldBe` Right
                            BlueprintSchema
                                { schemaTitle = Just "Order datum"
                                , schemaKind =
                                    SchemaConstructor
                                        0
                                        [ BlueprintSchema
                                            { schemaTitle = Just "owner"
                                            , schemaKind = SchemaBytes
                                            }
                                        ]
                                }

        it "parses Aiken blueprints with generic data and list definitions" $
            case parseBlueprintJSON aikenSubsetBlueprintJson of
                Left err ->
                    expectationFailure err
                Right blueprint -> do
                    Map.lookup "Data" (blueprintDefinitions blueprint)
                        `shouldBe` Just
                            ( BlueprintSchema
                                { schemaTitle = Just "Data"
                                , schemaKind = SchemaData
                                }
                            )
                    Map.lookup "List$Int" (blueprintDefinitions blueprint)
                        `shouldBe` Just
                            ( BlueprintSchema
                                { schemaTitle = Nothing
                                , schemaKind =
                                    SchemaListOf
                                        BlueprintSchema
                                            { schemaTitle = Nothing
                                            , schemaKind = SchemaReference "Int"
                                            }
                                }
                            )

        it "parses CIP-57 \"dataType\": \"map\" definitions into SchemaMap" $
            -- Closes the SundaeSwap treasury-contracts gap surfaced
            -- 2026-05-22 on a real Conway disburse tx: definitions with
            -- @"dataType": "map"@ (e.g. @Pairs<PolicyId,Pairs<AssetName,
            -- Int>>@) previously failed to parse and were silently
            -- dropped, turning every downstream @$ref@ to them into a
            -- @BlueprintDefinitionMissing@ that blocked typed-emit.
            case parseBlueprintJSON pairsMapBlueprintJson of
                Left err ->
                    expectationFailure err
                Right blueprint ->
                    Map.lookup
                        "Pairs<PolicyId,Pairs<AssetName,Int>>"
                        (blueprintDefinitions blueprint)
                        `shouldBe` Just
                            BlueprintSchema
                                { schemaTitle =
                                    Just "Pairs<PolicyId, Pairs<AssetName, Int>>"
                                , schemaKind =
                                    SchemaMap
                                        BlueprintSchema
                                            { schemaTitle = Nothing
                                            , schemaKind = SchemaReference "PolicyId"
                                            }
                                        BlueprintSchema
                                            { schemaTitle = Nothing
                                            , schemaKind =
                                                SchemaReference
                                                    "Pairs<AssetName,Int>"
                                            }
                                }

        it "surfaces blueprint definition parse failures instead of silently dropping" $ do
            -- Previously parseBlueprintDefinitions silently dropped any
            -- definition whose schema failed to parse, leaving every
            -- \$ref to it dangling as BlueprintDefinitionMissing at
            -- typed-emit time. Convert to a parse-time failure surfaced
            -- through the loader's BlueprintParseError path.
            case parseBlueprintJSON unknownDataTypeBlueprintJson of
                Left _ -> pure ()
                Right _ ->
                    expectationFailure
                        "expected parse failure on unknown dataType, but the \
                        \definition was silently dropped"

        it "decodes a recursive definition against finite data" $
            -- SundaeSwap `order.spend` OrderDatum: the `owner`
            -- field is a RECURSIVE `MultisigScript` (an `AtLeast`
            -- constructor whose `scripts` field is a
            -- `List<MultisigScript>`). Eagerly unfolding the schema
            -- returns `BlueprintDefinitionCycle` before any data is
            -- read, blocking even the non-recursive sibling field.
            -- Real on-chain `Data` is finite, so resolving the `$ref`
            -- per-occurrence during decode terminates: the recursive
            -- field decodes to its bounded value and the sibling
            -- `minReceive` is recovered.
            case parseBlueprintJSON recursiveBlueprintJson of
                Left err ->
                    expectationFailure err
                Right blueprint ->
                    blueprintDataDecoder
                        [blueprint]
                        TxDiffDataSelector
                            { txDiffDataValidatorTitle = Just "order"
                            , txDiffDataKind = TxDiffDatum
                            }
                        recursiveDatum
                        `shouldBe` Right
                            ( OpenObject
                                ( Map.fromList
                                    [
                                        ( "owner"
                                        , OpenObject
                                            ( Map.fromList
                                                [ ("required", OpenInteger 2)
                                                ,
                                                    ( "scripts"
                                                    , OpenArray
                                                        [ OpenObject
                                                            ( Map.fromList
                                                                [ ("keyHash", OpenBytes "aa")
                                                                ]
                                                            )
                                                        , OpenObject
                                                            ( Map.fromList
                                                                [ ("keyHash", OpenBytes "bb")
                                                                ]
                                                            )
                                                        ]
                                                    )
                                                ]
                                            )
                                        )
                                    , ("minReceive", OpenInteger 1000)
                                    ]
                                )
                            )

        it "still errors on a non-productive self-cycle" $
            -- The recursion-tolerant decoder must NOT loop forever on a
            -- definition that refers to itself without ever consuming a
            -- `Data` node. `Loop -> $ref Loop` makes no data progress,
            -- so the cycle guard fires with `BlueprintReferenceCycle`.
            decodeBlueprintDataWith
                ( Map.singleton
                    "Loop"
                    BlueprintSchema
                        { schemaTitle = Nothing
                        , schemaKind = SchemaReference "Loop"
                        }
                )
                BlueprintSchema
                    { schemaTitle = Nothing
                    , schemaKind = SchemaReference "Loop"
                    }
                (orderDatum 42)
                `shouldBe` Left (BlueprintReferenceCycle "Loop")

        it "selects the only matching blueprint argument that decodes the datum" $ do
            let wrongDatum =
                    BlueprintArgument
                        { argumentTitle = Just "Wrong datum"
                        , argumentSchema =
                            BlueprintSchema
                                { schemaTitle = Just "Wrong datum"
                                , schemaKind = SchemaConstructor 99 []
                                }
                        }
                rightValidator =
                    BlueprintValidator
                        { validatorTitle = Just "right"
                        , validatorDatum =
                            Just
                                BlueprintArgument
                                    { argumentTitle = Just "Order datum"
                                    , argumentSchema = orderSchema
                                    }
                        , validatorRedeemer = Nothing
                        }
                wrongValidator =
                    rightValidator
                        { validatorTitle = Just "wrong"
                        , validatorDatum = Just wrongDatum
                        }
                blueprint =
                    Blueprint
                        { blueprintPreamble =
                            BlueprintPreamble
                                { preambleTitle = "ambiguous"
                                , preamblePlutusVersion = "v3"
                                }
                        , blueprintValidators = [wrongValidator, rightValidator]
                        , blueprintDefinitions = Map.empty
                        }
            blueprintDataDecoder
                [blueprint]
                TxDiffDataSelector
                    { txDiffDataValidatorTitle = Nothing
                    , txDiffDataKind = TxDiffDatum
                    }
                (orderDatum 42)
                `shouldBe` Right
                    ( OpenObject
                        ( Map.fromList
                            [ ("amount", OpenInteger 42)
                            , ("owner", OpenBytes "dead")
                            ]
                        )
                    )

        it "converts constructor data into an open application value" $ do
            decodeBlueprintData orderSchema (orderDatum 42)
                `shouldBe` Right
                    ( OpenObject
                        ( Map.fromList
                            [ ("amount", OpenInteger 42)
                            , ("owner", OpenBytes "dead")
                            ]
                        )
                    )

        it "diffs decoded constructor fields as open application values" $ do
            diffBlueprintData orderSchema (orderDatum 42) (orderDatum 43)
                `shouldBe` Right
                    ( DiffNode
                        rootPath
                        ( DiffObject
                            ( Map.fromList
                                [ ("owner", Just (Aeson.object ["bytes" .= ("dead" :: String)]))
                                ]
                            )
                            ( Map.fromList
                                [
                                    ( "amount"
                                    , DiffNode
                                        (DiffPath ["amount"])
                                        ( DiffChanged
                                            (Aeson.Number 42)
                                            (Aeson.Number 43)
                                        )
                                    )
                                ]
                            )
                            Map.empty
                            Map.empty
                        )
                    )

        it "falls back to raw data when no blueprint argument matches" $
            case diffBlueprintArgumentData
                []
                orderDatumSelector
                (orderDatum 42)
                (orderDatum 43) of
                BlueprintDiffFallback
                    (BlueprintMatchFallback BlueprintArgumentMissing)
                    diff ->
                        diff `shouldBeRawDataChange` rootPath
                other ->
                    expectationFailure ("unexpected fallback result: " <> show other)

        it "falls back to raw data when blueprint argument matches ambiguously" $
            case parseBlueprintJSON blueprintJson of
                Left err ->
                    expectationFailure err
                Right blueprint ->
                    case diffBlueprintArgumentData
                        [blueprint, blueprint]
                        orderDatumSelector
                        (orderDatum 42)
                        (orderDatum 43) of
                        BlueprintDiffFallback
                            ( BlueprintMatchFallback
                                    (BlueprintArgumentAmbiguous ["swap", "swap"])
                                )
                            diff ->
                                diff `shouldBeRawDataChange` rootPath
                        other ->
                            expectationFailure $
                                "unexpected fallback result: " <> show other

rootPath :: DiffPath
rootPath =
    DiffPath []

orderSchema :: BlueprintSchema
orderSchema =
    BlueprintSchema
        { schemaTitle = Just "Order"
        , schemaKind =
            SchemaConstructor
                0
                [ BlueprintSchema
                    { schemaTitle = Just "owner"
                    , schemaKind = SchemaBytes
                    }
                , BlueprintSchema
                    { schemaTitle = Just "amount"
                    , schemaKind = SchemaInteger
                    }
                ]
        }

orderDatum :: Integer -> Data ConwayEra
orderDatum amount =
    Data
        ( PLC.Constr
            0
            [ PLC.B (BS.pack [0xde, 0xad])
            , PLC.I amount
            ]
        )

{- | Finite SundaeSwap-shaped OrderDatum payload exercising the
recursive @owner : MultisigScript@ field: @owner@ is an @AtLeast 2
[Signature 0xaa, Signature 0xbb]@ and the non-recursive sibling
@minReceive@ is @1000@.
-}
recursiveDatum :: Data ConwayEra
recursiveDatum =
    Data
        ( PLC.Constr
            0
            [ PLC.Constr
                1
                [ PLC.I 2
                , PLC.List
                    [ PLC.Constr 0 [PLC.B (BS.pack [0xaa])]
                    , PLC.Constr 0 [PLC.B (BS.pack [0xbb])]
                    ]
                ]
            , PLC.I 1000
            ]
        )

orderDatumSelector :: BlueprintArgumentSelector
orderDatumSelector =
    BlueprintArgumentSelector
        { selectorValidatorTitle = Just "swap"
        , selectorArgumentKind = BlueprintDatum
        }

shouldBeRawDataChange :: DiffNode -> DiffPath -> Expectation
shouldBeRawDataChange (DiffNode path (DiffChanged left right)) expectedPath = do
    path `shouldBe` expectedPath
    left `shouldSatisfy` hasCborField
    right `shouldSatisfy` hasCborField
    left `shouldNotBe` right
shouldBeRawDataChange other _ =
    expectationFailure ("expected raw data change, got: " <> show other)

hasCborField :: Aeson.Value -> Bool
hasCborField (Aeson.Object value) =
    KeyMap.member "cbor" value
hasCborField _ =
    False

blueprintJson :: LBS8.ByteString
blueprintJson =
    "{\
    \  \"preamble\": {\
    \    \"title\": \"Swap orders\",\
    \    \"plutusVersion\": \"v3\"\
    \  },\
    \  \"validators\": [\
    \    {\
    \      \"title\": \"swap\",\
    \      \"datum\": {\
    \        \"title\": \"Order datum\",\
    \        \"schema\": {\"$ref\": \"#/definitions/OrderDatum\"}\
    \      },\
    \      \"redeemer\": {\
    \        \"title\": \"Order redeemer\",\
    \        \"schema\": {\
    \          \"dataType\": \"constructor\",\
    \          \"index\": 1,\
    \          \"fields\": [\
    \            {\"title\": \"amount\", \"dataType\": \"integer\"},\
    \            {\"title\": \"asset\", \"dataType\": \"bytes\"}\
    \          ]\
    \        }\
    \      }\
    \    }\
    \  ],\
    \  \"definitions\": {\
    \    \"OrderDatum\": {\
    \      \"title\": \"Order datum\",\
    \      \"dataType\": \"constructor\",\
    \      \"index\": 0,\
    \      \"fields\": [\
    \        {\"title\": \"owner\", \"dataType\": \"bytes\"}\
    \      ]\
    \    }\
    \  }\
    \}"

{- | SundaeSwap-style blueprint snippet: a @Pairs<PolicyId,
Pairs<AssetName,Int>>@ definition whose @"dataType": "map"@ must
parse into a 'SchemaMap'. JSON-Pointer @~1@ escapes round-trip
per RFC 6901 through 'jsonPointerToken'.
-}
pairsMapBlueprintJson :: LBS8.ByteString
pairsMapBlueprintJson =
    "{\
    \  \"preamble\": {\"title\": \"Pairs map\", \"plutusVersion\": \"v3\"},\
    \  \"validators\": [],\
    \  \"definitions\": {\
    \    \"PolicyId\": {\"dataType\": \"bytes\"},\
    \    \"AssetName\": {\"dataType\": \"bytes\"},\
    \    \"Int\": {\"dataType\": \"integer\"},\
    \    \"Pairs<AssetName,Int>\": {\
    \      \"title\": \"Pairs<AssetName, Int>\",\
    \      \"dataType\": \"map\",\
    \      \"keys\": {\"$ref\": \"#/definitions/AssetName\"},\
    \      \"values\": {\"$ref\": \"#/definitions/Int\"}\
    \    },\
    \    \"Pairs<PolicyId,Pairs<AssetName,Int>>\": {\
    \      \"title\": \"Pairs<PolicyId, Pairs<AssetName, Int>>\",\
    \      \"dataType\": \"map\",\
    \      \"keys\": {\"$ref\": \"#/definitions/PolicyId\"},\
    \      \"values\": {\"$ref\": \"#/definitions/Pairs<AssetName,Int>\"}\
    \    }\
    \  }\
    \}"

{- | A blueprint containing a definition with an unsupported
@dataType@. Used to verify that 'parseBlueprintDefinitions'
surfaces the parse failure rather than silently dropping the
definition.
-}
unknownDataTypeBlueprintJson :: LBS8.ByteString
unknownDataTypeBlueprintJson =
    "{\
    \  \"preamble\": {\"title\": \"Bad\", \"plutusVersion\": \"v3\"},\
    \  \"validators\": [],\
    \  \"definitions\": {\
    \    \"Mystery\": {\"dataType\": \"this-is-not-a-real-data-type\"}\
    \  }\
    \}"

{- | SundaeSwap-style blueprint with a RECURSIVE @MultisigScript@
definition: the @AtLeast@ alternative carries a
@scripts : List<MultisigScript>@ field that refers back to the
definition itself. The @order@ validator's datum embeds it as the
@owner@ field next to a non-recursive @minReceive@ sibling. Eager
schema resolution returns @BlueprintDefinitionCycle@ on this shape;
per-occurrence resolution against finite 'Data' terminates.
-}
recursiveBlueprintJson :: LBS8.ByteString
recursiveBlueprintJson =
    "{\
    \  \"preamble\": {\"title\": \"Recursive\", \"plutusVersion\": \"v3\"},\
    \  \"validators\": [\
    \    {\
    \      \"title\": \"order\",\
    \      \"datum\": {\
    \        \"title\": \"Order datum\",\
    \        \"schema\": {\"$ref\": \"#/definitions/OrderDatum\"}\
    \      }\
    \    }\
    \  ],\
    \  \"definitions\": {\
    \    \"OrderDatum\": {\
    \      \"dataType\": \"constructor\",\
    \      \"index\": 0,\
    \      \"fields\": [\
    \        {\"title\": \"owner\", \"schema\": {\"$ref\": \"#/definitions/MultisigScript\"}},\
    \        {\"title\": \"minReceive\", \"dataType\": \"integer\"}\
    \      ]\
    \    },\
    \    \"MultisigScript\": {\
    \      \"title\": \"MultisigScript\",\
    \      \"anyOf\": [\
    \        {\
    \          \"title\": \"Signature\",\
    \          \"dataType\": \"constructor\",\
    \          \"index\": 0,\
    \          \"fields\": [{\"title\": \"keyHash\", \"dataType\": \"bytes\"}]\
    \        },\
    \        {\
    \          \"title\": \"AtLeast\",\
    \          \"dataType\": \"constructor\",\
    \          \"index\": 1,\
    \          \"fields\": [\
    \            {\"title\": \"required\", \"dataType\": \"integer\"},\
    \            {\
    \              \"title\": \"scripts\",\
    \              \"dataType\": \"list\",\
    \              \"items\": {\"$ref\": \"#/definitions/MultisigScript\"}\
    \            }\
    \          ]\
    \        }\
    \      ]\
    \    }\
    \  }\
    \}"

aikenSubsetBlueprintJson :: LBS8.ByteString
aikenSubsetBlueprintJson =
    "{\
    \  \"preamble\": {\
    \    \"title\": \"Aiken subset\",\
    \    \"plutusVersion\": \"v3\"\
    \  },\
    \  \"validators\": [],\
    \  \"definitions\": {\
    \    \"Bool\": {\
    \      \"title\": \"Bool\",\
    \      \"anyOf\": [\
    \        {\"title\": \"False\", \"dataType\": \"constructor\", \"index\": 0},\
    \        {\"title\": \"True\", \"dataType\": \"constructor\", \"index\": 1}\
    \      ]\
    \    },\
    \    \"Data\": {\
    \      \"title\": \"Data\",\
    \      \"description\": \"Any Plutus data.\"\
    \    },\
    \    \"Int\": {\"dataType\": \"integer\"},\
    \    \"List$Int\": {\
    \      \"dataType\": \"list\",\
    \      \"items\": {\"$ref\": \"#/definitions/Int\"}\
    \    }\
    \  }\
    \}"

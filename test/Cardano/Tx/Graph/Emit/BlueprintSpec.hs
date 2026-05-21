{- |
Module      : Cardano.Tx.Graph.Emit.BlueprintSpec
Description : T101 RED — Emit.Blueprint pure decoder + IRI minter.
License     : Apache-2.0

Pinned contract for the T101 slice of feature 050 (blueprint-decode
typed triples). The module under test
('Cardano.Tx.Graph.Emit.Blueprint') is introduced by this slice; the
RED therefore fails on the pre-T101 codebase because the module does
not yet exist.

Six invariants (four decoder + two IRI minter):

* @happy-path-datum@ — synthetic 'Blueprint' with a constructor-shaped
  datum schema + a matching 'Data' ConwayEra value + a synthetic
  'TxOut' ConwayEra whose payment credential is the blueprint's
  script hash. 'decodeDatumForOutput' returns @'Decoded' openValue
  blueprint@ where @openValue@ is the expected
  @'OpenObject' (Map.fromList [(...)])@ shape.

* @no-blueprint@ — same 'Data' value but the script hash is not in
  the index. Returns 'NoBlueprintRegistered'.

* @decode-failed@ — blueprint expects bytes but the 'Data' carries
  an integer. Returns @'DecodeFailed' ('BlueprintDataTypeMismatch'
  "bytes")@.

* @happy-path-redeemer@ — synthetic redeemer path with the 'Spend'
  purpose; the index has a blueprint whose @redeemer:@ shape decodes
  the 'Data'. Returns @'Decoded' openValue blueprint@.

* @iri-minter-happy@ — 'blueprintFieldPredicate' \"SwapOrder\"
  \"recipient\" produces @'PIri' ":SwapOrder_recipient"@ per FR-008
  / D-001b.

* @iri-minter-title-missing@ — the function is the lowest-level IRI
  minter; the title-missing substitutions ("_\<index\>" for the
  constructor, "field\<n\>" for the field) are the caller's
  responsibility. The minter just concatenates the two pre-resolved
  components with the @:\<a\>_\<b\>@ format. The test pins this
  contract by asserting
  'blueprintFieldPredicate' \"_0\" \"field0\" '==' @'PIri'
  ":_0_field0"@ (see STATUS.md NAV-PIN-IRI-MINTER for the rationale).
-}
module Cardano.Tx.Graph.Emit.BlueprintSpec (spec) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import PlutusCore.Data qualified as PLC
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx.Out (TxOut, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))

import Cardano.Tx.Blueprint (
    Blueprint (..),
    BlueprintArgument (..),
    BlueprintDataError (..),
    BlueprintPreamble (..),
    BlueprintSchema (..),
    BlueprintSchemaKind (..),
    BlueprintValidator (..),
 )
import Cardano.Tx.Diff (OpenValue (..))
import Cardano.Tx.Graph.Emit (Predicate (..))

import Cardano.Tx.Graph.Emit.Blueprint (
    BlueprintDecodeResult (..),
    RdmrPurpose (..),
    blueprintFieldPredicate,
    decodeDatumForOutput,
    decodeRedeemerForPurpose,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit.Blueprint (T101 / S1)" $ do
    describe "decodeDatumForOutput" $ do
        it "Decoded — script hash matches, blueprint datum schema decodes the constructor" $
            case decodeDatumForOutput
                [(swapOrderScriptHash, swapOrderBlueprint, swapOrderTitle)]
                (swapOrderTxOut swapOrderScriptHash)
                swapOrderDatum of
                Decoded openValue blueprint -> do
                    openValue
                        `shouldBe` OpenObject
                            ( Map.fromList
                                [("recipient", OpenBytes "deadbeef")]
                            )
                    blueprint `shouldBe` swapOrderBlueprint
                other ->
                    expectationFailure $
                        "expected Decoded, got: " <> show other

        it "NoBlueprintRegistered — output script hash absent from the index" $
            decodeDatumForOutput
                []
                (swapOrderTxOut swapOrderScriptHash)
                swapOrderDatum
                `shouldBe` NoBlueprintRegistered

        it "DecodeFailed — schema is bytes, Data carries integer" $
            decodeDatumForOutput
                [(bytesScriptHash, bytesBlueprint, bytesTitle)]
                (swapOrderTxOut bytesScriptHash)
                (Data (PLC.I 42))
                `shouldBe` DecodeFailed (BlueprintDataTypeMismatch "bytes")

    describe "decodeRedeemerForPurpose" $
        it "Decoded — Spend purpose, redeemer schema decodes the constructor" $
            case decodeRedeemerForPurpose
                [(swapRedeemerScriptHash, swapRedeemerBlueprint, swapRedeemerTitle)]
                Spend
                swapRedeemerScriptHash
                swapRedeemerDatum of
                Decoded openValue blueprint -> do
                    openValue
                        `shouldBe` OpenObject
                            ( Map.fromList
                                [("amount", OpenInteger 42)]
                            )
                    blueprint `shouldBe` swapRedeemerBlueprint
                other ->
                    expectationFailure $
                        "expected Decoded, got: " <> show other

    describe "blueprintFieldPredicate" $ do
        it "mints ':<Constructor>_<field>' for fully-titled inputs" $
            blueprintFieldPredicate "SwapOrder" "recipient"
                `shouldBe` PIri ":SwapOrder_recipient"

        it "concatenates pre-resolved title-missing fallbacks verbatim" $
            -- See NAV-PIN-IRI-MINTER (STATUS.md): the minter is pure
            -- concatenation; the caller pre-resolves the
            -- "_<constructor-index>" / "field<n>" fallback strings.
            blueprintFieldPredicate "_0" "field0"
                `shouldBe` PIri ":_0_field0"

----------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------

{- | The 'SwapOrder' datum blueprint used by happy-path-datum.
The constructor has a single bytes field titled @recipient@; the
preamble title is recorded on the index entry as the third tuple
element.
-}
swapOrderBlueprint :: Blueprint
swapOrderBlueprint =
    Blueprint
        { blueprintPreamble =
            BlueprintPreamble
                { preambleTitle = "amaru.swap.v2"
                , preamblePlutusVersion = "v3"
                }
        , blueprintValidators =
            [ BlueprintValidator
                { validatorTitle = Just "swap"
                , validatorDatum =
                    Just
                        BlueprintArgument
                            { argumentTitle = Just "SwapOrder"
                            , argumentSchema =
                                BlueprintSchema
                                    { schemaTitle = Just "SwapOrder"
                                    , schemaKind =
                                        SchemaConstructor
                                            0
                                            [ BlueprintSchema
                                                { schemaTitle = Just "recipient"
                                                , schemaKind = SchemaBytes
                                                }
                                            ]
                                    }
                            }
                , validatorRedeemer = Nothing
                }
            ]
        , blueprintDefinitions = Map.empty
        }

-- | Preamble title for 'swapOrderBlueprint', as kept on the index tuple.
swapOrderTitle :: Text
swapOrderTitle = "amaru.swap.v2"

{- | Plutus 'Data' value matching 'swapOrderBlueprint' — constructor 0
carrying a single bytes field.
-}
swapOrderDatum :: Data ConwayEra
swapOrderDatum =
    Data
        ( PLC.Constr
            0
            [PLC.B (BS.pack [0xde, 0xad, 0xbe, 0xef])]
        )

-- | The script hash registering 'swapOrderBlueprint' in the index.
swapOrderScriptHash :: ScriptHash
swapOrderScriptHash = mkScriptHash 1

{- | Bytes-typed datum blueprint used by decode-failed.
The datum schema is a bare 'SchemaBytes' (no constructor wrap) so the
@bytes@ vs @integer@ mismatch surfaces as
'BlueprintDataTypeMismatch' \"bytes\".
-}
bytesBlueprint :: Blueprint
bytesBlueprint =
    Blueprint
        { blueprintPreamble =
            BlueprintPreamble
                { preambleTitle = "raw-bytes-validator"
                , preamblePlutusVersion = "v3"
                }
        , blueprintValidators =
            [ BlueprintValidator
                { validatorTitle = Just "bytes-only"
                , validatorDatum =
                    Just
                        BlueprintArgument
                            { argumentTitle = Just "BytesDatum"
                            , argumentSchema =
                                BlueprintSchema
                                    { schemaTitle = Just "BytesDatum"
                                    , schemaKind = SchemaBytes
                                    }
                            }
                , validatorRedeemer = Nothing
                }
            ]
        , blueprintDefinitions = Map.empty
        }

bytesTitle :: Text
bytesTitle = "raw-bytes-validator"

bytesScriptHash :: ScriptHash
bytesScriptHash = mkScriptHash 2

{- | The 'SwapOrder' redeemer blueprint used by happy-path-redeemer.
The redeemer schema is a single-field constructor with an integer
field titled @amount@.
-}
swapRedeemerBlueprint :: Blueprint
swapRedeemerBlueprint =
    Blueprint
        { blueprintPreamble =
            BlueprintPreamble
                { preambleTitle = "amaru.swap.v2.redeem"
                , preamblePlutusVersion = "v3"
                }
        , blueprintValidators =
            [ BlueprintValidator
                { validatorTitle = Just "swap-redeem"
                , validatorDatum = Nothing
                , validatorRedeemer =
                    Just
                        BlueprintArgument
                            { argumentTitle = Just "SwapRedeem"
                            , argumentSchema =
                                BlueprintSchema
                                    { schemaTitle = Just "SwapRedeem"
                                    , schemaKind =
                                        SchemaConstructor
                                            0
                                            [ BlueprintSchema
                                                { schemaTitle = Just "amount"
                                                , schemaKind = SchemaInteger
                                                }
                                            ]
                                    }
                            }
                }
            ]
        , blueprintDefinitions = Map.empty
        }

swapRedeemerTitle :: Text
swapRedeemerTitle = "amaru.swap.v2.redeem"

swapRedeemerScriptHash :: ScriptHash
swapRedeemerScriptHash = mkScriptHash 3

swapRedeemerDatum :: Data ConwayEra
swapRedeemerDatum =
    Data (PLC.Constr 0 [PLC.I 42])

----------------------------------------------------------------------
-- TxOut + ScriptHash helpers
----------------------------------------------------------------------

{- | A synthetic 'TxOut' ConwayEra whose payment credential is the
supplied 'ScriptHash'. The address sits on Testnet with no stake
reference; the value is 1 ADA lovelace, no native assets — only the
payment credential matters for the decoder under test.
-}
swapOrderTxOut :: ScriptHash -> TxOut ConwayEra
swapOrderTxOut sh =
    mkBasicTxOut
        (Addr Testnet (ScriptHashObj sh) StakeRefNull)
        (MaryValue (Coin 1_000_000) (MultiAsset mempty))

{- | Build a deterministic 28-byte 'ScriptHash' from a small integer
seed — mirrors the @mkScriptHash@ helper in
'Cardano.Tx.Rewrite.ApplySpec' so the two suites read consistently.
-}
mkScriptHash :: Int -> ScriptHash
mkScriptHash n =
    let bytes =
            BS.pack
                ( replicate 26 0
                    <> [fromIntegral (n `div` 256), fromIntegral (n `mod` 256)]
                )
     in ScriptHash (fromJust (hashFromBytes bytes))

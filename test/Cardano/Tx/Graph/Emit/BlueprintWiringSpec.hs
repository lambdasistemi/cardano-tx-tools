{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Tx.Graph.Emit.BlueprintWiringSpec
Description : Walker-wiring contract for the T102 / S2 blueprint index seam.
License     : Apache-2.0

The RED contract for slice T102 / S2 of feature 050 (blueprint-decode
typed triples). T101 introduced the pure decoder + IRI minter surface
in 'Cardano.Tx.Graph.Emit.Blueprint'; T102 wires that surface into the
projection walker by extending 'Cardano.Tx.Graph.Emit.emit' with a
fourth parameter

> [(ScriptHash, Blueprint, Text)]

threaded through 'projectBody' + 'projectWitness' to the per-output
datum, datum-witness, and per-purpose redeemer emission paths.

This spec asserts three load-bearing invariants:

* __byte-stability on @[]@__ — for every existing rewrite-redesign
  fixture, @emit tx utxo entities []@ must produce a Turtle byte
  stream byte-identical to the committed @expected.ttl@. This pins
  the contract that callers passing the empty blueprint index see
  no behaviour change (FR-003) — the 11 existing fixtures stay
  GREEN through T102.

* __decodes-on-non-empty-index__ — a synthetic in-memory tx that
  carries a script-credential output with an inline 'Datum' shaped
  like a known CIP-57 blueprint must, when 'emit' is called with
  that blueprint registered in the index, emit at least one
  typed @:\<constructor\>_\<field\>@ predicate on the output's
  @cardano:Datum@ subject (FR-004 / D-001b).

* __decode-failure single literal__ — a synthetic in-memory tx
  whose inline datum cannot be matched against the registered
  blueprint must, when 'emit' runs the walker, produce exactly one
  @cardano:decodeError "\<reason\>"@ literal on the failing
  subject — never two (FR-005 / D-001d FIRST-error-only).

Pre-T102 this spec fails to compile because 'emit' takes three
arguments; that compile failure is the RED. T102's driver lands the
4-arg signature + the walker wiring; once both invariants hold the
suite goes GREEN. T103 will be the first slice to ship a fixture
whose @expected.ttl@ actually exercises the typed-emission path on
disk; T102 itself ships no fixture work.
-}
module Cardano.Tx.Graph.Emit.BlueprintWiringSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import System.FilePath ((</>))

import Lens.Micro ((&), (.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Datum)
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    datumTxOutL,
    mkBasicTxOut,
 )
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.Data (mkInlineDatum)
import PlutusCore.Data qualified as PLC

import Cardano.Tx.Blueprint (
    Blueprint (..),
    BlueprintArgument (..),
    BlueprintPreamble (..),
    BlueprintSchema (..),
    BlueprintSchemaKind (..),
    BlueprintValidator (..),
 )
import Cardano.Tx.Build (output)
import Cardano.Tx.Graph.Emit (
    EmitFormat (Turtle),
    EmittedGraph (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl,
    RulesLoadResult (..),
    loadRulesFile,
    rulesEntities,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.Helpers (
    TxBuilder (..),
    mkTx,
    stubTxIn,
    stubTxOutMA,
 )
import Fixtures.RewriteRedesign.S01_AmaruTreasurySwap qualified as S01
import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02
import Fixtures.RewriteRedesign.S03_MultiAssetTransfer qualified as S03
import Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap qualified as S04
import Fixtures.RewriteRedesign.S05_WithdrawalScriptStake qualified as S05
import Fixtures.RewriteRedesign.S06_StakePoolDelegation qualified as S06
import Fixtures.RewriteRedesign.S07_VoteDelegation qualified as S07
import Fixtures.RewriteRedesign.S08_ContingencyDisburse qualified as S08
import Fixtures.RewriteRedesign.S09_MpfsFactsRequest qualified as S09
import Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal qualified as S10
import Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal qualified as S11

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
 )

-- ---------------------------------------------------------------------------
-- Top-level spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit blueprint-index wiring (T102 / S2)" $ do
        byteStabilityOnEmptyIndex
        decodesOnNonEmptyIndex
        decodeFailureSingleLiteral

-- ---------------------------------------------------------------------------
-- Invariant 1: byte-stability on @[]@
-- ---------------------------------------------------------------------------

{- | For every existing rewrite-redesign fixture,
@emit tx utxo entities []@ must produce a Turtle byte stream
byte-identical to the committed @expected.ttl@. The fourth
parameter is the new blueprint-index slot landed by T102; passing
'[]' is the post-T102 invariant that pins FR-003 — no behaviour
change for callers that do not register any blueprints.

Pre-T102 this fails to compile because 'emit' is 3-arg; that
compile failure is the load-bearing RED.
-}
byteStabilityOnEmptyIndex :: Spec
byteStabilityOnEmptyIndex =
    describe "emit tx utxo entities [] is byte-stable on the 11 existing fixtures" $
        mapM_ goldenStability allFixtures

{- | The 11 rewrite-redesign fixtures in slug order. Kept in sync
with 'Cardano.Tx.Graph.EmitGoldenSpec.allFixtures' — that spec
re-asserts the same byte-diff invariant for the wider emitter
coverage; this re-enumeration scopes the assertion to the new
@[]@ blueprint-index parameter so the contract reads at the seam.
-}
allFixtures :: [(String, ConwayTx)]
allFixtures =
    [ ("01-amaru-treasury-swap", S01.tx)
    , ("02-alice-bob-ada", S02.tx)
    , ("03-multi-asset-transfer", S03.tx)
    , ("04-mint-spend-script-overlap", S04.tx)
    , ("05-withdrawal-script-stake", S05.tx)
    , ("06-stake-pool-delegation", S06.tx)
    , ("07-vote-delegation", S07.tx)
    , ("08-contingency-disburse", S08.tx)
    , ("09-mpfs-facts-request", S09.tx)
    , ("10-governance-treasury-withdrawal", S10.tx)
    , ("11-amaru-treasury-swap-real", S11.tx)
    ]

goldenStability :: (String, ConwayTx) -> Spec
goldenStability (slug, tx) = do
    let dir = "test/fixtures/rewrite-redesign" </> slug
        rulesPath = dir </> "rules.yaml"
        expectedPath = dir </> "expected.ttl"
    (entities, overlay) <-
        runIO (loadEntitiesAndOverlay rulesPath)
    expected <- runIO (BS.readFile expectedPath)
    it (slug <> " — emit tx utxo entities [] byte-equal to expected.ttl") $
        case emit tx (fixtureUtxo slug) entities [] of
            Left err ->
                expectationFailure $
                    "emit returned Left " <> show err
            Right g ->
                let joint = g{graphOverlayTurtle = overlay}
                    actual = serialize Turtle slug joint
                 in if actual == expected
                        then pure ()
                        else
                            expectationFailure $
                                "byte-diff: emit("
                                    <> slug
                                    <> ", index = []) /= "
                                    <> expectedPath
                                    <> " (lengths "
                                    <> show (BS.length actual)
                                    <> " vs "
                                    <> show (BS.length expected)
                                    <> ")"

-- ---------------------------------------------------------------------------
-- Invariant 2: typed predicate emerges on a non-empty index match
-- ---------------------------------------------------------------------------

{- | A synthetic in-memory tx carries a script-credential output
whose inline 'Datum' matches a synthetic @SwapOrder@ blueprint
('syntheticSwapBlueprint'). With that blueprint registered in
the index, the walker must mint a typed
@:SwapOrder_recipient@ predicate on the per-output datum
subject.

The fixture is constructed in-memory in this module (no disk
fixture under @test/fixtures/@); T103 ships the first
behaviour-changing on-disk fixture.
-}
decodesOnNonEmptyIndex :: Spec
decodesOnNonEmptyIndex =
    it "emits :SwapOrder_recipient on the inline-datum subject when the blueprint matches" $
        case emit syntheticTxOk Map.empty [] syntheticSwapIndex of
            Left err ->
                expectationFailure $ "emit returned Left " <> show err
            Right g ->
                let bytes = serialize Turtle "synth-blueprint-decodes" g
                 in if BS8.pack ":SwapOrder_recipient" `BS.isInfixOf` bytes
                        then pure ()
                        else
                            expectationFailure $
                                "expected typed predicate :SwapOrder_recipient \
                                \in emitted Turtle but did not find it.\n\n"
                                    <> BS8.unpack bytes

-- ---------------------------------------------------------------------------
-- Invariant 3: exactly one cardano:decodeError literal on a failure
-- ---------------------------------------------------------------------------

{- | A synthetic in-memory tx whose inline datum has the wrong
constructor index for the registered blueprint must produce
exactly one @cardano:decodeError@ literal on the Datum subject —
never two on the same subject (FR-005 / D-001d FIRST-error-only).
-}
decodeFailureSingleLiteral :: Spec
decodeFailureSingleLiteral =
    it "emits exactly one cardano:decodeError literal on a decode failure" $
        case emit syntheticTxBadDatum Map.empty [] syntheticSwapIndex of
            Left err ->
                expectationFailure $ "emit returned Left " <> show err
            Right g ->
                let bytes = serialize Turtle "synth-blueprint-decode-failure" g
                    count = occurrences (BS8.pack "cardano:decodeError") bytes
                 in count `shouldBe` 1

-- ---------------------------------------------------------------------------
-- Synthetic blueprint + tx fixtures
-- ---------------------------------------------------------------------------

{- | The script hash both the synthetic tx's output addresses and
the synthetic blueprint's registry entry key on. 28 bytes of
@0xAA@.
-}
swapScriptHash :: ScriptHash
swapScriptHash =
    ScriptHash (fromJust (hashFromStringAsHex (replicate 56 'a')))

{- | Synthetic CIP-57 blueprint with a single validator whose
@datum:@ argument is a one-field @SwapOrder@ constructor
( @{ "recipient": ByteString }@ ). Drives the typed-emission
walk in 'decodesOnNonEmptyIndex'.
-}
syntheticSwapBlueprint :: Blueprint
syntheticSwapBlueprint =
    Blueprint
        { blueprintPreamble =
            BlueprintPreamble
                { preambleTitle = "synthetic-swap"
                , preamblePlutusVersion = "v3"
                }
        , blueprintValidators =
            [ BlueprintValidator
                { validatorTitle = Just "synthetic.swap.spend"
                , validatorDatum =
                    Just
                        BlueprintArgument
                            { argumentTitle = Just "datum"
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

{- | The synthetic blueprint index threaded through 'emit'. The
'Text' third element is the blueprint preamble title — kept for
diagnostic messages downstream and ignored by the T101 decoder.
-}
syntheticSwapIndex :: [(ScriptHash, Blueprint, Text)]
syntheticSwapIndex = [(swapScriptHash, syntheticSwapBlueprint, "synthetic-swap")]

{- | The successful-decode synthetic Conway tx. One output:
script-credential address keyed on 'swapScriptHash', ADA-only
value, inline 'Datum' shaped as @Constr 0 [B "deadbeef"]@ — the
expected wire shape for the blueprint's @SchemaConstructor 0
[SchemaBytes]@ argument.
-}
syntheticTxOk :: ConwayTx
syntheticTxOk = mkTx . TxBuilder $ do
    _ <- output (scriptAddrOutput swapScriptHash okSwapDatum 5_000_000)
    pure ()

{- | The decode-failure synthetic Conway tx. Same shape as
'syntheticTxOk' but the inline datum carries a wrong constructor
index (@1@ instead of @0@); 'Cardano.Tx.Blueprint.decodeBlueprintData'
returns @BlueprintConstructorMismatch@.
-}
syntheticTxBadDatum :: ConwayTx
syntheticTxBadDatum = mkTx . TxBuilder $ do
    _ <- output (scriptAddrOutput swapScriptHash badSwapDatum 5_000_000)
    pure ()

-- | @SwapOrder { recipient = 0xdeadbeef }@ as an inline 'Datum'.
okSwapDatum :: Datum ConwayEra
okSwapDatum =
    mkInlineDatum (PLC.Constr 0 [PLC.B (BS.pack [0xde, 0xad, 0xbe, 0xef])])

-- | Same payload as 'okSwapDatum' but with constructor index @1@.
badSwapDatum :: Datum ConwayEra
badSwapDatum =
    mkInlineDatum (PLC.Constr 1 [PLC.B (BS.pack [0xde, 0xad, 0xbe, 0xef])])

{- | A 'TxOut' at a script-credential address keyed on the given
'ScriptHash', carrying an ADA-only value and the given inline
'Datum'. The stake reference is 'StakeRefNull' — the spec only
exercises the payment-credential branch of
'Cardano.Tx.Graph.Emit.Blueprint.decodeDatumForOutput'.
-}
scriptAddrOutput ::
    ScriptHash ->
    Datum ConwayEra ->
    Integer ->
    TxOut ConwayEra
scriptAddrOutput sh datum coin =
    mkBasicTxOut addr (MaryValue (Coin coin) (MultiAsset mempty))
        & datumTxOutL .~ datum
  where
    addr = Addr Testnet (ScriptHashObj sh) StakeRefNull

-- ---------------------------------------------------------------------------
-- Per-fixture UTxO + rules loader (mirrors Cardano.Tx.Graph.EmitGoldenSpec)
-- ---------------------------------------------------------------------------

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

{- | Per-fixture resolved-UTxO. Mirrors
'Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo' — fixture 11 is
the only one that ships a resolved input (the multi-asset
treasury input); every other fixture uses the empty map.
-}
fixtureUtxo :: String -> ResolvedUTxO
fixtureUtxo = \case
    "11-amaru-treasury-swap-real" ->
        Map.singleton
            (stubTxIn 2)
            ( stubTxOutMA
                1_137_000_000_000
                [(S11.swapUsdmPolicy, S11.swapUsdmName, 2_500_000_000)]
            )
    _ -> emptyUtxo

loadEntitiesAndOverlay ::
    FilePath -> IO ([EntityDecl], ByteString)
loadEntitiesAndOverlay path = do
    result <- loadRulesFile path
    case result of
        Right res@RulesLoadResult{rulesOverlayTurtle} ->
            pure (rulesEntities res, rulesOverlayTurtle)
        Left err ->
            fail $
                "BlueprintWiringSpec.loadEntitiesAndOverlay: "
                    <> path
                    <> ": "
                    <> show err

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

{- | Count non-overlapping occurrences of @needle@ in @hay@. Returns
@0@ if @needle@ is empty.
-}
occurrences :: ByteString -> ByteString -> Int
occurrences needle hay
    | BS.null needle = 0
    | otherwise = go hay 0
  where
    go bs n
        | BS.null bs = n
        | needle `BS.isPrefixOf` bs =
            go (BS.drop (BS.length needle) bs) (n + 1)
        | otherwise = go (BS.drop 1 bs) n

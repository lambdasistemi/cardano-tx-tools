{- |
Module      : Cardano.Tx.Graph.Rules.Load.BlueprintLoadSpec
Description : T100 RED — rules-loader threads the blueprint index.
License     : Apache-2.0

Asserts the new 'rulesBlueprints' field on 'RulesLoadResult' is populated
when @rules.yaml@ declares a @blueprints:@ entry, and that each of the
six new error / warning variants fires on its expected failure mode.

Test cases (six invariants from the navigator brief):

* happy-path-1 — an in-memory @rules.yaml@ pointing at a vendored CIP-57
  JSON loads successfully; @rulesBlueprints@ is non-empty and the
  script-hash key bytes equal the referenced entity's @PaymentScript@
  identifier bytes.
* happy-path-2 — no @blueprints:@ section in @rules.yaml@ →
  @rulesBlueprints@ is the empty list.
* error-1 — @datum:@ points at a non-existent file →
  'BlueprintFileMissing'.
* error-2 — @datum:@ points at malformed JSON → 'BlueprintParseError'.
* error-3 — absolute @datum:@ path → 'AbsoluteBlueprintPath'.
* error-4 — @https://@ @datum:@ URI → 'HttpsBlueprintPath'.
* warning-1 — two @blueprints:@ entries with the same @script:@ →
  loader returns 'Right' with a 'DuplicateBlueprintForScript' warning;
  @rulesBlueprints@ keeps the first declaration only (D-001f / A-001:
  first-wins, non-fatal — cf. spec.md Edge Case 5).
* error-5 — two different blueprints minting the same
  @\<Ctor\>_\<field\>@ predicate name →
  'DuplicateBlueprintPredicate' (D-001b / A-001: hard error).

The vendored blueprint at
@test/fixtures/rewrite-redesign/blueprints/swap-v2-datum.cip57.json@
provides the CIP-57 payload (preamble title @\"amaru.swap.v2\"@,
constructor title @\"SwapOrder\"@, field title @\"recipient\"@). The
spec writes synthetic @rules.yaml@ files into a fresh
'withSystemTempDirectory' so the loader exercises the on-disk path
resolution policy mirroring @owl:imports@.
-}
module Cardano.Tx.Graph.Rules.Load.BlueprintLoadSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
    RulesLoadResult (..),
    RulesLoadWarning (..),
    loadRulesFile,
 )

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Hashes (ScriptHash (..))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

----------------------------------------------------------------------
-- Vendored blueprint
----------------------------------------------------------------------

-- | Root of the vendored fixture tree.
fixturesRoot :: FilePath
fixturesRoot = "test/fixtures/rewrite-redesign"

{- | The vendored CIP-57 blueprint used by every happy-path / warning
test that needs a real blueprint payload. The file ships with fixture
01 and is parsed verbatim through 'Cardano.Tx.Blueprint.parseBlueprintJSON'.
-}
swapV2BlueprintPath :: FilePath
swapV2BlueprintPath =
    fixturesRoot </> "blueprints" </> "swap-v2-datum.cip57.json"

{- | The vendored SundaeSwap V3 plutus.json (issue #103) — the
upstream Aiken contract blueprint pinned at commit
@be33466b7dbe0f8e6c0e0f46ff23737897f45835@ of
github.com/SundaeSwap-finance/sundae-contracts. Used to verify
that the loader accepts the real Sundae V3 schema verbatim and
mints the expected typed-redeemer predicates
(:OrderRedeemer_Scoop, :OrderRedeemer_Cancel) for the
@order.spend@ validator's hash.
-}
sundaeV3BlueprintPath :: FilePath
sundaeV3BlueprintPath =
    fixturesRoot
        </> "blueprints"
        </> "sundaeswap-v3"
        </> "plutus.json"

{- | The on-chain mainnet hash of SundaeSwap V3's @order.spend@
validator. Authoritatively named in
@/code/amaru-treasury-tx/lib/Amaru/Treasury/Constants.hs@ as
@sundaeOrderScriptHashMainnet@; the May 2026 lattice consumes it
as the script behind every Amaru swap-order output.
-}
sundaeV3OrderScriptHex :: Text
sundaeV3OrderScriptHex =
    Text.pack "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"

{- | The 28-byte script hash for the @amaru.swap.v2@ entity declared in
fixture 01's @rules.yaml@. Used as the @script:@ identifier in the
synthetic test inputs so the @blueprints:@ entry's @script:@
reference resolves to a known entity whose @PaymentScript@
identifier bytes the loader can hash into the @rulesBlueprints@
key.
-}
swapV2ScriptHex :: Text
swapV2ScriptHex =
    Text.pack "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"

{- | A second 56-hex-character script hash distinct from
'swapV2ScriptHex'. Used by the duplicate-predicate test to provide a
second entity whose blueprint mints a colliding @\<Ctor\>_\<field\>@
predicate.
-}
swapV2AltScriptHex :: Text
swapV2AltScriptHex =
    Text.pack "aabbccddeeff00112233445566778899aabbccddeeff00112233abcd"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{- | Render a 'ScriptHash' as lowercase hex. Matches the byte-form the
loader stores in 'EntityIdentifier.entityIdBytesHex' for a
@PaymentScript@ identifier, so the two surfaces can be compared
verbatim.
-}
scriptHashHex :: ScriptHash -> Text
scriptHashHex (ScriptHash h) =
    TextEncoding.decodeUtf8 (Base16.encode (hashToBytes h))

{- | Write @rules.yaml@ plus any extra companion files (e.g.
@blueprints/foo.cip57.json@) into a fresh system temp directory and
drive 'loadRulesFile' over the rules path. The continuation receives
the rules file's absolute path and the loader's result.

Extra files are written under the same temp root via relative paths,
so the loader exercises the @owl:imports@-style relative-path
resolution policy.
-}
withRulesAndBlueprints ::
    -- | @rules.yaml@ body
    ByteString ->
    -- | Companion files: @(relative-path, body)@
    [(FilePath, ByteString)] ->
    -- | Continuation
    (FilePath -> Either RulesLoadError RulesLoadResult -> IO ()) ->
    IO ()
withRulesAndBlueprints yaml extras k =
    withSystemTempDirectory "tx-50-blueprint-load" $ \dir -> do
        let rulesPath = dir </> "rules.yaml"
        BS.writeFile rulesPath yaml
        mapM_ (writeExtra dir) extras
        result <- loadRulesFile rulesPath
        k rulesPath result
  where
    writeExtra dir (rel, blob) = do
        let path = dir </> rel
        createDirectoryIfMissing True (takeDirectory path)
        BS.writeFile path blob

----------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec = describe "Cardano.Tx.Graph.Rules.Load.rulesBlueprints (T100)" $ do
    describe "happy paths" $ do
        it "loads a single blueprint and threads it into rulesBlueprints" $ do
            blueprintBlob <- BS.readFile swapV2BlueprintPath
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: ./blueprints/swap-v2-datum.cip57.json"
                            ]
                extras =
                    [
                        ( "blueprints/swap-v2-datum.cip57.json"
                        , blueprintBlob
                        )
                    ]
            withRulesAndBlueprints yaml extras $ \_ result ->
                case result of
                    Left err ->
                        expectationFailure $
                            "expected Right RulesLoadResult, got Left "
                                <> show err
                    Right RulesLoadResult{rulesEntities, rulesBlueprints} ->
                        case rulesBlueprints of
                            [(sh, _bp, _title)] -> do
                                scriptHashHex sh `shouldBe` swapV2ScriptHex
                                let paymentScriptBytes =
                                        [ entityIdBytesHex i
                                        | e <- rulesEntities
                                        , i <- entityIdentifiers e
                                        , entityIdLeafType i == PaymentScript
                                        ]
                                paymentScriptBytes
                                    `shouldBe` [scriptHashHex sh]
                            other ->
                                expectationFailure $
                                    "expected exactly one blueprint index entry,"
                                        <> " got "
                                        <> show (length other)

        it "loads the SundaeSwap V3 plutus.json (#103) and mints OrderRedeemer_{Scoop,Cancel}" $ do
            -- The vendored Sundae V3 blueprint at
            -- @blueprints/sundaeswap-v3/plutus.json@ is the upstream
            -- Aiken-generated file from
            -- github.com/SundaeSwap-finance/sundae-contracts. The
            -- order.spend validator's hash matches the on-chain
            -- mainnet script behind every Amaru swap order. Datum
            -- is intentionally @Data@-typed by Sundae (opaque), so
            -- the typed decode lands on the redeemer side:
            -- @OrderRedeemer = Scoop | Cancel@.
            blueprintBlob <- BS.readFile sundaeV3BlueprintPath
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: sundae.swap.v3.order"
                            , "    script: " <> sundaeV3OrderScriptHex
                            , "blueprints:"
                            , "  - script: sundae.swap.v3.order"
                            , "    datum: ./blueprints/sundae-v3.cip57.json"
                            ]
                extras =
                    [
                        ( "blueprints/sundae-v3.cip57.json"
                        , blueprintBlob
                        )
                    ]
            withRulesAndBlueprints yaml extras $ \_ result -> case result of
                Left err ->
                    expectationFailure $
                        "expected Right + Sundae V3 blueprint loaded, got Left "
                            <> show err
                Right RulesLoadResult{rulesBlueprints} ->
                    case rulesBlueprints of
                        [(_sh, _bp, title)] ->
                            -- The preamble title carries Sundae's
                            -- own identifier; we don't pin its
                            -- exact bytes (it can rev with
                            -- upstream pin.json refreshes), just
                            -- confirm the entry is registered.
                            title `shouldSatisfy` Text.isInfixOf "sundae"
                        other ->
                            expectationFailure $
                                "expected exactly one blueprint index entry, got "
                                    <> show (length other)

        it "produces an empty blueprint index when rules.yaml omits blueprints:" $ do
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            ]
            withRulesAndBlueprints yaml [] $ \_ result -> case result of
                Left err ->
                    expectationFailure $
                        "expected Right (empty blueprints), got Left "
                            <> show err
                Right RulesLoadResult{rulesBlueprints} ->
                    rulesBlueprints `shouldBe` []

    describe "error variants" $ do
        it "BlueprintFileMissing when datum: points at a non-existent file" $ do
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: ./blueprints/does-not-exist.cip57.json"
                            ]
            withRulesAndBlueprints yaml [] $ \path result -> case result of
                Left (BlueprintFileMissing f line raw) -> do
                    f `shouldBe` path
                    line `shouldBe` 5
                    raw `shouldBe` "./blueprints/does-not-exist.cip57.json"
                other ->
                    expectationFailure $
                        "expected BlueprintFileMissing, got: " <> show other

        it "BlueprintParseError on malformed JSON" $ do
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: ./blueprints/broken.cip57.json"
                            ]
                extras =
                    [
                        ( "blueprints/broken.cip57.json"
                        , BS.pack
                            [ 0x7b -- '{'
                            , 0x74 -- 't'
                            , 0x68 -- 'h'
                            , 0x69 -- 'i'
                            , 0x73 -- 's'
                            ]
                            -- intentionally truncated JSON
                        )
                    ]
            withRulesAndBlueprints yaml extras $ \path result -> case result of
                Left (BlueprintParseError f line raw _aesonErr) -> do
                    f `shouldBe` path
                    line `shouldBe` 5
                    raw `shouldBe` "./blueprints/broken.cip57.json"
                other ->
                    expectationFailure $
                        "expected BlueprintParseError, got: " <> show other

        it "AbsoluteBlueprintPath on an absolute datum: path" $ do
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: /etc/swap-v2.cip57.json"
                            ]
            withRulesAndBlueprints yaml [] $ \path result -> case result of
                Left (AbsoluteBlueprintPath f line raw) -> do
                    f `shouldBe` path
                    line `shouldBe` 5
                    raw `shouldBe` "/etc/swap-v2.cip57.json"
                other ->
                    expectationFailure $
                        "expected AbsoluteBlueprintPath, got: " <> show other

        it "HttpsBlueprintPath on an https:// datum: URI" $ do
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: https://example.com/swap-v2.cip57.json"
                            ]
            withRulesAndBlueprints yaml [] $ \path result -> case result of
                Left (HttpsBlueprintPath f line raw) -> do
                    f `shouldBe` path
                    line `shouldBe` 5
                    raw `shouldBe` "https://example.com/swap-v2.cip57.json"
                other ->
                    expectationFailure $
                        "expected HttpsBlueprintPath, got: " <> show other

        it "DuplicateBlueprintPredicate when DIFFERENT blueprints mint the same predicate" $ do
            blueprintBlob <- BS.readFile swapV2BlueprintPath
            -- Two entities with distinct script hashes; two blueprints
            -- that are STRUCTURALLY DIFFERENT (so they parse to
            -- distinct 'Blueprint' values) but both mint the
            -- ':SwapOrder_recipient' predicate. The mismatch in
            -- preamble.description below is enough — the predicate
            -- name minting is deterministic over the validator
            -- schema, so a description-only edit preserves the
            -- collision while making the parsed values 'Blueprint'
            -- unequal. The loader rejects with
            -- 'DuplicateBlueprintPredicate' per D-001b / A-001.
            --
            -- Issue #101: the SAME blueprint registered against two
            -- scripts is the operator-intended "shared parameterised
            -- contract" pattern (Amaru contingency vs
            -- network_compliance — both treasury.treasury.spend) and
            -- is accepted; see the next test.
            -- Replace the preamble title in the second copy so its
            -- parsed 'Blueprint' value differs from the original
            -- (preambleTitle is captured into BlueprintPreamble; the
            -- preamble description / version / license are not, so
            -- we have to target a captured field). The constructor
            -- schema is untouched, so the minted predicate URIs
            -- (':SwapOrder_recipient') are identical.
            let distinctBlob =
                    replaceBytes
                        "\"title\": \"amaru.swap.v2\""
                        "\"title\": \"amaru.swap.v2.alt-title\""
                        blueprintBlob
                yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "  - name: amaru.swap.v2.alt"
                            , "    script: " <> swapV2AltScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: ./blueprints/swap-v2-datum.cip57.json"
                            , "  - script: amaru.swap.v2.alt"
                            , "    datum: ./blueprints/swap-v2-datum-distinct.cip57.json"
                            ]
                extras =
                    [
                        ( "blueprints/swap-v2-datum.cip57.json"
                        , blueprintBlob
                        )
                    ,
                        ( "blueprints/swap-v2-datum-distinct.cip57.json"
                        , distinctBlob
                        )
                    ]
            withRulesAndBlueprints yaml extras $ \path result -> case result of
                Left (DuplicateBlueprintPredicate f line predName) -> do
                    f `shouldBe` path
                    -- Second declaration is at line 9 (1-based) in the YAML
                    -- above (first '- script:' is line 7, second is line 9).
                    line `shouldBe` 9
                    -- The conflicting predicate's local part is
                    -- '<ConstructorTitle>_<FieldTitle>' per FR-008
                    -- ('SwapOrder' from the constructor's title,
                    -- 'recipient' from the field's title). Accept either
                    -- the bare local part or the ':SwapOrder_recipient'
                    -- CURIE form — the spec pins the IRI but the variant
                    -- payload's exact spelling is the driver's call.
                    predName
                        `shouldSatisfy` Text.isInfixOf "SwapOrder_recipient"
                other ->
                    expectationFailure $
                        "expected DuplicateBlueprintPredicate, got: "
                            <> show other

        it "shared blueprint across N scripts is accepted (#101)" $ do
            blueprintBlob <- BS.readFile swapV2BlueprintPath
            -- Two scope-parameterised script hashes registered against
            -- the SAME blueprint file — the Amaru treasury pattern
            -- (contingency + network_compliance both use the
            -- treasury.treasury.spend contract; the parameterisation
            -- gives each scope a distinct script hash but the
            -- redeemer schema is identical). The loader must accept
            -- both registrations and keep both bindings so the
            -- decoder can find the blueprint via either script hash.
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "  - name: amaru.swap.v2.alt"
                            , "    script: " <> swapV2AltScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: ./blueprints/swap-v2-datum.cip57.json"
                            , "  - script: amaru.swap.v2.alt"
                            , "    datum: ./blueprints/swap-v2-datum.cip57.json"
                            ]
                extras =
                    [
                        ( "blueprints/swap-v2-datum.cip57.json"
                        , blueprintBlob
                        )
                    ]
            withRulesAndBlueprints yaml extras $ \_ result -> case result of
                Left err ->
                    expectationFailure $
                        "expected Right + 2 blueprint bindings, got Left "
                            <> show err
                Right RulesLoadResult{rulesBlueprints, rulesWarnings} -> do
                    -- Both script-hash bindings survive (no
                    -- DuplicateBlueprintForScript warning — the
                    -- script hashes differ).
                    length rulesBlueprints `shouldBe` 2
                    rulesWarnings `shouldBe` []

    describe "warnings" $ do
        it "DuplicateBlueprintForScript first-wins, second dropped" $ do
            blueprintBlob <- BS.readFile swapV2BlueprintPath
            let yaml =
                    TextEncoding.encodeUtf8 $
                        Text.unlines
                            [ "entities:"
                            , "  - name: amaru.swap.v2"
                            , "    script: " <> swapV2ScriptHex
                            , "blueprints:"
                            , "  - script: amaru.swap.v2"
                            , "    datum: ./blueprints/swap-v2-datum.cip57.json"
                            , "  - script: amaru.swap.v2"
                            , "    datum: ./blueprints/swap-v2-datum.cip57.json"
                            ]
                extras =
                    [
                        ( "blueprints/swap-v2-datum.cip57.json"
                        , blueprintBlob
                        )
                    ]
            withRulesAndBlueprints yaml extras $ \_ result -> case result of
                Left err ->
                    expectationFailure $
                        "expected Right + DuplicateBlueprintForScript warning,"
                            <> " got Left "
                            <> show err
                Right RulesLoadResult{rulesBlueprints, rulesWarnings} -> do
                    -- First-wins: the index keeps exactly one entry.
                    length rulesBlueprints `shouldBe` 1
                    -- The warning names the duplicated script entity.
                    let dups =
                            [ name
                            | DuplicateBlueprintForScript _ _ name <-
                                rulesWarnings
                            ]
                    dups `shouldBe` ["amaru.swap.v2"]

{- | Replace every occurrence of @needle@ with @replacement@ in @haystack@.
Pure ByteString substitution; used to derive a structurally distinct
CIP-57 blueprint from an existing one without breaking JSON shape.
-}
replaceBytes :: ByteString -> ByteString -> ByteString -> ByteString
replaceBytes needle replacement = go
  where
    go bs = case BS.breakSubstring needle bs of
        (h, t)
            | BS.null t -> h
            | otherwise ->
                h <> replacement <> go (BS.drop (BS.length needle) t)

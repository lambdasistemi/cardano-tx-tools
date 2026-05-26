{- |
Module      : Cardano.Tx.Graph.Rules.LoadYamlSpec
Description : T002 unit tests for the YAML entities parser.
License     : Apache-2.0

Covers the in-memory @'parseRulesYamlText' :: ByteString -> Either
'RulesLoadError' ['EntityDecl']@ path: the @from-address@, @script@,
and @asset@ entity shapes, the six Conway base/enterprise address
classes (the cross-product of payment ∈ {Key,Script} and
stake ∈ {Key,Script,enterprise}), the slugify algorithm
(snake_case with @[^a-z0-9]@ → @_@, repeat collapse, end-trim) and
the two slug edge-cases (empty slug + leading-digit slug).

Per Q-001/A-001 the slug is used for both the entity IRI local-part
and the bnode prefix; the test only inspects the slug field — the
Turtle serializer is T003's responsibility.
-}
module Cardano.Tx.Graph.Rules.LoadYamlSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    Attestation (..),
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
    RulesLoadResult (..),
    loadRulesFile,
    parseRulesYamlText,
 )

import Cardano.Crypto.Hash (Hash, HashAlgorithm, hashFromBytes)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (Mainnet))
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefBase, StakeRefNull),
 )
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..))
import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Rules.Load.parseRulesYamlText (T002)" $ do
    describe "happy path" $ do
        it "returns [] for an empty YAML document" $ do
            parseRulesYamlText "" `shouldBe` Right []

        it "returns [] when the document has no entities: key" $ do
            parseRulesYamlText "blueprints: []\n" `shouldBe` Right []

        it "parses a single from-address (PaymentKey + StakeKey)" $ do
            -- A real mainnet base-address from the rewrite-redesign
            -- fixture-02 corpus. The decoded payment / stake hashes
            -- are the ground-truth bytes the ledger decoder produces
            -- (the fixture's expected.ttl pre-T002 used artisanal,
            -- unrelated bytes; we ignore that and trust the decoder).
            let yaml =
                    "entities:\n\
                    \  - name: alice\n\
                    \    from-address: "
                        <> aliceBech32Mainnet
                        <> "\n"
            parseRulesYamlText (TextEncoding.encodeUtf8 yaml)
                `shouldBe` Right
                    [ EntityDecl
                        { entityName = "alice"
                        , entitySlug = "alice"
                        , entityIdentifiers =
                            [ EntityIdentifier
                                PaymentKey
                                "8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1"
                            , EntityIdentifier
                                StakeKey
                                "4c7889c658ef4f491a34cf79c35a2e0fe6b0d1b0a856fb9580f2d9c3"
                            ]
                        , entityBech32 = Just aliceBech32Mainnet
                        , entityRole = Nothing
                        , entityPaidVia = Nothing
                        , entitySourceFile = inMemoryFile
                        }
                    ]

        it "parses a single script (PaymentScript) entity" $ do
            let yaml =
                    "entities:\n\
                    \  - name: my-script\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            parseRulesYamlText yaml
                `shouldBe` Right
                    [ EntityDecl
                        { entityName = "my-script"
                        , entitySlug = "my_script"
                        , entityIdentifiers =
                            [ EntityIdentifier
                                PaymentScript
                                "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"
                            ]
                        , entityBech32 = Nothing
                        , entityRole = Nothing
                        , entityPaidVia = Nothing
                        , entitySourceFile = inMemoryFile
                        }
                    ]

        it "parses an asset shape — bytesHex = policy ++ hex(ascii(name))" $ do
            let yaml =
                    "entities:\n\
                    \  - name: usdm\n\
                    \    asset: { policy: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad, name: USDM }\n"
            -- "USDM" → 55 53 44 4d (4 bytes ASCII = 8 hex chars).
            parseRulesYamlText yaml
                `shouldBe` Right
                    [ EntityDecl
                        { entityName = "usdm"
                        , entitySlug = "usdm"
                        , entityIdentifiers =
                            [ EntityIdentifier
                                AssetClass
                                "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad5553444d"
                            ]
                        , entityBech32 = Nothing
                        , entityRole = Nothing
                        , entityPaidVia = Nothing
                        , entitySourceFile = inMemoryFile
                        }
                    ]

        it "parses a compound-key (keys + bytes) entity — N identifiers share bytesHex" $ do
            -- Fixture-04's usdm-control declaration. The 28-byte hash
            -- is replicated under PaymentScript and Policy leafTypes,
            -- in source order matching the keys: list.
            let yaml =
                    "entities:\n\
                    \  - name: usdm-control\n\
                    \    keys: [PaymentScript, Policy]\n\
                    \    bytes: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad\n"
            parseRulesYamlText yaml
                `shouldBe` Right
                    [ EntityDecl
                        { entityName = "usdm-control"
                        , entitySlug = "usdm_control"
                        , entityIdentifiers =
                            [ EntityIdentifier
                                PaymentScript
                                "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad"
                            , EntityIdentifier
                                Policy
                                "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad"
                            ]
                        , entityBech32 = Nothing
                        , entityRole = Nothing
                        , entityPaidVia = Nothing
                        , entitySourceFile = inMemoryFile
                        }
                    ]

        it "parses multiple entities in source order" $ do
            let yaml =
                    "entities:\n\
                    \  - name: alpha\n\
                    \    script: 0123456789abcdef0123456789abcdef0123456789abcdef01234567\n\
                    \  - name: beta\n\
                    \    asset: { policy: aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc, name: MEME }\n"
            parseRulesYamlText yaml
                `shouldBe` Right
                    [ EntityDecl
                        "alpha"
                        "alpha"
                        [ EntityIdentifier
                            PaymentScript
                            "0123456789abcdef0123456789abcdef0123456789abcdef01234567"
                        ]
                        Nothing
                        Nothing
                        Nothing
                        inMemoryFile
                    , EntityDecl
                        "beta"
                        "beta"
                        [ EntityIdentifier
                            AssetClass
                            "aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc4d454d45"
                        ]
                        Nothing
                        Nothing
                        Nothing
                        inMemoryFile
                    ]

        it "accepts an overlay-only entity (paid-via, no identifier) — #105" $ do
            -- Issue #105: an entity with no on-chain identifier
            -- shape but a `paid-via:` cross-reference is a
            -- valid off-chain overlay entry. Round-trips through
            -- the YAML parser with empty 'entityIdentifiers' and
            -- 'entityPaidVia' = Just <slugified-name>.
            let yaml =
                    "entities:\n\
                    \  - name: amaru.cag-payee\n\
                    \    from-address: addr1q8qrds2nnx7clx3kcpp2l0eu45twmdcahsfu9m0xcwy59j6xz3vs0hnfaz9nhje8z34kfnds4jyk7hs6dnrag6e2lfgqtyf4rl\n\
                    \  - name: amaru.antithesis\n\
                    \    label: \"Antithesis Operations LLC\"\n\
                    \    role: fuzz-testing vendor\n\
                    \    paid-via: amaru.cag-payee\n"
            case parseRulesYamlText (TextEncoding.encodeUtf8 yaml) of
                Right [_cagPayee, ent] -> do
                    entitySlug ent `shouldBe` "amaru_antithesis"
                    entityIdentifiers ent `shouldBe` []
                    entityPaidVia ent `shouldBe` Just "amaru_cag_payee"
                    entityRole ent `shouldBe` Just "fuzz-testing vendor"
                    entityBech32 ent `shouldBe` Nothing
                other ->
                    expectationFailure $
                        "expected Right [cag-payee, antithesis], got: "
                            <> show other

    describe "six Conway address classes (FR-005)" $ do
        it "PaymentKey + StakeKey (base, key+key)" $
            decomposeAddrShouldBe
                (mkAddr (KeyHashObj keyHashPayment) (StakeRefBase (KeyHashObj keyHashStake)))
                [ EntityIdentifier PaymentKey paymentKeyBytesHex
                , EntityIdentifier StakeKey stakeKeyBytesHex
                ]
        it "PaymentKey + StakeScript (base, key+script)" $
            decomposeAddrShouldBe
                (mkAddr (KeyHashObj keyHashPayment) (StakeRefBase (ScriptHashObj scriptHashStake)))
                [ EntityIdentifier PaymentKey paymentKeyBytesHex
                , EntityIdentifier StakeScript scriptStakeBytesHex
                ]
        it "PaymentScript + StakeKey (base, script+key)" $
            decomposeAddrShouldBe
                (mkAddr (ScriptHashObj scriptHashPayment) (StakeRefBase (KeyHashObj keyHashStake)))
                [ EntityIdentifier PaymentScript scriptPaymentBytesHex
                , EntityIdentifier StakeKey stakeKeyBytesHex
                ]
        it "PaymentScript + StakeScript (base, script+script)" $
            decomposeAddrShouldBe
                (mkAddr (ScriptHashObj scriptHashPayment) (StakeRefBase (ScriptHashObj scriptHashStake)))
                [ EntityIdentifier PaymentScript scriptPaymentBytesHex
                , EntityIdentifier StakeScript scriptStakeBytesHex
                ]
        it "PaymentKey, enterprise (no stake)" $
            decomposeAddrShouldBe
                (mkAddr (KeyHashObj keyHashPayment) StakeRefNull)
                [EntityIdentifier PaymentKey paymentKeyBytesHex]
        it "PaymentScript, enterprise (no stake)" $
            decomposeAddrShouldBe
                (mkAddr (ScriptHashObj scriptHashPayment) StakeRefNull)
                [EntityIdentifier PaymentScript scriptPaymentBytesHex]

    describe "slug edge cases" $ do
        it "empty slug after normalization → EntityNameSlugEmpty" $ do
            let yaml =
                    "entities:\n\
                    \  - name: \"---\"\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            case parseRulesYamlText yaml of
                Left (EntityNameSlugEmpty _ _ original) ->
                    original `shouldBe` "---"
                other ->
                    fail $ "expected EntityNameSlugEmpty, got: " <> show other

        it "leading-digit slug → EntityNameSlugLeadingDigit" $ do
            let yaml =
                    "entities:\n\
                    \  - name: 9lives\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            case parseRulesYamlText yaml of
                Left (EntityNameSlugLeadingDigit _ _ original) ->
                    original `shouldBe` "9lives"
                other ->
                    fail $ "expected EntityNameSlugLeadingDigit, got: " <> show other

        it "rewrites dots and dashes to underscores; collapses runs" $ do
            let yaml =
                    "entities:\n\
                    \  - name: amaru-treasury.network__compliance\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            case parseRulesYamlText yaml of
                Right [decl] ->
                    entitySlug decl `shouldBe` "amaru_treasury_network_compliance"
                other ->
                    fail $ "expected single Right decl, got: " <> show other

    describe "attestations (#105)" $ do
        it "parses an attestations block alongside entities" $ do
            -- End-to-end via the public 'loadRulesFile' surface so
            -- the test exercises the same path the CLI uses.
            let yaml =
                    "entities:\n\
                    \  - name: amaru.cag-payee\n\
                    \    from-address: addr1q8qrds2nnx7clx3kcpp2l0eu45twmdcahsfu9m0xcwy59j6xz3vs0hnfaz9nhje8z34kfnds4jyk7hs6dnrag6e2lfgqtyf4rl\n\
                    \  - name: amaru.antithesis\n\
                    \    paid-via: amaru.cag-payee\n\
                    \attestations:\n\
                    \  - ipfs: ipfs://bafkreicnoadlgnc6cqxggxboho7yt532lkonxcusj3ndsxdnv5szyswyam\n\
                    \    label: \"Invoice INV-635\"\n\
                    \    of: amaru.antithesis\n\
                    \  - ipfs: ipfs://bafybeib3jef34ndw6oe24mkmifdvxe5jrv7ulh63rdllovyth27mqfj2da\n\
                    \    label: \"Bridge contract\"\n\
                    \    of: amaru.cag-payee\n"
            withSystemTempDirectory "tx-105-attestations" $ \dir -> do
                let rulesPath = dir </> "rules.yaml"
                BS.writeFile rulesPath (TextEncoding.encodeUtf8 yaml)
                result <- loadRulesFile rulesPath
                case result of
                    Right RulesLoadResult{rulesAttestations = [a1, a2]} -> do
                        attestationLabel a1 `shouldBe` "Invoice INV-635"
                        attestationOf a1 `shouldBe` "amaru_antithesis"
                        attestationIpfs a1
                            `shouldBe` "ipfs://bafkreicnoadlgnc6cqxggxboho7yt532lkonxcusj3ndsxdnv5szyswyam"
                        attestationOf a2 `shouldBe` "amaru_cag_payee"
                    other ->
                        expectationFailure $
                            "expected Right with 2 attestations, got: " <> show other

    describe "structural errors" $ do
        it "rejects an entity with zero identifier shapes (no from-address/script/asset)" $ do
            let yaml =
                    "entities:\n\
                    \  - name: orphan\n"
            parseRulesYamlText yaml
                `shouldSatisfy` isEntityZeroIdentifiers

        it "rejects keys: without bytes: (orphan compound key)" $ do
            let yaml =
                    "entities:\n\
                    \  - name: orphan-keys\n\
                    \    keys: [PaymentScript, Policy]\n"
            parseRulesYamlText yaml `shouldSatisfy` isParserError

        it "rejects bytes: without keys: (orphan compound bytes)" $ do
            let yaml =
                    "entities:\n\
                    \  - name: orphan-bytes\n\
                    \    bytes: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad\n"
            parseRulesYamlText yaml `shouldSatisfy` isParserError

        it "rejects keys+bytes mixed with another identifier shape (multi-shape mix)" $ do
            let yaml =
                    "entities:\n\
                    \  - name: mixed\n\
                    \    keys: [PaymentScript, Policy]\n\
                    \    bytes: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            parseRulesYamlText yaml `shouldSatisfy` isParserError

    describe "shared identity (first-entity-wins, T005)" $ do
        it "two entities share a (leafType, bytesHex) pair — both decls present, identifier block emitted exactly once" $ do
            -- Two entities point at the same 28-byte script hash. The
            -- first entity owns the identifier bnode name (its own
            -- slug + roleSuffix); the second entity references the
            -- same bnode in its hasIdentifier line without
            -- re-declaring the identifier block. Verified by
            -- byte-substring search over the overlay output produced
            -- via the public 'loadRulesFile' surface (temp file).
            let yaml =
                    "entities:\n\
                    \  - name: foo\n\
                    \    script: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n\
                    \  - name: bar\n\
                    \    script: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
            case parseRulesYamlText yaml of
                Right [decl1, decl2] -> do
                    entityIdentifiers decl1
                        `shouldBe` [ EntityIdentifier
                                        PaymentScript
                                        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                                   ]
                    entityIdentifiers decl2
                        `shouldBe` [ EntityIdentifier
                                        PaymentScript
                                        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                                   ]
                other ->
                    fail $ "expected two Right decls, got: " <> show other
            overlay <- runLoaderViaTempFile yaml
            -- Both entity decls appear.
            assertByteSubstring overlay ":foo a cardano:Entity"
            assertByteSubstring overlay ":bar a cardano:Entity"
            -- The shared bnode name is wired into both entities'
            -- hasIdentifier lines.
            assertByteSubstring
                overlay
                "  cardano:hasIdentifier _:foo_paymentScript ."
            assertByteSubstring
                overlay
                "  cardano:hasIdentifier _:foo_paymentScript ."
            -- The shared identifier block is emitted exactly once.
            let blockHeader = "_:foo_paymentScript a cardano:Identifier ;"
                occurrences = byteOccurrences overlay blockHeader
            if occurrences == 1
                then pure ()
                else
                    expectationFailure $
                        "expected the shared identifier block to be"
                            <> " emitted exactly once, got "
                            <> show occurrences
                            <> " occurrence(s)"
            -- No bnode named after the second entity gets emitted.
            byteOccurrences
                overlay
                "_:bar_paymentScript a cardano:Identifier"
                `shouldBe` 0

    describe "blueprints: top-level shape (T005)" $ do
        it "accepts a well-formed blueprints: entry whose script: names a script entity" $ do
            let yaml =
                    "entities:\n\
                    \  - name: foo.script\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n\
                    \blueprints:\n\
                    \  - script: foo.script\n\
                    \    datum: ./blueprints/foo.cip57.json\n"
            case parseRulesYamlText yaml of
                Right [decl] ->
                    entityName decl `shouldBe` "foo.script"
                other ->
                    fail $ "expected single Right decl, got: " <> show other

        it "rejects a blueprints: entry whose script: references an unknown entity" $ do
            let yaml =
                    "entities:\n\
                    \  - name: foo.script\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n\
                    \blueprints:\n\
                    \  - script: bar.absent\n\
                    \    datum: ./blueprints/bar.cip57.json\n"
            case parseRulesYamlText yaml of
                Left (BlueprintRefsUnknownScript _ _ refName) ->
                    refName `shouldBe` "bar.absent"
                other ->
                    fail $
                        "expected BlueprintRefsUnknownScript, got: " <> show other

        it "rejects a blueprints: entry whose script: references a non-script entity (from-address)" $ do
            -- Even though the referenced entity exists, it carries no
            -- PaymentScript identifier (its only identifier is
            -- PaymentKey + StakeKey), so the blueprint reference is
            -- ill-formed.
            let yaml =
                    "entities:\n\
                    \  - name: alice\n\
                    \    from-address: "
                        <> aliceBech32Mainnet
                        <> "\n\
                           \blueprints:\n\
                           \  - script: alice\n\
                           \    datum: ./blueprints/x.cip57.json\n"
            case parseRulesYamlText (TextEncoding.encodeUtf8 yaml) of
                Left (BlueprintRefsUnknownScript _ _ refName) ->
                    refName `shouldBe` "alice"
                other ->
                    fail $
                        "expected BlueprintRefsUnknownScript, got: " <> show other

        it "accepts a blueprints: entry whose script: references a compound-key entity carrying PaymentScript" $ do
            -- usdm-control declares keys: [PaymentScript, Policy] — the
            -- PaymentScript leafType is present, so the blueprint
            -- reference is well-formed.
            let yaml =
                    "entities:\n\
                    \  - name: usdm-control\n\
                    \    keys: [PaymentScript, Policy]\n\
                    \    bytes: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad\n\
                    \blueprints:\n\
                    \  - script: usdm-control\n\
                    \    datum: ./blueprints/usdm.cip57.json\n"
            parseRulesYamlText yaml `shouldSatisfy` isRightSingleton

    describe "collapse: top-level shape (T005)" $ do
        it "silently accepts a top-level collapse: list (no triples are emitted)" $ do
            let yaml =
                    "entities:\n\
                    \  - name: foo\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n\
                    \collapse:\n\
                    \  - name: SwapOrderInput\n\
                    \    at: body.inputs\n\
                    \    match:\n\
                    \      required:\n\
                    \        - resolved.address\n\
                    \    view: omit\n"
            parseRulesYamlText yaml `shouldSatisfy` isRightSingleton

        it "rejects a non-list collapse: value (shape guard)" $ do
            let yaml =
                    "entities:\n\
                    \  - name: foo\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n\
                    \collapse: notalist\n"
            parseRulesYamlText yaml `shouldSatisfy` isParserError

isEntityZeroIdentifiers :: Either RulesLoadError [EntityDecl] -> Bool
isEntityZeroIdentifiers (Left EntityZeroIdentifiers{}) = True
isEntityZeroIdentifiers _ = False

isParserError :: Either RulesLoadError [EntityDecl] -> Bool
isParserError (Left ParserError{}) = True
isParserError _ = False

isRightSingleton :: Either RulesLoadError [EntityDecl] -> Bool
isRightSingleton (Right [_]) = True
isRightSingleton _ = False

{- | The placeholder source-file path the in-memory parser entry
points stamp onto every produced 'EntityDecl'. Mirrors the
@inMemoryFile@ constant in
"Cardano.Tx.Graph.Rules.Load.Parse.Yaml"; the assertion sites in
this spec compare expected 'EntityDecl' values verbatim, so the
test reproduces the same string here rather than depending on an
internal export.
-}
inMemoryFile :: FilePath
inMemoryFile = "<in-memory>"

{- | Drive the public 'loadRulesFile' surface over an in-memory YAML
blob by writing it to a temp file and reading back the serialized
overlay bytes. Used by the shared-identity test to assert byte
presence (the parser-only AST surface cannot prove that the
serializer emits the deduplicated bnode block exactly once).
-}
runLoaderViaTempFile :: BS.ByteString -> IO BS.ByteString
runLoaderViaTempFile blob =
    withSystemTempDirectory "tx-48-yaml-spec" $ \dir -> do
        let path = dir </> "rules.yaml"
        BS.writeFile path blob
        result <- loadRulesFile path
        case result of
            Left err ->
                fail $
                    "runLoaderViaTempFile: loadRulesFile failed: "
                        <> show err
            Right RulesLoadResult{rulesOverlayTurtle = bs} -> pure bs

-- | Assert that @needle@ appears at least once inside @haystack@.
assertByteSubstring :: BS.ByteString -> BS.ByteString -> IO ()
assertByteSubstring haystack needle =
    if needle `BS.isInfixOf` haystack
        then pure ()
        else
            expectationFailure $
                "expected substring not found in overlay bytes: "
                    <> show needle

-- | Count occurrences of @needle@ inside @haystack@.
byteOccurrences :: BS.ByteString -> BS.ByteString -> Int
byteOccurrences haystack needle
    | BS.null needle = 0
    | otherwise = go 0 haystack
  where
    go n hs = case BS.breakSubstring needle hs of
        (_, rest)
            | BS.null rest -> n
            | otherwise -> go (n + 1) (BS.drop (BS.length needle) rest)

----------------------------------------------------------------------
-- Address synthesis helpers
----------------------------------------------------------------------

{- | Construct a Cardano mainnet 'Addr' and bech32-encode it under
@addr@ HRP, then feed it through 'parseRulesYamlText' as a
@from-address:@ entity called @synth@. Asserts the produced
'entityIdentifiers' match the expected list.
-}
decomposeAddrShouldBe :: Addr -> [EntityIdentifier] -> IO ()
decomposeAddrShouldBe addr expected = do
    let bech32 = encodeMainnetAddr addr
        yaml =
            "entities:\n\
            \  - name: synth\n\
            \    from-address: "
                <> bech32
                <> "\n"
    parseRulesYamlText (TextEncoding.encodeUtf8 yaml)
        `shouldBe` Right
            [ EntityDecl
                "synth"
                "synth"
                expected
                (Just bech32)
                Nothing
                Nothing
                inMemoryFile
            ]

encodeMainnetAddr :: Addr -> Text
encodeMainnetAddr a =
    let hrp = either (error . show) id $ Bech32.humanReadablePartFromText "addr"
        dataPart = Bech32.dataPartFromBytes (serialiseAddr a)
     in Bech32.encodeLenient hrp dataPart

mkAddr :: Credential payment -> StakeReference -> Addr
mkAddr p = Addr Mainnet (unsafeCoercePayment p)

{- | The 'Addr' constructor pins payment to @Credential Payment@; the
KeyRole phantom is irrelevant at the byte level, so we coerce.
-}
unsafeCoercePayment :: Credential payment -> Credential payment'
unsafeCoercePayment (KeyHashObj (KeyHash h)) = KeyHashObj (KeyHash h)
unsafeCoercePayment (ScriptHashObj sh) = ScriptHashObj sh

----------------------------------------------------------------------
-- Fixed test bytes
----------------------------------------------------------------------

-- | A 28-byte ed25519 verification-key hash (payment role).
paymentKeyBytesHex :: Text
paymentKeyBytesHex = "601f58e4436698104adbbda7bc9d8f3f10e9e49652f9799d6c63aeda"

-- | A 28-byte ed25519 verification-key hash (stake role).
stakeKeyBytesHex :: Text
stakeKeyBytesHex = "80226c84b26fe1a280649d819757ff2ffaec51adca5a3780356c05bf"

-- | A 28-byte payment-script hash.
scriptPaymentBytesHex :: Text
scriptPaymentBytesHex = "32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d"

{- | A 28-byte stake-script hash (chosen distinct from the payment one
so the test surface confirms the loader does not confuse the two).
-}
scriptStakeBytesHex :: Text
scriptStakeBytesHex = "9100eb83504e21b27158c84a9f89ecea2c52ee6d5da6699aa42ea906"

keyHashPayment :: KeyHash kr
keyHashPayment = KeyHash (mk28 paymentKeyBytesHex)

keyHashStake :: KeyHash kr
keyHashStake = KeyHash (mk28 stakeKeyBytesHex)

scriptHashPayment :: ScriptHash
scriptHashPayment = ScriptHash (mk28 scriptPaymentBytesHex)

scriptHashStake :: ScriptHash
scriptHashStake = ScriptHash (mk28 scriptStakeBytesHex)

mk28 :: (HashAlgorithm h) => Text -> Hash h a
mk28 hex =
    case Base16.decode (TextEncoding.encodeUtf8 hex) of
        Right bs
            | BS.length bs == 28 -> fromJust (hashFromBytes bs)
        _ -> error ("mk28: expected 28-byte hex, got: " <> Text.unpack hex)

{- | The well-known fixture-02 alice mainnet base address (PaymentKey +
StakeKey).
-}
aliceBech32Mainnet :: Text
aliceBech32Mainnet =
    "addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz"

{- |
Module      : Cardano.Tx.Graph.Rules.LoadTurtleSpec
Description : T006 unit tests for the structural Turtle parser.
License     : Apache-2.0

Covers the @.ttl@ surface of the rules loader:

* small in-line Turtle blobs are parsed into the expected
  @['EntityDecl']@ shape;
* a round-trip test asserts that the same content authored as YAML
  and as Turtle produces byte-equal @rulesOverlayTurtle@ output (the
  co-equality requirement, spec SC-005);
* out-of-scope Turtle constructs (collections, blank-node property
  lists, language tags, datatype suffixes, multiline strings, boolean
  literals) are rejected with a structured 'ParserError';
* @owl:imports@ triples are recognized but their target is not
  followed in this slice (T007's surface).

The parser drives the same naming algorithm as the YAML compiler, so
operator-typed bnode names in the input are normalized to the
deterministic @\<entitySlug\>_\<roleSuffix\>@ form before the
serializer renders them.
-}
module Cardano.Tx.Graph.Rules.LoadTurtleSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadError (..),
    RulesLoadResult (..),
    loadRulesFile,
    parseRulesTurtleText,
 )

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text.Encoding qualified as TextEncoding
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Rules.Load.parseRulesTurtleText (T006)" $ do
    describe "happy path" $ do
        it "parses a single entity with two identifiers" $ do
            let ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:alice a cardano:Entity ;\n\
                    \  rdfs:label \"alice\" ;\n\
                    \  cardano:hasIdentifier _:alice_paymentKey ;\n\
                    \  cardano:hasIdentifier _:alice_stakeKey .\n\
                    \\n\
                    \_:alice_paymentKey a cardano:Identifier ;\n\
                    \  cardano:leafType \"PaymentKey\" ;\n\
                    \  cardano:bytesHex \"8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1\" .\n\
                    \\n\
                    \_:alice_stakeKey a cardano:Identifier ;\n\
                    \  cardano:leafType \"StakeKey\" ;\n\
                    \  cardano:bytesHex \"4c7889c658ef4f491a34cf79c35a2e0fe6b0d1b0a856fb9580f2d9c3\" .\n"
            parseRulesTurtleText (TextEncoding.encodeUtf8 ttl)
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
                        , entityBech32 = Nothing
                        , entitySourceFile = inMemoryFile
                        }
                    ]

        it "parses two entities preserving source order" $ do
            let ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:alpha a cardano:Entity ;\n\
                    \  rdfs:label \"alpha\" ;\n\
                    \  cardano:hasIdentifier _:alpha_paymentScript .\n\
                    \\n\
                    \_:alpha_paymentScript a cardano:Identifier ;\n\
                    \  cardano:leafType \"PaymentScript\" ;\n\
                    \  cardano:bytesHex \"0123456789abcdef0123456789abcdef0123456789abcdef01234567\" .\n\
                    \\n\
                    \:beta a cardano:Entity ;\n\
                    \  rdfs:label \"beta\" ;\n\
                    \  cardano:hasIdentifier _:beta_assetClass .\n\
                    \\n\
                    \_:beta_assetClass a cardano:Identifier ;\n\
                    \  cardano:leafType \"AssetClass\" ;\n\
                    \  cardano:bytesHex \"aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc4d454d45\" .\n"
            parseRulesTurtleText (TextEncoding.encodeUtf8 ttl)
                `shouldBe` Right
                    [ EntityDecl
                        "alpha"
                        "alpha"
                        [ EntityIdentifier
                            PaymentScript
                            "0123456789abcdef0123456789abcdef0123456789abcdef01234567"
                        ]
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
                        inMemoryFile
                    ]

        it "ignores comments and accepts owl:imports triples without failing" $ do
            -- owl:imports is recognized structurally in T006; its
            -- target is NOT followed yet (T007's surface). The
            -- parser must accept the triple shape and continue.
            let ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                    \@prefix owl:     <http://www.w3.org/2002/07/owl#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \# This is a comment line.\n\
                    \: owl:imports <./other.ttl> .\n\
                    \\n\
                    \:foo a cardano:Entity ; # inline comment\n\
                    \  rdfs:label \"foo\" ;\n\
                    \  cardano:hasIdentifier _:foo_paymentScript .\n\
                    \\n\
                    \_:foo_paymentScript a cardano:Identifier ;\n\
                    \  cardano:leafType \"PaymentScript\" ;\n\
                    \  cardano:bytesHex \"fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\" .\n"
            parseRulesTurtleText (TextEncoding.encodeUtf8 ttl)
                `shouldBe` Right
                    [ EntityDecl
                        "foo"
                        "foo"
                        [ EntityIdentifier
                            PaymentScript
                            "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"
                        ]
                        Nothing
                        inMemoryFile
                    ]

    describe "out-of-scope constructs are rejected (research R1)" $ do
        it "rejects language tags on string literals" $ do
            let ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:foo a cardano:Entity ;\n\
                    \  rdfs:label \"foo\"@en .\n"
            parseRulesTurtleText (TextEncoding.encodeUtf8 ttl)
                `shouldSatisfy` isParserError

        it "rejects datatype suffixes on string literals" $ do
            let ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                    \@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:foo a cardano:Entity ;\n\
                    \  rdfs:label \"42\"^^xsd:integer .\n"
            parseRulesTurtleText (TextEncoding.encodeUtf8 ttl)
                `shouldSatisfy` isParserError

        it "rejects collection syntax ( )" $ do
            let ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:foo a cardano:Entity ;\n\
                    \  cardano:hasIdentifier ( _:a _:b ) .\n"
            parseRulesTurtleText (TextEncoding.encodeUtf8 ttl)
                `shouldSatisfy` isParserError

        it "rejects blank-node property lists [ ]" $ do
            let ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:foo a cardano:Entity ;\n\
                    \  cardano:hasIdentifier [ a cardano:Identifier ] .\n"
            parseRulesTurtleText (TextEncoding.encodeUtf8 ttl)
                `shouldSatisfy` isParserError

    describe "round-trip with YAML (SC-005 co-equality)" $ do
        it
            ( "authoring the same content as YAML and as Turtle"
                <> " produces byte-equal overlay output"
            )
            $ do
                let yaml =
                        "entities:\n\
                        \  - name: foo\n\
                        \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
                    -- Same content authored in canonical Turtle. The
                    -- naming algorithm rebuilds the bnode label so any
                    -- operator-chosen bnode prefix would normalize away.
                    ttl =
                        "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                        \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                        \@prefix :        <https://example.com/x#> .\n\
                        \\n\
                        \:foo a cardano:Entity ;\n\
                        \  rdfs:label \"foo\" ;\n\
                        \  cardano:hasIdentifier _:foo_paymentScript .\n\
                        \\n\
                        \_:foo_paymentScript a cardano:Identifier ;\n\
                        \  cardano:leafType \"PaymentScript\" ;\n\
                        \  cardano:bytesHex \"fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\" .\n"
                (yamlBytes, ttlBytes) <- roundTripBytes yaml ttl
                ttlBytes `shouldBe` yamlBytes

        it "round-trips even when the operator-chosen bnode name differs from canonical" $ do
            -- Operator authored "_:my_custom_bnode" instead of the
            -- canonical "_:foo_paymentScript". The parser routes the
            -- entities through the same Naming algorithm the YAML
            -- compiler uses, so the serializer rewrites the bnode to
            -- the deterministic form and the byte output is identical.
            let yaml =
                    "entities:\n\
                    \  - name: foo\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
                ttl =
                    "@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .\n\
                    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:foo a cardano:Entity ;\n\
                    \  rdfs:label \"foo\" ;\n\
                    \  cardano:hasIdentifier _:my_custom_bnode .\n\
                    \\n\
                    \_:my_custom_bnode a cardano:Identifier ;\n\
                    \  cardano:leafType \"PaymentScript\" ;\n\
                    \  cardano:bytesHex \"fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\" .\n"
            (yamlBytes, ttlBytes) <- roundTripBytes yaml ttl
            ttlBytes `shouldBe` yamlBytes

isParserError :: Either RulesLoadError [EntityDecl] -> Bool
isParserError (Left ParserError{}) = True
isParserError _ = False

{- | The placeholder source-file path the in-memory parser entry
points stamp onto every produced 'EntityDecl'. Mirrors the
@inMemoryFile@ constant in
"Cardano.Tx.Graph.Rules.Load.Parse.Turtle"; the assertion sites
in this spec compare expected 'EntityDecl' values verbatim, so
the test reproduces the same string here rather than depending
on an internal export.
-}
inMemoryFile :: FilePath
inMemoryFile = "<in-memory>"

{- | Drive the YAML and Turtle blobs through 'loadRulesFile' in the same
temp directory so the fixture-slug derived from the directory
basename matches between the two — this isolates the byte-difference
test from the slug, leaving only the parser+serializer co-equality
under test. Returns @(yamlBytes, ttlBytes)@.
-}
roundTripBytes ::
    ByteString -> ByteString -> IO (ByteString, ByteString)
roundTripBytes yaml ttl =
    withSystemTempDirectory "tx-48-turtle-roundtrip" $ \dir -> do
        let yamlPath = dir </> "rules.yaml"
            ttlPath = dir </> "rules.ttl"
        BS.writeFile yamlPath yaml
        BS.writeFile ttlPath ttl
        yamlResult <- loadRulesFile yamlPath
        ttlResult <- loadRulesFile ttlPath
        case (yamlResult, ttlResult) of
            (Right RulesLoadResult{rulesOverlayTurtle = yBs}, Right RulesLoadResult{rulesOverlayTurtle = tBs}) ->
                pure (yBs, tBs)
            (Left e, _) ->
                fail $ "roundTripBytes: YAML loadRulesFile failed: " <> show e
            (_, Left e) ->
                fail $ "roundTripBytes: Turtle loadRulesFile failed: " <> show e

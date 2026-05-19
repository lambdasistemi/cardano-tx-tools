{- |
Module      : Cardano.Tx.Graph.Rules.LoadValidationSpec
Description : T009 unit tests for file+line provenance on validation errors.
License     : Apache-2.0

Covers the structured error surface of the rules loader: every variant
that the operator can hit at parse / validation time carries a
@(filePath, lineNumber)@ pair so the future @tx-graph@ CLI and a
language-server can render hyperlinked diagnostics.

Each test authors a small in-line @rules.yaml@ or @rules.ttl@ with a
known bug at a known line, drives the public 'loadRulesFile' surface
through 'withSystemTempFile', and asserts the returned 'RulesLoadError'
carries the temp-file's absolute path and the expected source line
number (1-based).

Tested error variants:

* 'ParserError' on malformed YAML (tab indent → libyaml decode failure).
* 'ParserError' on malformed Turtle (unterminated string).
* 'EntityZeroIdentifiers' on an entity with no identifier shape.
* 'BadBech32' on a malformed @from-address:@ string.
* 'BadPolicyHex' on a malformed @asset.policy:@ hex.
* 'BlueprintRefsUnknownScript' on a dangling blueprint reference.
* 'EntityNameSlugEmpty' on a name that slugifies to empty.
* 'EntityNameSlugLeadingDigit' on a name that slugifies leading-digit.
-}
module Cardano.Tx.Graph.Rules.LoadValidationSpec (spec) where

import Cardano.Tx.Graph.Rules.Load (
    RulesLoadError (..),
    loadRulesFile,
 )

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as TextEncoding
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Rules.Load (T009: file+line provenance)" $ do
    describe "ParserError carries (file, line)" $ do
        it "YAML decode failure points at the offending line" $ do
            -- Line 1: "entities:" (valid).
            -- Line 2: "  - name: foo" (valid).
            -- Line 3: a malformed flow mapping (unterminated brace).
            -- libyaml reports the line of the failure.
            let yaml =
                    "entities:\n\
                    \  - name: foo\n\
                    \    asset: { policy: aa, name: BAD\n"
            withYamlInTempFile yaml $ \path err -> case err of
                ParserError f line _ -> do
                    f `shouldBe` path
                    -- libyaml reports the line where the failure was
                    -- detected. The unterminated flow mapping is on
                    -- line 3 of the source; we accept either line 3
                    -- (the source line) or 4 (libyaml may report EOF
                    -- as the line after).
                    if line == 3 || line == 4
                        then pure ()
                        else
                            expectationFailure $
                                "expected line 3 or 4, got: " <> show line
                other ->
                    expectationFailure $
                        "expected ParserError, got: " <> show other

        it "Turtle unterminated string points at the offending line" $ do
            -- Line 5 contains an unterminated string literal: the
            -- rdfs:label opens a quote that never closes.
            let ttl =
                    "@prefix cardano: <https://example.com/c#> .\n\
                    \@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n\
                    \@prefix :        <https://example.com/x#> .\n\
                    \\n\
                    \:foo a cardano:Entity ; rdfs:label \"unterminated\n"
            withTurtleInTempFile ttl $ \path err -> case err of
                ParserError f line _ -> do
                    f `shouldBe` path
                    line `shouldBe` 5
                other ->
                    expectationFailure $
                        "expected ParserError, got: " <> show other

    describe "EntityZeroIdentifiers carries (file, line)" $ do
        it "points at the entity's '- name:' line" $ do
            -- Line 1: "entities:".
            -- Line 2: "  - name: alpha" — has script, fine.
            -- Line 3:   "    script: ...".
            -- Line 4: "  - name: orphan" — no identifier shape.
            let yaml =
                    "entities:\n\
                    \  - name: alpha\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n\
                    \  - name: orphan\n"
            withYamlInTempFile yaml $ \path err -> case err of
                EntityZeroIdentifiers f line slug -> do
                    f `shouldBe` path
                    line `shouldBe` 4
                    slug `shouldBe` "orphan"
                other ->
                    expectationFailure $
                        "expected EntityZeroIdentifiers, got: " <> show other

    describe "BadBech32 carries (file, line)" $ do
        it "from-address with malformed bech32 points at the entity line" $ do
            -- Line 2: "  - name: bad" — the entity owning the bad bech32.
            let yaml =
                    "entities:\n\
                    \  - name: bad\n\
                    \    from-address: addr1qx_THIS_IS_NOT_VALID_BECH32_x\n"
            withYamlInTempFile yaml $ \path err -> case err of
                BadBech32 f line s -> do
                    f `shouldBe` path
                    line `shouldBe` 2
                    s `shouldBe` "addr1qx_THIS_IS_NOT_VALID_BECH32_x"
                other ->
                    expectationFailure $
                        "expected BadBech32, got: " <> show other

    describe "BadPolicyHex carries (file, line)" $ do
        it "asset.policy with non-hex points at the entity line" $ do
            -- Line 2: "  - name: bad" — the entity owning the bad policy.
            let yaml =
                    "entities:\n\
                    \  - name: bad\n\
                    \    asset: { policy: ZZ, name: USDM }\n"
            withYamlInTempFile yaml $ \path err -> case err of
                BadPolicyHex f line s -> do
                    f `shouldBe` path
                    line `shouldBe` 2
                    s `shouldBe` "ZZ"
                other ->
                    expectationFailure $
                        "expected BadPolicyHex, got: " <> show other

        it "script: with non-hex points at the entity line" $ do
            -- Line 2: "  - name: bad-script" — owns the malformed hex.
            let yaml =
                    "entities:\n\
                    \  - name: bad-script\n\
                    \    script: NOTHEX\n"
            withYamlInTempFile yaml $ \path err -> case err of
                BadPolicyHex f line s -> do
                    f `shouldBe` path
                    line `shouldBe` 2
                    s `shouldBe` "NOTHEX"
                other ->
                    expectationFailure $
                        "expected BadPolicyHex (script reuse), got: " <> show other

    describe "BlueprintRefsUnknownScript carries (file, line)" $ do
        it "points at the blueprint entry's line" $ do
            -- Line 1: "entities:".
            -- Line 2: "  - name: foo.script".
            -- Line 3:   "    script: <56 hex>".
            -- Line 4: "blueprints:".
            -- Line 5:   "  - script: bar.absent".
            -- Line 6:     "    datum: ...".
            let yaml =
                    "entities:\n\
                    \  - name: foo.script\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n\
                    \blueprints:\n\
                    \  - script: bar.absent\n\
                    \    datum: ./blueprints/bar.cip57.json\n"
            withYamlInTempFile yaml $ \path err -> case err of
                BlueprintRefsUnknownScript f line refName -> do
                    f `shouldBe` path
                    line `shouldBe` 5
                    refName `shouldBe` "bar.absent"
                other ->
                    expectationFailure $
                        "expected BlueprintRefsUnknownScript, got: "
                            <> show other

    describe "EntityNameSlugEmpty carries (file, line)" $ do
        it "points at the offending entity's '- name:' line" $ do
            -- Line 2: "  - name: \"---\"" — slugifies to empty.
            let yaml =
                    "entities:\n\
                    \  - name: \"---\"\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            withYamlInTempFile yaml $ \path err -> case err of
                EntityNameSlugEmpty f line original -> do
                    f `shouldBe` path
                    line `shouldBe` 2
                    original `shouldBe` "---"
                other ->
                    expectationFailure $
                        "expected EntityNameSlugEmpty, got: " <> show other

    describe "EntityNameSlugLeadingDigit carries (file, line)" $ do
        it "points at the offending entity's '- name:' line" $ do
            -- Line 2: "  - name: 9lives" — slug starts with digit.
            let yaml =
                    "entities:\n\
                    \  - name: 9lives\n\
                    \    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077\n"
            withYamlInTempFile yaml $ \path err -> case err of
                EntityNameSlugLeadingDigit f line original -> do
                    f `shouldBe` path
                    line `shouldBe` 2
                    original `shouldBe` "9lives"
                other ->
                    expectationFailure $
                        "expected EntityNameSlugLeadingDigit, got: " <> show other

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

{- | Write @blob@ to a fresh @rules.yaml@ in a system temp directory,
drive 'loadRulesFile' against it, and feed the resulting
'RulesLoadError' (plus the file's absolute path) to the caller's
assertion. Fails the spec if the loader returns 'Right'.
-}
withYamlInTempFile ::
    ByteString -> (FilePath -> RulesLoadError -> IO ()) -> IO ()
withYamlInTempFile blob k =
    withSystemTempDirectory "tx-48-load-val-yaml" $ \dir -> do
        let path = dir </> "rules.yaml"
        BS.writeFile path blob
        result <- loadRulesFile path
        case result of
            Left err -> k path err
            Right _ ->
                expectationFailure
                    "expected Left RulesLoadError, got Right (load succeeded)"

{- | Sibling of 'withYamlInTempFile' for Turtle inputs. The temp file
extension drives the loader's parser dispatch.
-}
withTurtleInTempFile ::
    Text ->
    (FilePath -> RulesLoadError -> IO ()) ->
    IO ()
withTurtleInTempFile txt k =
    withSystemTempDirectory "tx-48-load-val-ttl" $ \dir -> do
        let path = dir </> "rules.ttl"
        BS.writeFile path (TextEncoding.encodeUtf8 txt)
        result <- loadRulesFile path
        case result of
            Left err -> k path err
            Right _ ->
                expectationFailure
                    "expected Left RulesLoadError, got Right (load succeeded)"

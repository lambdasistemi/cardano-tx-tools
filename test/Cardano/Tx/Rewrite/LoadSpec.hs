{- |
Module      : Cardano.Tx.Rewrite.LoadSpec
Description : Parser tests for the unified rewriting-rules YAML grammar.
License     : Apache-2.0

Drives 'Cardano.Tx.Rewrite.parseRewriteRulesYaml' through the
required compatibility surface for slice S1 of
@specs/032-tx-inspect@:

* legacy collapse-only documents parse to the same 'CollapseRules'
  that 'Cardano.Tx.Diff.parseCollapseRulesYaml' produces (SC-002,
  zero-regression guarantee),
* every 'RenameRule' variant — @kind: address@ with @match: full@,
  @kind: address@ with @match: payment@ and the implicit default,
  @kind: script@ — parses correctly, and the documented parse
  errors land as @Left@s,
* @rename:@ before @collapse:@ and the reverse key order parse to
  equal 'RewriteRules' values (SC-004, parse-level stage-order
  invariance),
* an empty @{}@ document parses to 'defaultRewriteRules'.
-}
module Cardano.Tx.Rewrite.LoadSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Either (isLeft)
import Test.Hspec

import Cardano.Tx.Diff (CollapseRule (..), CollapseRules (..), parseCollapseRulesYaml)
import Cardano.Tx.Rewrite (
    AddressMatch (..),
    AddressTarget (..),
    RenameRule (..),
    RenameRules (..),
    RewriteRules (..),
    defaultRewriteRules,
    parseRewriteRulesYaml,
 )

spec :: Spec
spec =
    describe "Cardano.Tx.Rewrite.parseRewriteRulesYaml" $ do
        legacyCompatSpec
        renameParsingSpec
        stageOrderSpec
        emptyDocumentSpec

legacyCompatSpec :: Spec
legacyCompatSpec =
    describe "legacy compatibility (SC-002)" $ do
        it "parses an existing collapse-only object identically to parseCollapseRulesYaml" $ do
            case (parseCollapseRulesYaml legacyDoc, parseRewriteRulesYaml legacyDoc) of
                (Right legacy, Right rewrite) ->
                    rewriteCollapse rewrite `shouldBe` legacy
                (legacyResult, rewriteResult) ->
                    expectationFailure $
                        "expected both to succeed; got legacy="
                            <> show legacyResult
                            <> " rewrite="
                            <> show rewriteResult

        it "keeps the collapse rule list contents and order" $ do
            case parseRewriteRulesYaml legacyDoc of
                Right rules ->
                    map collapseRuleName (collapseRules (rewriteCollapse rules))
                        `shouldBe` ["Swap output"]
                Left err ->
                    expectationFailure ("parse failed: " <> err)

        it "fills rename with the empty list when no rename: key is present" $ do
            case parseRewriteRulesYaml legacyDoc of
                Right rules ->
                    renameEntries (rewriteRename rules) `shouldBe` []
                Left err ->
                    expectationFailure ("parse failed: " <> err)

renameParsingSpec :: Spec
renameParsingSpec =
    describe "rename rule parsing" $ do
        it "parses kind: address with match: payment (default)" $ do
            case parseRewriteRulesYaml addressDefaultMatchDoc of
                Right rules ->
                    case renameEntries (rewriteRename rules) of
                        [RenameAddress _ MatchPayment (TargetPaymentCredential _) "alice"] ->
                            pure ()
                        other ->
                            expectationFailure ("unexpected: " <> show other)
                Left err ->
                    expectationFailure ("parse failed: " <> err)

        it "parses kind: address with match: full" $ do
            case parseRewriteRulesYaml addressFullMatchDoc of
                Right rules ->
                    case renameEntries (rewriteRename rules) of
                        [RenameAddress _ MatchFull (TargetFullAddress _) "alice-stake"] ->
                            pure ()
                        other ->
                            expectationFailure ("unexpected: " <> show other)
                Left err ->
                    expectationFailure ("parse failed: " <> err)

        it "parses kind: script" $ do
            case parseRewriteRulesYaml scriptDoc of
                Right rules ->
                    case renameEntries (rewriteRename rules) of
                        [RenameScript _ "validator.v1"] -> pure ()
                        other -> expectationFailure ("unexpected: " <> show other)
                Left err ->
                    expectationFailure ("parse failed: " <> err)

        it "rejects unknown kind" $
            parseRewriteRulesYaml unknownKindDoc `shouldSatisfy` isLeft

        it "rejects address rule with invalid bech32" $
            parseRewriteRulesYaml badAddressDoc `shouldSatisfy` isLeft

        it "rejects script rule whose key is not 56 hex chars" $
            parseRewriteRulesYaml badScriptDoc `shouldSatisfy` isLeft

        it "rejects a rule with empty name" $
            parseRewriteRulesYaml emptyNameDoc `shouldSatisfy` isLeft

        it "rejects unsupported version" $
            parseRewriteRulesYaml badVersionDoc `shouldSatisfy` isLeft

        it "rejects address rule with invalid match value" $
            parseRewriteRulesYaml badMatchDoc `shouldSatisfy` isLeft

stageOrderSpec :: Spec
stageOrderSpec =
    describe "stage-order invariance under YAML key order (SC-004, parse level)" $ do
        it "parses rename: before collapse: equal to collapse: before rename:" $ do
            case ( parseRewriteRulesYaml renameFirstDoc
                 , parseRewriteRulesYaml collapseFirstDoc
                 ) of
                (Right renameFirst, Right collapseFirst) ->
                    renameFirst `shouldBe` collapseFirst
                (a, b) ->
                    expectationFailure
                        ("parse failed; renameFirst=" <> show a <> " collapseFirst=" <> show b)

emptyDocumentSpec :: Spec
emptyDocumentSpec =
    describe "empty document" $ do
        it "{} parses to defaultRewriteRules" $ do
            parseRewriteRulesYaml "{}\n" `shouldBe` Right defaultRewriteRules

-- Fixtures ----------------------------------------------------------------

legacyDoc :: ByteString
legacyDoc =
    "version: 1\n\
    \collapse:\n\
    \  - name: \"Swap output\"\n\
    \    at: body.outputs\n\
    \    match:\n\
    \      required:\n\
    \        - datum.fields.0\n\
    \        - datum.fields.1\n"

-- Real mainnet base address (payment key + stake key) from the
-- @swap-cancel-issue-8@ fixture's @utxo.json@. Used as a parser
-- fixture only, not as an identity claim.
sampleBech32 :: String
sampleBech32 =
    "addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz"

addressDefaultMatchDoc :: ByteString
addressDefaultMatchDoc =
    "rename:\n\
    \  - kind: address\n\
    \    key: \""
        <> toBS sampleBech32
        <> "\"\n    name: alice\n"

addressFullMatchDoc :: ByteString
addressFullMatchDoc =
    "rename:\n\
    \  - kind: address\n\
    \    key: \""
        <> toBS sampleBech32
        <> "\"\n    match: full\n    name: alice-stake\n"

scriptDoc :: ByteString
scriptDoc =
    "rename:\n\
    \  - kind: script\n\
    \    key: 9c2e7e15a4c1b2d3e4f5061718192021222324252627282930313233\n\
    \    name: validator.v1\n"

unknownKindDoc :: ByteString
unknownKindDoc =
    "rename:\n\
    \  - kind: pool\n\
    \    key: foo\n\
    \    name: bar\n"

badAddressDoc :: ByteString
badAddressDoc =
    "rename:\n\
    \  - kind: address\n\
    \    key: not-bech32\n\
    \    name: alice\n"

badScriptDoc :: ByteString
badScriptDoc =
    "rename:\n\
    \  - kind: script\n\
    \    key: deadbeef\n\
    \    name: short\n"

emptyNameDoc :: ByteString
emptyNameDoc =
    "rename:\n\
    \  - kind: script\n\
    \    key: 9c2e7e15a4c1b2d3e4f5061718192021222324252627282930313233\n\
    \    name: \"\"\n"

badVersionDoc :: ByteString
badVersionDoc =
    "version: 2\n"

badMatchDoc :: ByteString
badMatchDoc =
    "rename:\n\
    \  - kind: address\n\
    \    key: \""
        <> toBS sampleBech32
        <> "\"\n    match: prefix\n    name: alice\n"

collapseFirstDoc :: ByteString
collapseFirstDoc =
    "version: 1\n\
    \collapse:\n\
    \  - name: \"Swap output\"\n\
    \    at: body.outputs\n\
    \    match:\n\
    \      required:\n\
    \        - datum.fields.0\n\
    \rename:\n\
    \  - kind: script\n\
    \    key: 9c2e7e15a4c1b2d3e4f5061718192021222324252627282930313233\n\
    \    name: validator.v1\n"

renameFirstDoc :: ByteString
renameFirstDoc =
    "version: 1\n\
    \rename:\n\
    \  - kind: script\n\
    \    key: 9c2e7e15a4c1b2d3e4f5061718192021222324252627282930313233\n\
    \    name: validator.v1\n\
    \collapse:\n\
    \  - name: \"Swap output\"\n\
    \    at: body.outputs\n\
    \    match:\n\
    \      required:\n\
    \        - datum.fields.0\n"

{- | Pack a literal ASCII 'String' (the bech32 fixture) into a
'ByteString' for splicing into the inline YAML payloads above.
-}
toBS :: String -> ByteString
toBS = BS8.pack

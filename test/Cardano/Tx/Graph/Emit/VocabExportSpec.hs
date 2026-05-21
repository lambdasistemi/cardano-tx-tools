{- |
Module      : Cardano.Tx.Graph.Emit.VocabExportSpec
Description : Derived canonical-vocab fragment is in sync (T122b / S23).
License     : Apache-2.0

Asserts that the Turtle fragment 'renderVocabFragment' derives
from 'Cardano.Tx.Graph.Emit.Vocab' matches the vendored copy at
@test/fixtures/canonical-vocab/derived.ttl@. Re-running with
@EMIT_GOLDEN_REGEN=1@ refreshes the file.

Operators inspecting drift between the local Vocab.hs surface
and the upstream kmaps canonical vocab can @diff
test/fixtures/canonical-vocab/{derived,transactions}.ttl@ — any
non-trivial diff is a candidate kmaps PR.
-}
module Cardano.Tx.Graph.Emit.VocabExportSpec (spec) where

import Data.ByteString qualified as BS
import Data.Text.Encoding qualified as TextEncoding
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)

import Cardano.Tx.Graph.Emit (renderVocabFragment)

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    pendingWith,
    runIO,
    shouldBe,
 )

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit derived canonical-vocab fragment (T122b)" $ do
    regen <- runIO regenEnabled
    let path = "test/fixtures/canonical-vocab/derived.ttl"
        expected = TextEncoding.encodeUtf8 renderVocabFragment
    it "test/fixtures/canonical-vocab/derived.ttl matches Vocab.hs" $ do
        if regen
            then do
                BS.writeFile path expected
                pendingWith "EMIT_GOLDEN_REGEN=1 — derived.ttl rewritten"
            else do
                exists <- doesFileExist path
                if not exists
                    then
                        expectationFailure $
                            "derived.ttl missing at "
                                <> path
                                <> "; run EMIT_GOLDEN_REGEN=1 just unit"
                    else do
                        actual <- BS.readFile path
                        actual `shouldBe` expected

regenEnabled :: IO Bool
regenEnabled = do
    mv <- lookupEnv "EMIT_GOLDEN_REGEN"
    pure (mv == Just "1")

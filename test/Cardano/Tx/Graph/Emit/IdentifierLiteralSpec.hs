{- |
Module      : Cardano.Tx.Graph.Emit.IdentifierLiteralSpec
Description : Raw-bytes identifier literal triples (T119b / S18b).
License     : Apache-2.0

Asserts the T119b / S18b invariant: every raw-bytes credential /
asset-class / pool-id / DRep-key bnode the body walker resolves
also carries the canonical identifier-literal triples

> _:bn a cardano:Identifier ;
>     cardano:leafType "<LeafType>" ;
>     cardano:bytesHex "<hex>" .

so SPARQL views can join @cardano:hasRequiredSigner "\<hex\>"@
literals (and similar raw-hex predicates) against the credential
bnode's @cardano:bytesHex@ via @FILTER (?signer = ?credHex)@ —
no IRI surgery required. Operator-driven gap: pre-T119b the
bnode was named after the hex prefix in its IRI but the hex
bytes themselves were not exposed as RDF data.

This spec exercises the path via the rewrite-redesign fixtures
which contain payment-key credentials (every fixture) — the
emitted bytes must contain at least one
@_:cred_paymentkey_\<hex\> a cardano:Identifier ;@ subject
block with the matching @cardano:bytesHex@ literal.
-}
module Cardano.Tx.Graph.Emit.IdentifierLiteralSpec (spec) where

import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02

import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit raw-bytes identifier literals (T119b)" $ do
        it "emits a cardano:Identifier block per raw-bytes credential" $ do
            let bytes = emitBytes S02.tx
            -- Fixture 02 references _:cred_paymentkey_0000000000000000
            -- across its address-decomposition section.
            bytes
                `shouldSatisfy` BS8.isInfixOf
                    "_:cred_paymentkey_0000000000000000 a cardano:Identifier"
        it "the identifier block carries cardano:leafType" $ do
            let bytes = emitBytes S02.tx
            bytes
                `shouldSatisfy` BS8.isInfixOf
                    "cardano:leafType \"PaymentKey\""
        it "the identifier block carries cardano:bytesHex with full 56-hex" $ do
            let bytes = emitBytes S02.tx
            bytes
                `shouldSatisfy` BS8.isInfixOf
                    ("cardano:bytesHex \"" <> BS8.replicate 56 '0' <> "\"")

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

emitBytes :: ConwayTx -> BS.ByteString
emitBytes tx =
    case emit tx emptyUtxo [] [] of
        Right g -> serialize Turtle "identifier-literal-spec" g
        Left e -> error ("IdentifierLiteralSpec.emit: " <> show e)

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

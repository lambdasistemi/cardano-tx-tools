{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Tx.Graph.Emit.BlueprintTypedFixtureSpec
Description : RED contract for fixture @12-blueprint-typed@ (T103 / S3).
License     : Apache-2.0

The first behaviour-changing on-disk fixture for feature 050
(blueprint-decode typed triples). T102 wired the blueprint index
through 'Cardano.Tx.Graph.Emit.emit'; T103 ships the first fixture
whose @rules.yaml@ registers an on-disk CIP-57 blueprint (the
@amaru.swap.v2@ SwapOrder blueprint at
@test/fixtures/rewrite-redesign/blueprints/swap-v2-datum.cip57.json@)
and whose @expected.ttl@ records the typed-emission byte shape.

This spec pins three invariants on the bytes 'emit' produces when
the SwapOrder blueprint is in the index:

* __fixture-12-emits-typed__ — the Turtle output contains the typed
  predicate @:SwapOrder_recipient@ at least once (FR-004 / D-001b).
  Pre-T103 this fails to compile because
  'Fixtures.RewriteRedesign.S12BlueprintTyped' does not yet exist;
  that compile failure is the load-bearing RED.

* __typed-no-rawbytes__ — the @a cardano:Datum@ stanza emitted for
  the SwapOrder output carries NO @cardano:hasRawBytes@ literal. The
  typed walker must suppress the opaque-shape fallback once the
  blueprint matches (FR-004 / D-001f). Fixture 01 (the structural
  mirror of the same transaction) emits @hasRawBytes "182a"@ on its
  Datum subject; fixture 12 must not.

* __bytes-match-output-address__ — the @cardano:bytesHex@ literal
  attached to the SwapOrder recipient bnode is byte-equal to the
  @cardano:bytesHex@ on the spending output's payment credential
  (cross-bnode join SC-002 in @specs/050-blueprint-decode/spec.md@).
  Asserted shape-agnostically: the known recipient pubKey hash for
  fixture 12 (the operator-paste CBOR decodes to
  @PubKeyCredential 0x64f35d…40ef@) is hardcoded as
  'swapOrderRecipientHex' and counted against the emitted Turtle —
  the count must be at least two (recipient bnode + spending output
  2's payment-credential bnode). This intentionally does NOT assume
  a particular bnode tree depth; the walker is free to grow deeper
  @anyOf@ / leaf-type structure without breaking this invariant.

The fixture itself (the @12-blueprint-typed@ directory + the
@S12BlueprintTyped@ builder + the @EmitGoldenSpec@ enumeration
extension) lands in the same T103 commit as the driver's GREEN
work; this spec is the navigator's RED contract pinning the
emission shape.
-}
module Cardano.Tx.Graph.Emit.BlueprintTypedFixtureSpec (spec) where

import Control.Monad (unless, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Cardano.Tx.Graph.Emit (
    EmitFormat (Turtle),
    EmittedGraph (..),
    emit,
    serialize,
 )
import Cardano.Tx.Graph.Rules.Load (
    RulesLoadResult (..),
    loadRulesFile,
    rulesEntities,
 )

import Fixtures.RewriteRedesign.S12BlueprintTyped qualified as S12

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
 )

-- ---------------------------------------------------------------------------
-- Top-level spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
    describe
        "Cardano.Tx.Graph.Emit fixture 12-blueprint-typed (T103 / S3)"
        $ do
            emitted <- runIO loadAndEmitFixture12

            it "emits :SwapOrder_recipient at least once (typed predicate present)" $
                case emitted of
                    Left err -> expectationFailure err
                    Right bytes ->
                        unless (BS8.pack ":SwapOrder_recipient" `BS.isInfixOf` bytes) $
                            expectationFailure $
                                "expected typed predicate :SwapOrder_recipient \
                                \in fixture 12 emitted Turtle, but did not find it.\n\n"
                                    <> BS8.unpack bytes

            it "Datum stanza carries no cardano:hasRawBytes (typed walker suppresses opaque shape)" $
                case emitted of
                    Left err -> expectationFailure err
                    Right bytes -> case datumStanza bytes of
                        Nothing ->
                            expectationFailure
                                "could not locate an `a cardano:Datum` stanza \
                                \in fixture 12 emitted Turtle"
                        Just stanza ->
                            when (BS8.pack "cardano:hasRawBytes" `BS.isInfixOf` stanza) $
                                expectationFailure $
                                    "Datum stanza carried cardano:hasRawBytes — \
                                    \typed path did not suppress opaque shape.\n\n"
                                        <> BS8.unpack stanza

            it "SwapOrder recipient bytesHex equals the spending output paymentCredential bytesHex (SC-002)" $
                case emitted of
                    Left err -> expectationFailure err
                    Right bytes ->
                        let n = occurrences recipientHexLiteral bytes
                         in unless (n >= 2) $
                                expectationFailure $
                                    "expected recipient bytesHex "
                                        <> BS8.unpack recipientHexLiteral
                                        <> " to occur at least twice (recipient + \
                                           \output payment-credential, SC-002 \
                                           \cross-bnode join); found "
                                        <> show n
                                        <> ".\n\n"
                                        <> BS8.unpack bytes

-- ---------------------------------------------------------------------------
-- Fixture 12 emission
-- ---------------------------------------------------------------------------

-- | Slug for fixture 12 under @test/fixtures/rewrite-redesign/@.
fixtureSlug :: String
fixtureSlug = "12-blueprint-typed"

-- | On-disk @rules.yaml@ for fixture 12.
fixtureRulesPath :: FilePath
fixtureRulesPath =
    "test/fixtures/rewrite-redesign" </> fixtureSlug </> "rules.yaml"

{- | Load fixture 12's rules + blueprint index and run 'emit' /
'serialize' to produce the joint Turtle byte stream. Each error
mode short-circuits into a 'Left' carrying a diagnostic string
the @it@ blocks render via 'expectationFailure'.
-}
loadAndEmitFixture12 :: IO (Either String ByteString)
loadAndEmitFixture12 = do
    res <- loadRulesFile fixtureRulesPath
    pure $ case res of
        Left err ->
            Left $
                "loadRulesFile "
                    <> fixtureRulesPath
                    <> " returned Left "
                    <> show err
        Right r@RulesLoadResult{rulesOverlayTurtle, rulesBlueprints} ->
            case emit S12.tx Map.empty (rulesEntities r) rulesBlueprints of
                Left err ->
                    Left $ "emit fixture 12 returned Left " <> show err
                Right g ->
                    let joint = g{graphOverlayTurtle = rulesOverlayTurtle}
                     in Right (serialize Turtle fixtureSlug joint)

-- ---------------------------------------------------------------------------
-- Turtle scanning helpers
-- ---------------------------------------------------------------------------

{- | Extract the first stanza in @hay@ that declares @a cardano:Datum@.
A stanza is the contiguous range of bytes from the subject's
opening line through the next line that ends with @ .@ (Turtle's
statement terminator). Returns 'Nothing' if no such stanza is
present.

Only used by the @typed-no-rawbytes@ invariant; the spec emits
exactly one @cardano:Datum@ subject for fixture 12 (one
script-credential output, one inline datum).
-}
datumStanza :: ByteString -> Maybe ByteString
datumStanza hay = go (BS.split 0x0A hay) []
  where
    -- Walk line-by-line; once we have entered a Datum stanza, accumulate
    -- lines until we see a statement-terminating @.@ at end of line.
    inside ls acc =
        case ls of
            [] -> Just (BS.intercalate (BS.singleton 0x0A) (reverse acc))
            l : rest ->
                let acc' = l : acc
                 in if isStatementEnd l
                        then
                            Just
                                ( BS.intercalate
                                    (BS.singleton 0x0A)
                                    (reverse acc')
                                )
                        else inside rest acc'
    go ls acc = case ls of
        [] -> Nothing
        l : rest ->
            if BS8.pack "a cardano:Datum" `BS.isInfixOf` l
                then inside rest (l : acc)
                else go rest acc
    isStatementEnd line =
        let trimmed = BS.dropWhile isSpace (BS.reverse line)
         in case BS.uncons trimmed of
                Just (c, _) -> c == 0x2E -- '.'
                Nothing -> False
    isSpace w = w == 0x20 || w == 0x09 || w == 0x0D

{- | The known recipient pubKey hash for fixture 12's SwapOrder
datum. The operator-paste CBOR decodes to
@SwapOrder { recipient = PubKeyCredential 0x64f35d…40ef }@; the
same 28-byte hash appears as the payment-credential bytes on the
spending output 2's address.

Hardcoded here so the @bytes-match-output-address@ invariant is
shape-agnostic: it counts the literal in the emitted Turtle byte
stream rather than walking the bnode tree. Future walker
refinements (deeper @anyOf@ nesting, leaf-type lookup, OpenArray
recursion) leave this assertion intact.
-}
swapOrderRecipientHex :: ByteString
swapOrderRecipientHex =
    BS8.pack "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef"

{- | The quoted Turtle literal form of 'swapOrderRecipientHex'
(@"…"@). Counted against the emitted Turtle by the third
invariant to assert the SC-002 cross-bnode coincidence — the
literal must appear at least twice: once on the SwapOrder
recipient bnode, once on the spending output 2's payment
credential bnode.
-}
recipientHexLiteral :: ByteString
recipientHexLiteral =
    BS.concat
        [ BS8.pack "\""
        , swapOrderRecipientHex
        , BS8.pack "\""
        ]

{- | Count non-overlapping occurrences of @needle@ in @hay@. Mirrors
the helper in 'Cardano.Tx.Graph.Emit.BlueprintWiringSpec' — kept
local to this module so the spec stays self-contained.
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

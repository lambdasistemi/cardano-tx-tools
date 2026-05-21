{- |
Module      : Cardano.Tx.Graph.Emit.BlockfrostSampleSmokeSpec
Description : Terminal acceptance gate — real-chain Conway txs (T127 / S25).
License     : Apache-2.0

The operator-mandated acceptance rule (A-005):

> Pick random Conway transactions from Blockfrost, run them
> through, and create graphs — it's going to work. That's it.

This spec walks every @*.cbor.hex@ file under
@test/fixtures/blockfrost-cache/@ and asserts the body emitter
handles it without crashing. The cache directory is the
deterministic side of the gate: CI without Blockfrost
credentials still runs against the vendored cache; operators
with @$BLOCKFROST_API_KEY_MAINNET@ extend the cache via a
separate fetch script (see @NOTES.md@ in the cache dir).

A failing cache entry blocks @gh pr ready@. The first
entry is @operator-paste-2026-05-21.cbor.hex@ — the tx that
crashed the pre-T116 emitter with
@UnsupportedLeafType: ConwayRequiredSignersValue@.

== Per-tx assertions

For each @<slug>.cbor.hex@ in the cache the spec emits two
@it@-blocks:

1. /Baseline/ — the bytes decode as a Conway tx via
   'decodeConwayTxInput', 'emit' returns @Right@ (no
   @PUnsupportedLeafType@ / @MalformedTxCbor@ / etc.), and the
   serialized Turtle output is non-empty and contains the
   @_:tx a cardano:Transaction@ anchor.
2. /Redeemer-block surfaces/ (T128e) — when the witness set
   carries a non-empty @Redeemers@ map, the emitted Turtle
   carries the canonical redeemer block: the top-level
   @cardano:hasRedeemer@ edge plus the six witness-set
   predicates @cardano:hasPurpose@, @cardano:hasIndex@,
   @cardano:hasData@, @cardano:hasExUnits@,
   @cardano:memoryUnits@, @cardano:cpuUnits@. For txs with no
   redeemers the check is marked @pending@.

The strict canonical-vocab traceability gate
('VocabTraceabilitySpec' T123a) runs over the rewrite-redesign
fixtures, not these — real-chain txs may exercise leaves not
yet declared upstream, in which case the strict gate would
need a temporary subset relaxation. Until that happens, this
spec is the "does it emit at all" gate plus the T128e redeemer
surface gate.

== Skip-when-empty

If the cache directory is empty (no @.cbor.hex@ files), every
case is marked @pending@ with a hint to populate the cache.
-}
module Cardano.Tx.Graph.Emit.BlockfrostSampleSmokeSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.List (sort)
import Data.Map.Strict qualified as Map
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, takeFileName, (</>))

import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Tx (witsTxL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Lens.Micro ((^.))

import Cardano.Tx.Diff (decodeConwayTxInput)
import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
    ResolvedUTxO,
    emit,
    renderEmitError,
    serialize,
 )
import Cardano.Tx.Ledger (ConwayTx)

import Test.Hspec (
    Expectation,
    Spec,
    describe,
    expectationFailure,
    it,
    pendingWith,
    runIO,
    shouldSatisfy,
 )

cacheDir :: FilePath
cacheDir = "test/fixtures/blockfrost-cache"

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit Blockfrost-sample smoke gate (T127 / S25)" $ do
        cacheFiles <- runIO listCachedTxs
        if null cacheFiles
            then
                it "no cached txs — gate is pending" $
                    pendingWith $
                        "Populate "
                            <> cacheDir
                            <> " with <slug>.cbor.hex files (see NOTES.md)"
            else mapM_ assertTxEmits cacheFiles

-- | List @.cbor.hex@ files in 'cacheDir', sorted by filename.
listCachedTxs :: IO [FilePath]
listCachedTxs = do
    exists <- doesDirectoryExist cacheDir
    if not exists
        then pure []
        else do
            entries <- listDirectory cacheDir
            let hexFiles =
                    [ cacheDir </> name
                    | name <- entries
                    , takeExtension name == ".hex"
                    , ".cbor.hex" `isSuffixOf'` name
                    ]
            pure (sort hexFiles)

assertTxEmits :: FilePath -> Spec
assertTxEmits path = do
    it (takeFileName path <> " — decodes and emits cleanly") $
        withEmittedTurtle path $ \_tx out ->
            out
                `shouldSatisfy` BS8.isInfixOf
                    "_:tx a cardano:Transaction"
    it (takeFileName path <> " — redeemer block surfaces if redeemers present") $
        withEmittedTurtle path $ \tx out ->
            let Redeemers rdmrMap = tx ^. witsTxL . rdmrsTxWitsL
             in if Map.null rdmrMap
                    then pendingWith "no redeemers in this tx"
                    else assertRedeemerBlockSurfaces path out

{- | Decode the cached tx, run 'emit' against an empty UTxO, and
hand the decoded tx plus serialized Turtle bytes to a continuation
that performs the per-block assertions. Used by both the baseline
and redeemer-surface checks.
-}
withEmittedTurtle ::
    FilePath -> (ConwayTx -> ByteString -> Expectation) -> Expectation
withEmittedTurtle path k = do
    bytes <- BS.readFile path
    case decodeConwayTxInput (stripWhitespace bytes) of
        Left err ->
            expectationFailure $
                "decodeConwayTxInput failed for " <> path <> ": " <> show err
        Right tx ->
            case emit tx emptyUtxo [] [] of
                Left err ->
                    expectationFailure $
                        "emit returned Left for "
                            <> path
                            <> ": "
                            <> renderEmitError err
                Right g ->
                    k tx (serialize Turtle (takeFileName path) g)

{- | T128e strengthened assertion: when the cached tx carries at
least one redeemer, the emitted Turtle must surface the complete
witness-set redeemer block. Checks the top-level edge
(@cardano:hasRedeemer@), the six witness-set predicates
(@hasPurpose@, @hasIndex@, @hasData@, @hasExUnits@, @memoryUnits@,
@cpuUnits@), and the operator-mandated spending redeemer value
(@cardano:hasPurpose \"Spend\"@ at @cardano:hasIndex 0@).

The quoted @"Spend"@ literal and the bare @0@ index are the exact
byte representation the serializer emits — spot-checked against
the operator-paste fixture before being pinned here.
-}
assertRedeemerBlockSurfaces :: FilePath -> ByteString -> Expectation
assertRedeemerBlockSurfaces path out =
    let needles =
            [ "cardano:hasRedeemer"
            , "cardano:hasPurpose"
            , "cardano:hasIndex"
            , "cardano:hasData"
            , "cardano:hasExUnits"
            , "cardano:memoryUnits"
            , "cardano:cpuUnits"
            , "cardano:hasPurpose \"Spend\""
            , "cardano:hasIndex 0"
            ]
        missing = [n | n <- needles, not (BS8.isInfixOf n out)]
     in case missing of
            [] -> pure ()
            xs ->
                expectationFailure $
                    "redeemer block missing predicates in "
                        <> path
                        <> ": "
                        <> show xs

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

{- | Strip ASCII whitespace (spaces, tabs, newlines) from a
bytestring — the hex files may end in a trailing newline.
-}
stripWhitespace :: ByteString -> ByteString
stripWhitespace = BS.filter (`notElem` [0x20, 0x09, 0x0A, 0x0D])

-- | Local 'List.isSuffixOf' for bare strings.
isSuffixOf' :: String -> String -> Bool
isSuffixOf' suffix s =
    let n = length suffix
        m = length s
     in m >= n && drop (m - n) s == suffix

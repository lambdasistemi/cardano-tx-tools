{- |
Module      : Cardano.Tx.Graph.Emit.VocabTraceabilitySpec
Description : Per-emit namespacing invariant (analyzer H1 / SC-005 / FR-009).
License     : Apache-2.0

Asserts the three vocab-traceability invariants on the joint
Turtle output of a fixture-02 emit:

1. The emitter declares only the three known prefixes — @cardano:@,
   @rdfs:@, fixture-local empty prefix — and no others.
2. No body line references a prefix outside that set (no
   @ex:foo@, no @owl:Class@, no stray @rdf:type@ — Turtle's @a@
   keyword covers the latter).
3. No @_internal:@ substring leaks into the bytes. This catches
   accidental leaks of internal vocabulary draft IRIs.

The traceability spec parses with a regex sweep — full Turtle
parsing is out of scope; the point is per-emit invariant catching.
-}
module Cardano.Tx.Graph.Emit.VocabTraceabilitySpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Char (isAlpha, isAlphaNum)
import Data.List (nub, sort)
import Data.Map.Strict qualified as Map
import System.FilePath ((</>))

import Cardano.Tx.Graph.Emit (
    EmitFormat (..),
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

import Fixtures.RewriteRedesign.S02_AliceBobAda qualified as S02

import Test.Hspec (
    Spec,
    describe,
    it,
    runIO,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec =
    describe "Cardano.Tx.Graph.Emit vocab traceability (T005 / H1 closer)" $ do
        let slug = "02-alice-bob-ada"
            dir = "test/fixtures/rewrite-redesign" </> slug
            rulesPath = dir </> "rules.yaml"
        entities <- runIO (loadEntities rulesPath)
        let bytes = case emit S02.tx emptyUtxo entities of
                Right g -> serialize Turtle slug g
                Left _ -> BS.empty
        runIO $
            case emit S02.tx emptyUtxo entities of
                Left err ->
                    fail $
                        "VocabTraceabilitySpec setup: emit returned Left "
                            <> show err
                Right _ -> pure ()
        it "fixture 02: declared prefixes ⊆ {cardano, rdfs, :}" $ do
            sort (extractDeclaredPrefixes bytes)
                `shouldBe` sort ["", "cardano", "rdfs"]
        it "fixture 02: every CURIE prefix in the body is one of the declared three" $ do
            let usedPrefixes = nub (extractUsedPrefixes bytes)
                ok p = p `elem` ["", "cardano", "rdfs"]
                bad = filter (not . ok) usedPrefixes
            bad `shouldBe` []
        it "fixture 02: no '_internal:' substring leak" $ do
            BS8.unpack bytes
                `shouldSatisfy` notContaining "_internal:"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

emptyUtxo :: ResolvedUTxO
emptyUtxo = Map.empty

loadEntities :: FilePath -> IO [EntityDecl]
loadEntities path = do
    result <- loadRulesFile path
    case result of
        Right res -> pure (rulesEntities res)
        Left err ->
            fail $
                "VocabTraceabilitySpec.loadEntities: "
                    <> path
                    <> ": "
                    <> show err

notContaining :: String -> String -> Bool
notContaining needle haystack = not (needle `isInfixOf'` haystack)

isInfixOf' :: String -> String -> Bool
isInfixOf' needle haystack =
    any
        (\i -> take (length needle) (drop i haystack) == needle)
        [0 .. length haystack - length needle]

{- | Extract the prefix name from every @\@prefix NAME: <IRI> .@
declaration. @NAME@ is empty for the default prefix.
-}
extractDeclaredPrefixes :: ByteString -> [String]
extractDeclaredPrefixes bs =
    [ trim (drop (length prefixKeyword) (takeBefore ':' line))
    | bsLine <- BS8.lines bs
    , let line = BS8.unpack bsLine
    , prefixKeyword `isPrefix` line
    ]
  where
    prefixKeyword :: String
    prefixKeyword = "@prefix"
    isPrefix p s = take (length p) s == p
    takeBefore c = takeWhile (/= c)
    trim = dropWhile (== ' ')

{- | Extract the prefix name of every CURIE @prefix:local@ occurrence in
the body (lines that are not @\@prefix …@ declarations). The empty
prefix appears as @:local@; we report that as @""@.
-}
extractUsedPrefixes :: ByteString -> [String]
extractUsedPrefixes bs =
    concat
        [ scanCuries line
        | bsLine <- BS8.lines bs
        , let line = BS8.unpack bsLine
        , not (prefixKeyword `isPrefix` line)
        , not (hashMark `isPrefix` line)
        ]
  where
    prefixKeyword, hashMark :: String
    prefixKeyword = "@prefix"
    hashMark = "#"
    isPrefix p s = take (length p) s == p

{- | Scan a single line for tokens of the form @[A-Za-z_][A-Za-z0-9_-]*:@
or @:@-prefixed local names. Returns the prefix part of each
occurrence (empty for default prefix). Skips Turtle blank-node
references (@_:foo@) and tokens inside string literals.
-}
scanCuries :: String -> [String]
scanCuries = go False
  where
    go _ [] = []
    -- toggle inString on unescaped quote
    go inString ('"' : rest) = go (not inString) rest
    go True (_ : rest) = go True rest
    -- blank-node reference: skip the "_:NAME"
    go False ('_' : ':' : rest) =
        go False (dropName rest)
    -- empty-prefix CURIE: ":local" not preceded by a name char
    go False (':' : rest)
        | startsLocal rest = "" : go False (dropName rest)
        | otherwise = go False rest
    -- named-prefix CURIE
    go False (c : rest)
        | isAlpha c || c == '_' =
            let (name, after) = spanIdent (c : rest)
             in case after of
                    (':' : after')
                        | startsLocal after' ->
                            name : go False (dropName after')
                    _ -> go False after
        | otherwise = go False rest

    spanIdent =
        span (\c -> isAlphaNum c || c == '_' || c == '-')

    startsLocal [] = False
    startsLocal (c : _) = isAlphaNum c || c == '_'

    dropName =
        dropWhile (\c -> isAlphaNum c || c == '_' || c == '-')

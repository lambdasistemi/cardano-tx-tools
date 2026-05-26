{- |
Module      : Cardano.Tx.Graph.Emit.LookupSpec
Description : Spec for the credential-lookup machinery (T004).
License     : Apache-2.0

Covers 'Cardano.Tx.Graph.Emit.Lookup' — the @(LeafType, ByteString)
→ 'BnodeName'@ resolution table the body emitter builds at the
start of every walk.

Four cases:

1. /Entity-named hit/ — 'buildLookup' over fixture-02-style entities
   ([alice, bob]) returns the operator-declared bnode for a known
   @(PaymentKey, alice's bytes)@ pair.
2. /Raw-bytes-named miss/ — an unknown 28-byte hash projects to
   @\\_:cred_paymentkey_\<first-16-hex-chars\>@ per spec FR-005 +
   plan D4 + research R3.
3. /Shared-identity first-wins/ — two entities sharing one
   @(PaymentScript, …)@ pair: the second entity's bnode is dropped;
   both 'resolveCredential' calls return the first entity's name.
4. /Injectivity property/ — across all 11 fixtures' @rules.yaml@,
   every distinct @(LeafType, ByteString)@ pair projects to a
   distinct raw-bytes 'BnodeName'. Validates the @N = 16@ prefix
   length pinned by research R3.
-}
module Cardano.Tx.Graph.Emit.LookupSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.FilePath ((</>))

import Cardano.Tx.Graph.Emit (
    BnodeName (..),
    buildLookup,
    entityBnodeName,
    rawBytesBnodeName,
    rawBytesPrefixLength,
    resolveCredential,
 )
import Cardano.Tx.Graph.Rules.Load (
    EntityDecl (..),
    EntityIdentifier (..),
    LeafType (..),
    RulesLoadResult (..),
    loadRulesFile,
    rulesEntities,
 )

import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    runIO,
    shouldBe,
 )

----------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------

spec :: Spec
spec = describe "Cardano.Tx.Graph.Emit.Lookup (T004)" $ do
    it "entity-named: resolveCredential returns the operator's bnode" $ do
        let table = buildLookup [aliceEnt, bobEnt]
        resolveCredential table PaymentKey aliceBytes
            `shouldBe` BnodeName "alice_paymentKey"

    it "raw-bytes-named: unknown bytes project to cred_<role>_<full-hex>" $ do
        let bytes = unsafeHex unknownHex
        rawBytesBnodeName PaymentKey bytes
            `shouldBe` BnodeName ("cred_paymentkey_" <> Text.pack unknownHex)

    it "shared-identity: first entity wins; both lookups agree" $ do
        let sharedHex =
                "fa6a58bb33333333333333333333333333333333333c8f3077"
                    <> "33"
            -- Two entities both naming the same PaymentScript bytes;
            -- the loader's first-entity-wins semantics is mirrored
            -- inside 'buildLookup'.
            firstE =
                mkScriptEntity "usdm_control" sharedHex
            secondE =
                mkScriptEntity "later_alias" sharedHex
            table = buildLookup [firstE, secondE]
            bytes = unsafeHex sharedHex
            first = resolveCredential table PaymentScript bytes
            secondViaLookup =
                resolveCredential table PaymentScript bytes
        first `shouldBe` BnodeName "usdm_control_paymentScript"
        secondViaLookup `shouldBe` first
        case entityIdentifiers secondE of
            (i : _) ->
                entityBnodeName secondE i
                    `shouldBe` BnodeName "later_alias_paymentScript"
            [] ->
                expectationFailure
                    "mkScriptEntity produced zero identifiers"

    fixtureDecls <- runIO loadAllFixtureEntities
    it
        ( "injectivity: raw-bytes bnodes across all 11 fixtures'"
            <> " rules.yaml are distinct"
        )
        $ do
            let pairs = collectPairs fixtureDecls
                projected =
                    [ (rawBytesBnodeName lt bs, (lt, bs))
                    | (lt, bs) <- Set.toList pairs
                    ]
                grouped =
                    Map.fromListWith
                        Set.union
                        [ (bn, Set.singleton p)
                        | (bn, p) <- projected
                        ]
            forM_ (Map.toList grouped) $ \(bn, ps) ->
                if Set.size ps == 1
                    then pure ()
                    else
                        expectationFailure $
                            "raw-bytes bnode collision at N = "
                                <> show rawBytesPrefixLength
                                <> ": "
                                <> show bn
                                <> " <- "
                                <> show (Set.toList ps)

----------------------------------------------------------------------
-- Fixture-02 stand-ins
----------------------------------------------------------------------

aliceEnt :: EntityDecl
aliceEnt =
    EntityDecl
        { entityName = "alice"
        , entitySlug = "alice"
        , entityIdentifiers =
            [ EntityIdentifier
                { entityIdLeafType = PaymentKey
                , entityIdBytesHex = aliceHex
                }
            , EntityIdentifier
                { entityIdLeafType = StakeKey
                , entityIdBytesHex =
                    "4c7889c658ef4f491a34cf79c35a2e0fe6b0d1b0a856fb9580f2d9c3"
                }
            ]
        , entityBech32 = Nothing
        , entitySourceFile = "<in-memory>"
        }

bobEnt :: EntityDecl
bobEnt =
    EntityDecl
        { entityName = "bob"
        , entitySlug = "bob"
        , entityIdentifiers =
            [ EntityIdentifier
                { entityIdLeafType = PaymentKey
                , entityIdBytesHex =
                    "2841f2c629212003be2c87fd02c0ff91fb81d8993129036d758ba548"
                }
            , EntityIdentifier
                { entityIdLeafType = StakeKey
                , entityIdBytesHex =
                    "e54e05afe3cb96ad42650e389b397b1722f0918ca977f239fd595a14"
                }
            ]
        , entityBech32 = Nothing
        , entitySourceFile = "<in-memory>"
        }

aliceHex :: Text.Text
aliceHex = "8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1"

aliceBytes :: ByteString
aliceBytes = unsafeHex (Text.unpack aliceHex)

{- | 28-byte hex string not referenced by any fixture entity. Picked
with a leading @ff…@ so it cannot collide with a fixture bytesHex
(no fixture uses @ff@ as the first byte).
-}
unknownHex :: String
unknownHex =
    "ffeeddccbbaa99887766554433221100ffeeddccbbaa9988"
        <> "77665544"

mkScriptEntity :: Text.Text -> String -> EntityDecl
mkScriptEntity slug hex =
    EntityDecl
        { entityName = slug
        , entitySlug = slug
        , entityIdentifiers =
            [ EntityIdentifier
                { entityIdLeafType = PaymentScript
                , entityIdBytesHex = Text.pack hex
                }
            ]
        , entityBech32 = Nothing
        , entitySourceFile = "<in-memory>"
        }

----------------------------------------------------------------------
-- Fixture loading (injectivity property)
----------------------------------------------------------------------

-- | The 11 fixture slugs covered by the rewrite-redesign suite.
fixtureSlugs :: [FilePath]
fixtureSlugs =
    [ "01-amaru-treasury-swap"
    , "02-alice-bob-ada"
    , "03-multi-asset-transfer"
    , "04-mint-spend-script-overlap"
    , "05-withdrawal-script-stake"
    , "06-stake-pool-delegation"
    , "07-vote-delegation"
    , "08-contingency-disburse"
    , "09-mpfs-facts-request"
    , "10-governance-treasury-withdrawal"
    , "11-amaru-treasury-swap-real"
    ]

loadAllFixtureEntities :: IO [EntityDecl]
loadAllFixtureEntities = do
    concat
        <$> mapM
            ( \slug -> do
                let path =
                        "test/fixtures/rewrite-redesign"
                            </> slug
                            </> "rules.yaml"
                result <- loadRulesFile path
                case result of
                    Right res ->
                        pure (rulesEntities res)
                    Left err ->
                        fail $
                            "LookupSpec.loadAllFixtureEntities: "
                                <> path
                                <> ": "
                                <> show err
            )
            fixtureSlugs

collectPairs :: [EntityDecl] -> Set (LeafType, ByteString)
collectPairs es =
    Set.fromList
        [ ( entityIdLeafType i
          , unsafeHex (Text.unpack (entityIdBytesHex i))
          )
        | e <- es
        , i <- entityIdentifiers e
        ]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- | Decode hex; @error@ on malformed input (fixture invariant).
unsafeHex :: String -> ByteString
unsafeHex s =
    case Base16.decode (TextEncoding.encodeUtf8 (Text.pack s)) of
        Right bs -> bs
        Left err ->
            error $ "LookupSpec.unsafeHex: " <> s <> ": " <> err

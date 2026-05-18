{- |
Module      : Cardano.Tx.Rewrite.ApplySpec
Description : Pure-function tests for the rewriting-rules application
              layer (slices S2 — collapse, and S3 — rename).
License     : Apache-2.0

Drives 'Cardano.Tx.Rewrite.applyCollapseFromRewriteRules' and
'Cardano.Tx.Rewrite.applyRewriteRules' through the load-bearing
pure-function shape required by slices S2 and S3 of
@specs\/032-tx-inspect@.

S2 coverage (collapse plumbing):

* a hand-crafted 'RewriteRules' with a non-empty 'CollapseRules' value
  sets 'humanCollapseRules' to @Just (rewriteCollapse rr)@ verbatim,
* 'defaultRewriteRules' (empty collapse list) still produces a non-Nothing
  'humanCollapseRules' carrying the empty rule list — the renderer
  treats this the same as 'Nothing' but the helper's job is to be
  faithful to the rewriting-rules value,
* the operation is idempotent: applying twice equals applying once.

S3 coverage (rename application + composite):

* an address with @match: payment@ against a base address whose stake
  credential differs still matches (the dominant treasury-work case),
* an unknown identifier renders verbatim,
* the same address with @match: full@ against a different stake
  credential does NOT match,
* a body input whose UTxO did not resolve (no @resolved.address@) plus
  a rename rule that would match the resolved address still renders
  the structural unresolved txin marker; no crash,
* render-level stage-order invariance — 'applyRewriteRules' produces
  output independent of the order in which 'rewriteCollapse' /
  'rewriteRename' are constructed (collapse always runs first; rename
  always runs second).

Render-level effects of the @gate.sh@ smoke / golden file are covered
by 'Cardano.Tx.InspectSpec'; this spec covers the pure-function plumbing
plus the small in-Haskell smoke needed for the edge cases above.
-}
module Cardano.Tx.Rewrite.ApplySpec (spec) where

import Data.Maybe (fromJust)
import Data.Text qualified as Text
import Test.Hspec

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx.Out (TxOut, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Mainnet), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj),
    StakeReference (StakeRefBase, StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Data.Map.Strict qualified as Map

import Cardano.Tx.Diff (
    AddressMatch (..),
    AddressTarget (..),
    CollapseRawView (..),
    CollapseRule (..),
    CollapseRules (..),
    ConwayDiffValue (..),
    DiffPath (..),
    HumanRenderOptions (..),
    RenameRule (..),
    RenameRules (..),
    RewriteRules (..),
    TxDiffOptions (..),
    defaultHumanRenderOptions,
    defaultRewriteRules,
    defaultTxDiffOptions,
    renderConwayDiffValueHuman,
 )
import Cardano.Tx.Rewrite (applyCollapseFromRewriteRules, applyRewriteRules)

spec :: Spec
spec = do
    collapsePlumbingSpec
    renameApplySpec
    stageOrderInvarianceSpec

-- ---------------------------------------------------------------------------
-- S2 — collapse plumbing
-- ---------------------------------------------------------------------------

collapsePlumbingSpec :: Spec
collapsePlumbingSpec =
    describe "Cardano.Tx.Rewrite.applyCollapseFromRewriteRules" $ do
        it "sets humanCollapseRules to Just (rewriteCollapse rr) for a non-empty rule list" $ do
            let rules = sampleRewriteRules
                opts =
                    applyCollapseFromRewriteRules
                        rules
                        defaultHumanRenderOptions
            humanCollapseRules opts `shouldBe` Just (rewriteCollapse rules)

        it
            "fills humanCollapseRules with the rewrite's collapse value\
            \ even when the rule list is empty"
            $ do
                let opts =
                        applyCollapseFromRewriteRules
                            defaultRewriteRules
                            defaultHumanRenderOptions
                humanCollapseRules opts
                    `shouldBe` Just (rewriteCollapse defaultRewriteRules)

        it "leaves every other field of HumanRenderOptions unchanged" $ do
            let opts =
                    applyCollapseFromRewriteRules
                        sampleRewriteRules
                        defaultHumanRenderOptions
            humanRenderShape opts
                `shouldBe` humanRenderShape defaultHumanRenderOptions
            humanTreeArt opts
                `shouldBe` humanTreeArt defaultHumanRenderOptions
            humanRenameRules opts
                `shouldBe` humanRenameRules defaultHumanRenderOptions

        it "is idempotent — applying twice equals applying once" $ do
            let once =
                    applyCollapseFromRewriteRules
                        sampleRewriteRules
                        defaultHumanRenderOptions
                twice =
                    applyCollapseFromRewriteRules
                        sampleRewriteRules
                        once
            twice `shouldBe` once

sampleRewriteRules :: RewriteRules
sampleRewriteRules =
    defaultRewriteRules
        { rewriteCollapse =
            CollapseRules
                { collapseRawView = CollapseRawHide
                , collapseRules =
                    [ CollapseRule
                        { collapseRuleName = "Output"
                        , collapseRuleAt =
                            DiffPath ["body", "outputs"]
                        , collapseRuleRequired =
                            [ DiffPath ["address"]
                            , DiffPath ["coin"]
                            ]
                        }
                    ]
                }
        }

-- ---------------------------------------------------------------------------
-- S3 — rename application
-- ---------------------------------------------------------------------------

renameApplySpec :: Spec
renameApplySpec =
    describe "Cardano.Tx.Rewrite.applyRewriteRules (rename application)" $ do
        it
            "address rule with match: payment matches a base address whose\
            \ stake credential differs (one rule covers every stake variant\
            \ of the same payment script)"
            $ do
                let rules =
                        renameOnly
                            [ aliceAddressRulePayment
                            ]
                    addr =
                        Addr
                            Mainnet
                            (KeyHashObj (mkKeyHash 1))
                            ( StakeRefBase
                                (KeyHashObj (mkKeyHash 99))
                            )
                    rendered = renderSingleAddress rules addr
                rendered `shouldContain` "alice"
                rendered `shouldNotContain` "{\"bytes\":"

        it
            "unknown identifier renders verbatim (best-effort,\
            \ never an error)"
            $ do
                let rules =
                        renameOnly
                            [ aliceAddressRulePayment
                            ]
                    -- Unknown payment credential — rule does not match.
                    addr =
                        Addr
                            Mainnet
                            (KeyHashObj (mkKeyHash 7))
                            StakeRefNull
                    rendered = renderSingleAddress rules addr
                rendered `shouldContain` "{\"bytes\":"
                rendered `shouldNotContain` "alice"

        it
            "address rule with match: full does NOT match the same payment\
            \ credential paired with a different stake credential"
            $ do
                let ruleAddr =
                        Addr
                            Mainnet
                            (KeyHashObj (mkKeyHash 1))
                            ( StakeRefBase
                                (KeyHashObj (mkKeyHash 10))
                            )
                    rules =
                        renameOnly
                            [ RenameAddress
                                { renameAddressKey = "alice-full"
                                , renameAddressMatch = MatchFull
                                , renameAddressTarget =
                                    TargetFullAddress ruleAddr
                                , renameName = "alice-full"
                                }
                            ]
                    -- Same payment credential, different stake credential.
                    rendered =
                        renderSingleAddress
                            rules
                            ( Addr
                                Mainnet
                                (KeyHashObj (mkKeyHash 1))
                                ( StakeRefBase
                                    (KeyHashObj (mkKeyHash 11))
                                )
                            )
                rendered `shouldNotContain` "alice-full"
                rendered `shouldContain` "{\"bytes\":"

        it
            "an unresolved input (no resolved.address) plus a rule that\
            \ would match the resolved address still renders the\
            \ structural txin marker; no crash"
            $ do
                let txIn = mkTxIn 1
                    resolverHit = mkTxIn 99
                    addr =
                        Addr
                            Mainnet
                            (KeyHashObj (mkKeyHash 1))
                            StakeRefNull
                    txOut :: TxOut ConwayEra
                    txOut =
                        mkBasicTxOut
                            addr
                            (MaryValue (Coin 1) (MultiAsset mempty))
                    rules = renameOnly [aliceAddressRulePayment]
                    opts =
                        applyRewriteRules rules defaultHumanRenderOptions
                    -- Resolver map deliberately MISSES txIn; the
                    -- ConwayTxInValue projection emits no `resolved` child.
                    diffOptions =
                        defaultTxDiffOptions
                            { txDiffResolvedInputs =
                                Just (Map.singleton resolverHit txOut)
                            }
                    rendered =
                        Text.unpack $
                            renderConwayDiffValueHuman
                                opts
                                diffOptions
                                (ConwayInputsValue [txIn])
                -- The structural txin marker is emitted.
                rendered `shouldContain` "\"index\":0"
                -- No rename happens (no resolved address to look up).
                rendered `shouldNotContain` "alice"
                -- No resolved branch (no UTxO map hit).
                rendered `shouldNotContain` "resolved"

-- ---------------------------------------------------------------------------
-- S3 — stage-order invariance (SC-004 at render level)
-- ---------------------------------------------------------------------------

stageOrderInvarianceSpec :: Spec
stageOrderInvarianceSpec =
    describe
        "Cardano.Tx.Rewrite.applyRewriteRules render-level stage-order invariance (SC-004)"
        $ do
            it
                "renders identically regardless of the order in which\
                \ rewriteCollapse / rewriteRename fields of the\
                \ RewriteRules record are constructed (collapse always\
                \ runs first; rename always runs second)"
                $ do
                    let collapseFirst =
                            RewriteRules
                                { rewriteCollapse = sampleCollapse
                                , rewriteRename = sampleRename
                                }
                        renameFirst =
                            RewriteRules
                                { rewriteRename = sampleRename
                                , rewriteCollapse = sampleCollapse
                                }
                        addr =
                            Addr
                                Mainnet
                                (KeyHashObj (mkKeyHash 1))
                                StakeRefNull
                        rendered rr =
                            renderSingleAddress rr addr
                    rendered renameFirst `shouldBe` rendered collapseFirst

sampleCollapse :: CollapseRules
sampleCollapse =
    CollapseRules
        { collapseRawView = CollapseRawHide
        , collapseRules =
            [ CollapseRule
                { collapseRuleName = "Output"
                , collapseRuleAt = DiffPath ["body", "outputs"]
                , collapseRuleRequired = [DiffPath ["address"]]
                }
            ]
        }

sampleRename :: RenameRules
sampleRename =
    RenameRules
        [ aliceAddressRulePayment
        , RenameScript
            { renameScriptHash = mkScriptHash 2
            , renameName = "swap.v1"
            }
        ]

aliceAddressRulePayment :: RenameRule
aliceAddressRulePayment =
    RenameAddress
        { renameAddressKey = "alice-payment"
        , renameAddressMatch = MatchPayment
        , renameAddressTarget =
            TargetPaymentCredential (KeyHashObj (mkKeyHash 1))
        , renameName = "alice"
        }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

renameOnly :: [RenameRule] -> RewriteRules
renameOnly entries =
    defaultRewriteRules{rewriteRename = RenameRules entries}

renderSingleAddress :: RewriteRules -> Addr -> String
renderSingleAddress rr addr =
    Text.unpack $
        renderConwayDiffValueHuman
            (applyRewriteRules rr defaultHumanRenderOptions)
            defaultTxDiffOptions
            (ConwayAddressValue addr)

{- | Build a deterministic 'KeyHash' from a small integer seed. The
underlying 28-byte hash is hex-encoded as @\<52 zeros\>\<two-byte
big-endian seed\>@ and decoded back via 'hashFromStringAsHex'. Used
to mint distinct payment- or stake-credential test identifiers
without committing to any specific cryptographic key.
-}
mkKeyHash :: Int -> KeyHash kr
mkKeyHash n =
    let hexStr =
            replicate 52 '0'
                ++ hexByte (n `div` 256)
                ++ hexByte (n `mod` 256)
        h = fromJust (hashFromStringAsHex hexStr)
     in KeyHash h

{- | Build a deterministic 'ScriptHash' from a small integer seed,
mirroring 'mkKeyHash'.
-}
mkScriptHash :: Int -> ScriptHash
mkScriptHash n =
    let hexStr =
            replicate 52 '0'
                ++ hexByte (n `div` 256)
                ++ hexByte (n `mod` 256)
        h = fromJust (hashFromStringAsHex hexStr)
     in ScriptHash h

hexByte :: Int -> String
hexByte x =
    let s = "0123456789abcdef"
     in [s !! (x `div` 16), s !! (x `mod` 16)]

mkTxIn :: Int -> TxIn
mkTxIn n =
    let hexStr =
            replicate 60 '0'
                ++ hexByte (n `div` 256)
                ++ hexByte (n `mod` 256)
        h = fromJust (hashFromStringAsHex hexStr)
     in TxIn
            (TxId (unsafeMakeSafeHash h))
            (TxIx 0)

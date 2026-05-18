{- |
Module      : Cardano.Tx.InspectSpec
Description : Golden test for the @tx-inspect@ render path.
License     : Apache-2.0

Drives 'Cardano.Tx.Diff.renderConwayTxHuman' against the existing
@swap-cancel-issue-8@ body fixture, with inputs resolved by the
test-only 'StaticResolver.staticResolver' over the same producer-tx
CBORs the Phase-1 validate suite already uses. The captured output is
checked against
@test\/fixtures\/mainnet-txbuild\/swap-cancel-issue-8\/inspect.verbatim.txt@.

This proves the S1 acceptance for slice S1 of
@specs\/032-tx-inspect@: the render path produces a stable structural
view of one Conway transaction without invoking the live resolver
chain.

The smoke at @scripts\/smoke\/tx-inspect@ exercises the unresolved
render path (no producer-tx fixtures); the two goldens together cover
both with-resolution and without-resolution shapes.
-}
module Cardano.Tx.InspectSpec (spec) where

import Data.Text.IO qualified as TextIO
import Lens.Micro ((^.))
import Test.Hspec

import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    referenceInputsTxBodyL,
 )

import Cardano.Tx.BuildSpec (loadBody)
import Cardano.Tx.Diff (
    TxDiffOptions (..),
    defaultHumanRenderOptions,
    defaultTxDiffOptions,
    renderConwayTxHuman,
 )
import Cardano.Tx.Diff.Resolver (Resolver (..))

import StaticResolver (staticResolver)

spec :: Spec
spec =
    describe "Cardano.Tx.Diff.renderConwayTxHuman (slice S1 baseline)" $ do
        it
            "renders the swap-cancel-issue-8 body with resolved inputs to the\
            \ checked-in golden"
            $ do
                tx <- loadBody (fixtureDir <> "/body.cbor.hex")
                let body = tx ^. bodyTxL
                    inputs =
                        (body ^. inputsTxBodyL)
                            <> (body ^. referenceInputsTxBodyL)
                            <> (body ^. collateralInputsTxBodyL)
                let resolver = staticResolver producerDir
                resolved <- resolveInputs resolver inputs
                let diffOptions =
                        defaultTxDiffOptions
                            { txDiffResolvedInputs = Just resolved
                            }
                    actual =
                        renderConwayTxHuman
                            defaultHumanRenderOptions
                            diffOptions
                            tx
                expected <- TextIO.readFile goldenPath
                actual `shouldBe` expected
  where
    fixtureDir =
        "test/fixtures/mainnet-txbuild/swap-cancel-issue-8"
    producerDir =
        fixtureDir <> "/producer-txs"
    goldenPath =
        fixtureDir <> "/inspect.verbatim.txt"

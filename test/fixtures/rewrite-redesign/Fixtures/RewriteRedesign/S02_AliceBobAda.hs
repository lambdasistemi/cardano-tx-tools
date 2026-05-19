{- |
Module      : Fixtures.RewriteRedesign.S02_AliceBobAda
Description : Conway tx builder for fixture 02-alice-bob-ada (044 Story 2).
License     : Apache-2.0

The simplest A-side fixture: Alice spends one UTxO and pays 10 ADA to Bob.
The tx body has 1 input, 2 outputs (Bob's payment + Alice's change),
zero certificates / withdrawals / proposals / collateral / reference
inputs / mint entries / script witnesses. Fee is left to the @draft@
interpreter (which produces a zero-fee body — the harness only asserts
structural shape; ledger-valid fee computation is out of scope).

Values follow the 044 spec verbatim (100 ADA UTxO → 10 ADA to Bob +
89.825 ADA change). Body addresses are structurally distinct stubs
since 'assertShape' only counts the body fields and does not inspect
address bytes; the entity-aware bech32 strings live in the companion
@rules.yaml@ where they drive the (future) rename pass.

The transaction body is composed via the @Cardano.Tx.Build@ DSL: each
@spend@ / @output@ call adds one instruction to the 'TxBuild' program
inside the 'TxBuilder' newtype, which 'mkTx' interprets to a 'ConwayTx'.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/, for the module contract.
-}
module Fixtures.RewriteRedesign.S02_AliceBobAda (
    storyId,
    tx,
    shape,
) where

import Fixtures.RewriteRedesign.Helpers (
    ExpectedShape (..),
    StoryId (..),
    TxBuilder (..),
    baseShape,
    mkTx,
    stubTxIn,
    stubTxOut,
 )

import Cardano.Tx.Build (output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "02-alice-bob-ada"

{- | Conway tx body: 1 input (Alice's 100 ADA UTxO), 2 outputs (Bob 10 ADA,
Alice change 89.825 ADA).
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- output (stubTxOut 10_000_000)
    _ <- output (stubTxOut 89_825_000)
    pure ()

-- | Expected structural shape per 044 Story 2.
shape :: ExpectedShape
shape = baseShape{esInputs = 1, esOutputs = 2}

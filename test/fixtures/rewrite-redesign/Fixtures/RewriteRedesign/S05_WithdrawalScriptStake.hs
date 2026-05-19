{- |
Module      : Fixtures.RewriteRedesign.S05_WithdrawalScriptStake
Description : Conway tx builder for fixture 05-withdrawal-script-stake (044 Story 5).
License     : Apache-2.0

Alice's wallet pays the fee; the body @withdrawals@ field claims 50 ADA in
rewards from a stake account whose stake credential is a script hash (the
@amaru-treasury@ stake script in @rules.yaml@). The 044 narrative drives
the rendering — script-stake credential resolves to the
@amaru-treasury.network_compliance@ entity in the expected output via the
future #47 emitter.

The harness contract this slice exercises is structural: 1 input, 1
output, 1 withdrawal map entry, all other body fields zero. @assertShape@
does not inspect the credential kind (key-hash vs. script-hash) — that
distinction is exercised by the rename + emit pipeline against
@rules.yaml@'s @entities:@ list, not here.

The transaction body is composed via the @Cardano.Tx.Build@ DSL.
'withdraw' adds one entry to the body @withdrawals@ map; the synthetic
reward account from 'stubRewardAccount' is structurally a key-hash
credential (the harness doesn't distinguish key vs script at the body
level; that's the future emitter's job).

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S05_WithdrawalScriptStake (
    storyId,
    tx,
    shape,
) where

import Cardano.Ledger.Coin (Coin (..))

import Fixtures.RewriteRedesign.Helpers (
    ExpectedShape (..),
    StoryId (..),
    TxBuilder (..),
    baseShape,
    mkTx,
    stubRewardAccount,
    stubTxIn,
    stubTxOut,
 )

import Cardano.Tx.Build (output, spend, withdraw)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "05-withdrawal-script-stake"

{- | Conway tx body: 1 input (Alice's 2 ADA fee-paying UTxO), 1 output
(Alice's 51.825 ADA change after the 50 ADA withdrawal), 1 withdrawal
entry claiming 50 ADA from a synthetic reward account.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- output (stubTxOut 51_825_000)
    withdraw (stubRewardAccount 1) (Coin 50_000_000)

-- | Expected structural shape per 044 Story 5.
shape :: ExpectedShape
shape = baseShape{esInputs = 1, esOutputs = 1, esWithdrawals = 1}

{- |
Module      : Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal
Description : Conway tx builder for fixture 10-governance-treasury-withdrawal
              (044 Story 10).
License     : Apache-2.0

An operator submits a Conway governance @ProposalProcedure@ of variety
@TreasuryWithdrawals@ requesting that the chain treasury pay 50_000 ADA to the
Cardano Foundation's operations stake address. The 044 narrative drives the
rendering — the proposal's @returnAddr@ resolves to the @operator@ entity and
the single withdrawal target to @cardano-foundation.ops@ via the future #47
emitter against @rules.yaml@.

The harness contract this slice exercises is structural: 1 input, 1 output, 1
proposal procedure, all other body fields zero. @assertShape@ does not
inspect the proposal internals (deposit, return-addr credential, withdrawal
map, anchor) — those rendering distinctions are exercised by the rename +
emit pipeline against @rules.yaml@, not here.

The transaction body is composed via the @Cardano.Tx.Build@ DSL. 'propose'
adds a 'ProposalProcedure' to the body; 'NoProposalScript' is the default
witnessing form since 'assertShape' does not inspect witness contents.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal (
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
    stubTreasuryWithdrawalProposal,
    stubTxIn,
    stubTxOut,
 )

import Cardano.Tx.Build (
    ProposalWitness (NoProposalScript),
    output,
    propose,
    spend,
 )
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "10-governance-treasury-withdrawal"

{- | Conway tx body: 1 input (operator's 100_001 ADA UTxO), 1 output
(operator's 0.825 ADA change after 100_000 ADA proposal deposit), 1
@TreasuryWithdrawals@ proposal procedure.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- output (stubTxOut 825_000)
    _ <- propose (stubTreasuryWithdrawalProposal 1) NoProposalScript
    pure ()

-- | Expected structural shape per 044 Story 10.
shape :: ExpectedShape
shape = baseShape{esInputs = 1, esOutputs = 1, esProposals = 1}

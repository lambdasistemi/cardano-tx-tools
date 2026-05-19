{- |
Module      : Fixtures.RewriteRedesign.S07_VoteDelegation
Description : Conway tx builder for fixture 07-vote-delegation (044 Story 7).
License     : Apache-2.0

Alice spends one UTxO, returns change to her own address, and emits a single
Conway @VoteDelegation@ certificate (a @DelegTxCert@ with a @DelegVote@
delegatee) referencing the Cardano Foundation DRep. The 044 narrative drives
the rendering — the DRep credential resolves to the @cardano-foundation-drep@
entity in the expected output via the future #47 emitter.

The harness contract this slice exercises is structural: 1 input, 1 output,
1 certificate, all other body fields zero. @assertShape@ does not inspect
the cert internals (stake credential, DRep credential, delegatee variant) —
that distinction is exercised by the rename + emit pipeline against
@rules.yaml@, not here. As a corollary the 044 @AlwaysAbstain@ sibling
variant is not encoded structurally in this slice: a second @DRepAlwaysAbstain@
tx would assert the same body-shape counts, so the harness contract is fully
covered by the single @cardano-foundation-drep@ case.

The transaction body is composed via the @Cardano.Tx.Build@ DSL. 'certify'
adds the vote-delegation cert; 'PubKeyCert' is the default witnessing form
since 'assertShape' does not inspect witness kind.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S07_VoteDelegation (
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
    stubVoteDelegationCert,
 )

import Cardano.Tx.Build (CertWitness (PubKeyCert), certify, output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "07-vote-delegation"

{- | Conway tx body: 1 input (Alice's 5 ADA UTxO), 1 output (Alice's
4.825 ADA change), 1 vote-delegation certificate.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- output (stubTxOut 4_825_000)
    _ <- certify (stubVoteDelegationCert 1) PubKeyCert
    pure ()

-- | Expected structural shape per 044 Story 7.
shape :: ExpectedShape
shape = baseShape{esInputs = 1, esOutputs = 1, esCertificates = 1}

{- |
Module      : Fixtures.RewriteRedesign.S06_StakePoolDelegation
Description : Conway tx builder for fixture 06-stake-pool-delegation (044 Story 6).
License     : Apache-2.0

Alice spends one UTxO, returns change to her own address, and emits a single
Conway @StakeDelegation@ certificate referencing a known pool. The 044
narrative drives the rendering — the pool key-hash resolves to the
@iog-pool-1@ entity in the expected output via the future #47 emitter.

The harness contract this slice exercises is structural: 1 input, 1 output,
1 certificate, all other body fields zero. @assertShape@ does not inspect
the cert internals (stake credential, pool key-hash) — that distinction is
exercised by the rename + emit pipeline against @rules.yaml@, not here.

The transaction body is composed via the @Cardano.Tx.Build@ DSL. 'certify'
adds one entry to the body @certificates@ sequence; 'PubKeyCert' is the
default witnessing form since 'assertShape' counts certs and does not
inspect witness kind.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S06_StakePoolDelegation (
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
    stubStakeDelegationCert,
    stubTxIn,
    stubTxOut,
 )

import Cardano.Tx.Build (CertWitness (PubKeyCert), certify, output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "06-stake-pool-delegation"

{- | Conway tx body: 1 input (Alice's 5 ADA UTxO), 1 output (Alice's
4.825 ADA change), 1 stake-delegation certificate.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- output (stubTxOut 4_825_000)
    _ <- certify (stubStakeDelegationCert 1) PubKeyCert
    pure ()

-- | Expected structural shape per 044 Story 6.
shape :: ExpectedShape
shape = baseShape{esInputs = 1, esOutputs = 1, esCertificates = 1}

{- |
Module      : Fixtures.RewriteRedesign.S08_ContingencyDisburse
Description : Conway tx builder for fixture 08-contingency-disburse (044 Story 8).
License     : Apache-2.0

The contingency self-script spends two of its own UTxOs to disburse 100 ADA
to a recipient and return change to itself; one collateral input is supplied
by a user wallet. The 044 narrative drives the rendering — both spent inputs
resolve to the same @amaru-treasury.contingency.account@ entity, and the
@rules.yaml@ collapse rule pins @resolved.address@ in @required:@. That
pinning is the #43 reproducer trigger: it forces the future #47 emitter to
elide the per-input address row in favour of the collapsed @Input × 2@
header.

The harness contract this slice exercises is structural: 2 inputs, 2
outputs, 1 collateral input, all other body fields zero. @assertShape@ does
not inspect the collateral 'TxIn' bytes — the user-wallet attribution lives
in @rules.yaml@ and is verified by the future #47 emitter against
@expected.txt@, not here.

The transaction body is composed via the @Cardano.Tx.Build@ DSL: 'spend'
adds the two contingency inputs, 'output' adds the two outputs, and
'collateral' adds the user-wallet collateral input.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S08_ContingencyDisburse (
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

import Cardano.Tx.Build (collateral, output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "08-contingency-disburse"

{- | Conway tx body: 2 inputs from the contingency self-script (60 + 50 ADA),
2 outputs (100 ADA disbursement to recipient, 9.825 ADA change back to the
contingency account), 1 user-wallet collateral input.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- spend (stubTxIn 2)
    _ <- output (stubTxOut 100_000_000)
    _ <- output (stubTxOut 9_825_000)
    collateral (stubTxIn 3)

-- | Expected structural shape per 044 Story 8.
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 2
        , esOutputs = 2
        , esCollateral = 1
        }

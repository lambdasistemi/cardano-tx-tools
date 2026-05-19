{- |
Module      : Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal
Description : Conway tx builder mirroring the real-tx Amaru swap shape.
License     : Apache-2.0

Mirrors mainnet tx
@5fc04113da630ec676a5a7a66d82f53c0e64527ee592c3e6c5e1dccad67732ea@. See
the cardano-tx-tools sibling
@test\/fixtures\/amaru-treasury-swap\/swap-1.source.md@ for the on-chain
provenance and
@\/code\/amaru-treasury-tx\/lib\/Amaru\/Treasury\/Tx\/Swap.hs@ for the
production DSL call shape (read-only — the harness does NOT depend on
@amaru-treasury-tx@).

Body shape: 2 inputs (1 user wallet + 1 treasury), 5 outputs (2 swap
orders at @amaru.swap.v2@ + 1 treasury leftover at
@amaru-treasury.network_compliance@ + 2 user payments back to the
@amaru.network-wallet@), 1 collateral input from the same user wallet.
The on-chain tx additionally carries a zero-amount @withdraw@ redeemer
and four reference inputs; the harness does NOT model these structurally
because 'assertShape' counts only the body-shape fields enumerated in
'ExpectedShape', and the rewrite-redesign rendering contract is
exercised by the future @#47@ emitter against @rules.yaml@'s
@entities:@ section, not by the @TxBuilder@ body.

The harness sister fixture @01-amaru-treasury-swap@ remains as the
hypothetical 33-input stress example from the 044 spec narrative; this
one tracks the actual on-chain shape so reviewers can compare both
against the same rules YAML structure.

The transaction body is composed via the @Cardano.Tx.Build@ DSL —
'spend' for the two body inputs, 'output' for each of the 5 outputs,
'collateral' for the user-wallet collateral. Coin values follow the
on-chain @expected.txt@ canonical render; 'assertShape' only counts
entries, so individual coin amounts are illustrative.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S11_AmaruTreasurySwapReal (
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
storyId = StoryId "11-amaru-treasury-swap-real"

{- | Conway tx body: 2 inputs (user fuel + treasury), 5 outputs (2 swap-order
chunks + 1 treasury leftover + 2 user payments), 1 collateral input.
Values from the on-chain @expected.txt@ render; illustrative only.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1) -- user-wallet input (96.8 ADA, also collateral source)
    _ <- spend (stubTxIn 2) -- treasury input (1_137_000 ADA)
    _ <- output (stubTxOut 39_306_821_250) -- swap-order chunk 1
    _ <- output (stubTxOut 39_306_821_249) -- swap-order chunk 2
    _ <- output (stubTxOut 1_058_730_000_000) -- treasury leftover
    _ <- output (stubTxOut 50_000_000) -- user payment 1
    _ <- output (stubTxOut 46_800_000) -- user payment 2 (residual change)
    collateral (stubTxIn 100)

-- | Expected structural shape per the real on-chain tx.
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 2
        , esOutputs = 5
        , esCollateral = 1
        }

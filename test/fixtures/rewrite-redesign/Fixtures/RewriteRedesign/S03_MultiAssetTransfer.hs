{- |
Module      : Fixtures.RewriteRedesign.S03_MultiAssetTransfer
Description : Conway tx builder for fixture 03-multi-asset-transfer (044 Story 3).
License     : Apache-2.0

Alice transfers a mixed bundle (ADA + USDM + MEME) to Bob, with change back
to herself. The 044 narrative carries the multi-asset values (200 ADA + 500
USDM + 5 000 000 MEME in; 50 ADA + 100 USDM + 1 000 000 MEME to Bob; 149.825
ADA + 400 USDM + 4 000 000 MEME change) and declares two asset entities
(USDM and MEME) alongside the address entities (alice and bob) in
@rules.yaml@.

The harness contract this slice exercises is purely structural: 1 input,
2 outputs, no certs / withdrawals / proposals / collateral / reference
inputs / mint entries / script witnesses. Asset entity rendering and the
@assets:@ multi-asset shape in @expected.txt@ are exercised by the future
#47 emitter against @rules.yaml@'s @entities:@ list, not by 'assertShape'
— which only counts body-field entries. Hence 'stubTxOut' (coin-only) is
sufficient here; values are illustrative per spec.md FR-002.

The transaction body is composed via the @Cardano.Tx.Build@ DSL: each
@spend@ / @output@ call adds one instruction to the 'TxBuild' program
inside the 'TxBuilder' newtype, which 'mkTx' interprets to a 'ConwayTx'.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/, for the module contract.
-}
module Fixtures.RewriteRedesign.S03_MultiAssetTransfer (
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
storyId = StoryId "03-multi-asset-transfer"

{- | Conway tx body: 1 input (Alice's 200 ADA + 500 USDM + 5M MEME UTxO),
2 outputs (50 ADA + 100 USDM + 1M MEME to Bob; 149.825 ADA + 400 USDM + 4M
MEME change). Multi-asset values are not encoded in the 'stubTxOut'
bodies — 'assertShape' only counts entries, and the future #47 emitter
rebuilds these tokens from @rules.yaml@'s asset entities.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- output (stubTxOut 50_000_000)
    _ <- output (stubTxOut 149_825_000)
    pure ()

-- | Expected structural shape per 044 Story 3.
shape :: ExpectedShape
shape = baseShape{esInputs = 1, esOutputs = 2}

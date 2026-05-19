{- |
Module      : Fixtures.RewriteRedesign.S01_AmaruTreasurySwap
Description : Conway tx builder for fixture 01-amaru-treasury-swap (044 Story 1).
License     : Apache-2.0

The load-bearing P1 fixture of the harness — exercises every distinguishing
feature of the rewrite-redesign pipeline at once. Thirty-three
@SwapOrder@ UTxOs at the @amaru.swap.v2@ script address are spent by the
swap script; each input's datum carries a @recipient@ field whose value is
the @amaru-treasury.network_compliance@ script hash. The settlement
produces one USDM-bearing output back to the treasury (per the recipient
field) plus a small ADA change output to the @amaru.network-wallet@
account; collateral for the script witness is taken from the same network
wallet. The 044 narrative drives the rendering — the 33 swap inputs
collapse into a single @SwapOrderInput@ bucket pinned on
@resolved.address@ and @datum.SwapOrder.recipient@, and the future #47
emitter decodes the datum via @swap-v2-datum.cip57.json@ into a typed AST
exposing the @recipient@ field by name. This fixture is the cross-leaf
identity reproducer for #43: the same @recipient@ script hash appears at
@body.outputs[0].address@ (as the treasury output) and at every
@body.inputs[*].datum.SwapOrder.recipient@ (as the bucket key), and the
emitter must resolve both to the same @amaru-treasury.network_compliance@
entity label.

The harness contract this slice exercises is purely structural: 34 inputs
(33 swap + 1 network-wallet), 2 outputs (USDM-bearing treasury output + ADA
change), 1 collateral input, all other body fields zero. @assertShape@
does not inspect input datums, output values, the @recipient@ field, or
the @amaru.swap.v2@ witness — those rich rendering distinctions (entity
cross-leaf identity, blueprint decode, nested @SwapOrderInput@ collapse,
USDM asset entity) are exercised by @rules.yaml@ against the future #47
emitter, not here. Per the deferred script-witness policy from S2,
@esScriptWits@ remains empty.

The transaction body is composed via the @Cardano.Tx.Build@ DSL.
'mapM_ spend' chains the 34 'spend' calls (33 swap-order UTxOs +
1 network-wallet input); 'output' adds the two outputs; 'collateral'
adds the user-wallet collateral.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S01_AmaruTreasurySwap (
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
storyId = StoryId "01-amaru-treasury-swap"

{- | Conway tx body: 34 inputs (33 @SwapOrder@ UTxOs at the @amaru.swap.v2@
script + 1 @amaru.network-wallet@ UTxO sourcing fee/collateral funds), 2
outputs (1.5 ADA + 95 USDM to @amaru-treasury.network_compliance@, 0.85
ADA change to @amaru.network-wallet@), 1 collateral input from the
network wallet. Coin values match the @expected.txt@ canonical render;
@assertShape@ only counts, so the USDM amount and the per-input
swap-order coin amounts are not modelled here.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    mapM_ (spend . stubTxIn) ([1 .. 34] :: [Int])
    _ <- output (stubTxOut 1_500_000)
    _ <- output (stubTxOut 850_000)
    collateral (stubTxIn 100)

-- | Expected structural shape per 044 Story 1.
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 34
        , esOutputs = 2
        , esCollateral = 1
        }

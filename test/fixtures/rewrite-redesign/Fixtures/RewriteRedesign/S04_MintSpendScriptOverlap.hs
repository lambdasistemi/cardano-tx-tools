{- |
Module      : Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap
Description : Conway tx builder for fixture 04-mint-spend-script-overlap (044 Story 4).
License     : Apache-2.0

A treasury tx mints 1000 USDM under the @usdm-control@ policy and spends a
UTxO locked by the same script hash used as a spending validator. The same
28-byte hash appears as 'Policy' role in the mint field and as
'PaymentScript' role in the input's address — the cross-leaf identity
surface 044 Story 4 declares via @keys: [PaymentScript, Policy]@ in
'rules.yaml'.

The harness contract this slice exercises is structural: 1 input,
1 output, 1 mint entry, all other body fields zero. The future #47
emitter consumes 'rules.yaml' to render the entity name on both the
@inputs@ and @mint@ lines; the dual-role identity is enforced there,
not by 'assertShape'.

The transaction body is composed via the @Cardano.Tx.Build@ DSL. 'mint'
takes a 'PolicyID', an asset map (one @(AssetName, qty)@ here), and a
typed redeemer; the harness uses @()@ as a trivial redeemer since
'assertShape' counts mint entries and does not inspect witness
contents. Script-witness enforcement is deferred — 'assertShape'
currently does not inspect 'esScriptWits', and this slice intentionally
does not register a Plutus script witness.

See @specs/033-rewrite-redesign-harness/data-model.md@, section
/Per-fixture Tx module shape/.
-}
module Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap (
    storyId,
    tx,
    shape,
) where

import Data.ByteString.Short qualified as SBS
import Data.Maybe (fromJust)

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    PolicyID (..),
 )

import Fixtures.RewriteRedesign.Helpers (
    ExpectedShape (..),
    StoryId (..),
    TxBuilder (..),
    baseShape,
    mkTx,
    stubMintEntry,
    stubTxIn,
    stubTxOutMA,
 )

import Cardano.Tx.Build (mint, output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "04-mint-spend-script-overlap"

{- | Conway tx body: 1 input under the @usdm-control@ script (5 ADA),
1 output to alice (4.5 ADA carrying 1000 USDM), 1 mint entry
(@usdm-control@ × USDM, +1000).

T104 / S3 binds the minted 1000 USDM onto the output via
'stubTxOutMA'; mint + send-to-output is the typical Cardano shape and
gives the output-side multi-asset emission path real coverage on the
overlap fixture in addition to S03's pure transfer.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <- output (stubTxOutMA 4_500_000 [(usdmControlPolicy, usdmName, 1000)])
    let (policyID, assetMap) = stubMintEntry 1 1000
    mint policyID assetMap ()

----------------------------------------------------------------------
-- Asset constants — match @rules.yaml@ entity declarations
----------------------------------------------------------------------

usdmControlPolicy :: PolicyID
usdmControlPolicy =
    PolicyID
        ( ScriptHash
            ( fromJust
                ( hashFromStringAsHex
                    "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad"
                )
            )
        )

usdmName :: AssetName
usdmName = AssetName (SBS.toShort "USDM")

-- | Expected structural shape per 044 Story 4.
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 1
        , esOutputs = 1
        , esMintEntries = 1
        }

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
    stubTxIn,
    stubTxOutMA,
 )

import Cardano.Tx.Build (output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "03-multi-asset-transfer"

{- | Conway tx body: 1 input (Alice's 200 ADA + 500 USDM + 5M MEME UTxO),
2 outputs:

* output 1 — 50 ADA + 100 USDM + 1_000_000 MEME → Bob.
* output 2 — 149.825 ADA + 400 USDM + 4_000_000 MEME (change) → Alice.

Both outputs carry the multi-asset value matching the 044 narrative.
T104 / S3 introduced 'stubTxOutMA' so this fixture finally exercises
the output-side multi-asset RDF-list emission path; pre-T104 the
outputs were coin-only and the @-multi-asset-@ slug was nominal only.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1)
    _ <-
        output
            ( stubTxOutMA
                50_000_000
                [ (usdmPolicy, usdmName, 100)
                , (memePolicy, memeName, 1_000_000)
                ]
            )
    _ <-
        output
            ( stubTxOutMA
                149_825_000
                [ (usdmPolicy, usdmName, 400)
                , (memePolicy, memeName, 4_000_000)
                ]
            )
    pure ()

-- | Expected structural shape per 044 Story 3.
shape :: ExpectedShape
shape = baseShape{esInputs = 1, esOutputs = 2}

----------------------------------------------------------------------
-- Asset constants — match @rules.yaml@ entity declarations
----------------------------------------------------------------------

usdmPolicy :: PolicyID
usdmPolicy =
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

memePolicy :: PolicyID
memePolicy =
    PolicyID
        ( ScriptHash
            ( fromJust
                ( hashFromStringAsHex
                    "aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc"
                )
            )
        )

memeName :: AssetName
memeName = AssetName (SBS.toShort "MEME")

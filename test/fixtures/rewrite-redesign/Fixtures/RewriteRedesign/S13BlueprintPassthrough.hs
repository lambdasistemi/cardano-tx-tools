{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Fixtures.RewriteRedesign.S13BlueprintPassthrough
Description : Fixture 13 — no-blueprint datum stays opaque (T104 / S4).
License     : Apache-2.0

Second behaviour-changing on-disk fixture for feature 050
(blueprint-decode typed triples), and the negative twin of fixture
12: the transaction body is identical (same SwapOrder inline datum
on output 1, same recipient pubkey-credential output 2), but the
fixture's @rules.yaml@ does __not__ register any blueprint. The
walker therefore hits the 'NoBlueprintRegistered' branch in
'Cardano.Tx.Graph.Emit.Blueprint' and emits the pre-#50 opaque
@cardano:hasRawBytes@ literal on the Datum subject — byte-equal to
what the pre-T103 emitter would have produced on the same datum
body.

This is the operational proof of SC-003 (no typed predicates leak
into the no-blueprint path) and FR-018 (back-compat byte-stability
on fixtures that declare no @blueprints:@). The cross-fixture
traceability spec
('Cardano.Tx.Graph.Emit.BlueprintPredicateTraceabilitySpec') asserts
the @:\<ctor\>_\<field\>@ predicate set is empty here.

The transaction body — 1 fuel input, output 1 at the @amaru.swap.v2@
script-credential address with the SwapOrder inline datum, output 2
at the recipient's pubkey-credential address — mirrors fixture 12
verbatim. Keeping the datum bytes byte-equal between the two
fixtures isolates the variable under test (blueprint registered vs
not) and lets a reviewer cross-read the two @expected.ttl@ files to
see exactly which triples the blueprint registration mints.
-}
module Fixtures.RewriteRedesign.S13BlueprintPassthrough (
    storyId,
    tx,
    shape,
    swapScriptHash,
    recipientPubKeyHash,
) where

import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.Function ((&))
import Data.Maybe (fromJust)
import Lens.Micro ((.~))

import Cardano.Crypto.Hash (hashFromStringAsHex)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Datum)
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    datumTxOutL,
    mkBasicTxOut,
 )
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (
    Credential (KeyHashObj, ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (Payment))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.Data (mkInlineDatum)
import PlutusCore.Data qualified as PLC

import Fixtures.RewriteRedesign.Helpers (
    ExpectedShape (..),
    StoryId (..),
    TxBuilder (..),
    baseShape,
    mkTx,
    stubTxIn,
 )

import Cardano.Tx.Build (output, spend)
import Cardano.Tx.Ledger (ConwayTx)

-- | Story slug — kebab directory name under @test/fixtures/rewrite-redesign/@.
storyId :: StoryId
storyId = StoryId "13-blueprint-passthrough"

{- | The @amaru.swap.v2@ payment-credential script hash. Same on-chain
mainnet hash as fixture @11-amaru-treasury-swap-real@ +
@12-blueprint-typed@; the fixture declares an entity for this hash
in @rules.yaml@ so the body emitter mints the overlay's
@:amaru_swap_v2@ subject, but does __not__ register a blueprint —
the negative case the slice is asserting on.
-}
swapScriptHash :: ScriptHash
swapScriptHash =
    ScriptHash
        ( fromJust
            ( hashFromStringAsHex
                "fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077"
            )
        )

{- | The SwapOrder recipient's pubKeyHash, byte-equal to fixture 12's
'Fixtures.RewriteRedesign.S12BlueprintTyped.recipientPubKeyHash'
(the operator-paste CBOR's inline-datum payload). Re-declared here
so this fixture's builder stands alone; the shared bytes are what
makes the negative-vs-positive byte-diff between fixtures 12 and 13
inspectable line-by-line.
-}
recipientPubKeyHash :: ByteString
recipientPubKeyHash =
    case Base16.decode "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef" of
        Right bs -> bs
        Left err ->
            error
                ( "S13BlueprintPassthrough.recipientPubKeyHash: hex decode failed: "
                    <> err
                )

{- | Conway tx body for fixture 13: 1 input, 2 outputs. Identical to
fixture 12's body — same SwapOrder inline datum on output 1, same
recipient pubkey-credential output 2. The behaviour change comes
from the fixture's @rules.yaml@ omitting the @blueprints:@ block,
not from the tx body.
-}
tx :: ConwayTx
tx = mkTx . TxBuilder $ do
    _ <- spend (stubTxIn 1) -- user-wallet fuel input
    _ <- output (swapOrderOutput 5_000_000)
    _ <- output (recipientOutput 2_000_000)
    pure ()

{- | Expected structural shape for fixture 13. Same 1-input /
2-output counts as fixture 12; 'esBlueprintRef' is 'Nothing' because
@rules.yaml@ registers no blueprint.
-}
shape :: ExpectedShape
shape =
    baseShape
        { esInputs = 1
        , esOutputs = 2
        }

----------------------------------------------------------------------
-- Outputs
----------------------------------------------------------------------

{- | The SwapOrder output: at the @amaru.swap.v2@ script-credential
address with the inline SwapOrder datum
(@Constr 0 [Constr 0 [B <recipient>]]@). Byte-equal to fixture 12's
'swapOrderOutput' — the negative-case fixture deliberately keeps
the datum body identical so the only emitted-Turtle difference
between fixtures 12 and 13 is whether the walker decoded the datum
or fell through to @cardano:hasRawBytes@.
-}
swapOrderOutput :: Integer -> TxOut ConwayEra
swapOrderOutput coin =
    mkBasicTxOut swapOrderAddr (MaryValue (Coin coin) (MultiAsset mempty))
        & datumTxOutL .~ swapOrderDatum

{- | The recipient output: at a pubkey-credential address whose
payment key-hash equals the SwapOrder recipient's pubKeyHash. Same
as fixture 12 — present here so the body shape between the two
fixtures is identical and the byte-diff isolates the datum-emission
branch.
-}
recipientOutput :: Integer -> TxOut ConwayEra
recipientOutput coin =
    mkBasicTxOut recipientAddr (MaryValue (Coin coin) (MultiAsset mempty))

swapOrderAddr :: Addr
swapOrderAddr = Addr Testnet (ScriptHashObj swapScriptHash) StakeRefNull

recipientAddr :: Addr
recipientAddr =
    Addr
        Testnet
        ( KeyHashObj
            ( KeyHash
                ( fromJust
                    ( hashFromStringAsHex
                        "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef"
                    )
                ) ::
                KeyHash Payment
            )
        )
        StakeRefNull

{- | The inline SwapOrder datum on output 1: byte-equal to fixture
12's 'swapOrderDatum'. Encoded as
@Constr 0 [Constr 0 [B 0x64f35d…]]@.
-}
swapOrderDatum :: Datum ConwayEra
swapOrderDatum =
    mkInlineDatum
        ( PLC.Constr
            0
            [PLC.Constr 0 [PLC.B recipientPubKeyHash]]
        )

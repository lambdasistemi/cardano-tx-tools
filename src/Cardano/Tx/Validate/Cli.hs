{- |
Module      : Cardano.Tx.Validate.Cli
Description : CLI surface for the tx-validate executable.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

CLI surface for the @tx-validate@ executable that wraps
'Cardano.Tx.Validate.validatePhase1'. This module is
deliberately Node-to-Client-free: the N2C glue lives in
@app/tx-validate/Main.hs@ + the existing @n2c-resolver@
sublibrary (constitution I — one-way dependency on
@cardano-node-clients@).

The 'Session' value collects the protocol parameters, the tip
slot, and the resolver chain the executable's @Main@ entry
acquires from an N2C bracket. Pure consumers (and unit tests)
build a 'Session' directly via 'mkSession' without opening any
socket.

The Blockfrost-side surface originally part of this module's
design is deferred to upstream issue
<https://github.com/lambdasistemi/cardano-tx-tools/issues/21>.
-}
module Cardano.Tx.Validate.Cli (
    -- * Option ADT
    TxValidateCliOptions (..),
    InputSource (..),
    OutputFormat (..),
    N2cConfig (..),

    -- * Session
    Session (..),
    mkSession,
) where

import Data.Word (Word32)

import Cardano.Ledger.Api (PParams)
import Cardano.Ledger.BaseTypes (Network, SlotNo)
import Cardano.Ledger.Conway (ConwayEra)

import Cardano.Tx.Diff.Resolver (Resolver)

-- * Option ADT

-- | The fully-parsed option record produced by the CLI parser.
data TxValidateCliOptions = TxValidateCliOptions
    { txValidateCliInput :: InputSource
    , txValidateCliN2c :: N2cConfig
    , txValidateCliOutput :: OutputFormat
    }
    deriving stock (Eq, Show)

-- | Where to read the candidate Conway transaction CBOR hex from.
data InputSource
    = InputFile FilePath
    | InputStdin
    deriving stock (Eq, Show)

-- | Verdict rendering target.
data OutputFormat
    = Human
    | Json
    deriving stock (Eq, Show)

-- | Node-to-Client (N2C) session configuration.
data N2cConfig = N2cConfig
    { n2cSocket :: FilePath
    , n2cMagic :: Word32
    }
    deriving stock (Eq, Show)

-- * Session

{- | Resolved session state for one tx-validate invocation. The
@Main@ entry's N2C bracket acquires the 'PParams' + tip slot
from a live @cardano-node@ and pairs them with the
'n2cResolver'-wrapped UTxO chain to build this record. Pure
consumers (and unit tests) construct a 'Session' directly via
'mkSession'.

The resolver chain has exactly one entry in v1 (the N2C
resolver); the JSON output schema preserves the @"n2c"@ /
@"blockfrost"@ vocabulary so a future second resolver lands
additively
(<https://github.com/lambdasistemi/cardano-tx-tools/issues/21>).
-}
data Session = Session
    { sessionNetwork :: Network
    , sessionPParams :: PParams ConwayEra
    , sessionSlot :: SlotNo
    , sessionUtxoResolvers :: [Resolver]
    }

{- | Build a 'Session' from already-acquired primary-session
data and the resolver chain. Pure.
-}
mkSession ::
    Network ->
    PParams ConwayEra ->
    SlotNo ->
    [Resolver] ->
    Session
mkSession network pp slot resolvers =
    Session
        { sessionNetwork = network
        , sessionPParams = pp
        , sessionSlot = slot
        , sessionUtxoResolvers = resolvers
        }

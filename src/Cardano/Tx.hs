{- |
Module      : Cardano.Tx
Description : Top-level umbrella for Cardano transaction tooling.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Placeholder module. The actual builder, diff core, blueprint decoder,
and resolvers are migrating from
[lambdasistemi/cardano-node-clients](https://github.com/lambdasistemi/cardano-node-clients)
under the tracking issue
<https://github.com/lambdasistemi/cardano-node-clients/issues/152>.
-}
module Cardano.Tx (
    txToolsVersion,
) where

-- | Build identifier for the cardano-tx-tools library.
txToolsVersion :: String
txToolsVersion = "0.0.0"

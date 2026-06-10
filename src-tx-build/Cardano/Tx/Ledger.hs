{-# LANGUAGE DataKinds #-}

{- |
Module      : Cardano.Tx.Ledger
Description : Conway-era transaction type alias.
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The transaction shape every module in this repository works with.
'ConwayTx' is a Haskell type synonym, so it is interchangeable with any
identical synonym defined elsewhere: the type checker sees through both
to @'Tx' 'TopTx' 'ConwayEra'@. Defining it here keeps the @tx-build@
sub-library independent from node-client packages.
-}
module Cardano.Tx.Ledger (
    ConwayTx,
) where

import Cardano.Ledger.Alonzo.Core (TopTx, Tx)
import Cardano.Ledger.Conway (ConwayEra)

-- | Conway-era top-level transaction.
type ConwayTx = Tx TopTx ConwayEra

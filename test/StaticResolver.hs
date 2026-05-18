{- |
Module      : StaticResolver
Description : Test-only static-fixture resolver for the @tx-inspect@
              golden suite.
License     : Apache-2.0

A 'Cardano.Tx.Diff.Resolver.Resolver' implementation that reads
canonical producer-tx CBOR fixtures from disk via
'Cardano.Tx.Validate.LoadUtxo.loadUtxo' and answers
'Cardano.Tx.Diff.Resolver.resolveInputs' with the requested subset of
the pre-loaded map.

This helper is __test-only__. It is NOT part of the production
resolver chain (constitution principle VI — default-offline). Golden
tests use it to resolve fixture inputs without speaking N2C or HTTPS.
-}
module StaticResolver (
    staticResolver,
) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set

import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.TxIn (TxIn)

import Cardano.Tx.Diff.Resolver (Resolver (..))
import Cardano.Tx.Validate.LoadUtxo (loadUtxo)

{- | Build a 'Resolver' over a directory of producer-tx CBOR fixtures.

The directory layout is the one
'Cardano.Tx.Validate.LoadUtxo.loadUtxo' consumes: one
@\<txIdHex\>.cbor.hex@ file per producer transaction. The resolver
loads the producer transactions on every 'resolveInputs' call and
returns the requested subset; the cost is acceptable for test fixtures
(a handful of producer transactions per invocation).
-}
staticResolver :: FilePath -> Resolver
staticResolver producerDir =
    Resolver
        { resolverName = "static"
        , resolveInputs = resolveAgainstFixtures producerDir
        }

resolveAgainstFixtures ::
    FilePath -> Set TxIn -> IO (Map TxIn (TxOut ConwayEra))
resolveAgainstFixtures producerDir asked = do
    resolved <- loadUtxo producerDir (Set.toList asked)
    pure (Map.fromList resolved)

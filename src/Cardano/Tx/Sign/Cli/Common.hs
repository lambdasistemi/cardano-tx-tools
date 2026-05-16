{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Tx.Sign.Cli.Common
Description : Shared CLI runtime helpers for tx-sign
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Globally required options shared by every tx-sign subcommand.
-}
module Cardano.Tx.Sign.Cli.Common (
    GlobalOpts (..),
    globalOptsP,
    resolveNetworkName,
) where

import Data.Text (Text)
import Options.Applicative (
    Parser,
    eitherReader,
    help,
    long,
    metavar,
    option,
 )

-- | Globally required options shared by every subcommand.
newtype GlobalOpts = GlobalOpts
    { goNetworkName :: Text
    }
    deriving stock (Eq, Show)

-- | Parser for 'GlobalOpts'.
globalOptsP :: Parser GlobalOpts
globalOptsP =
    GlobalOpts
        <$> option
            (eitherReader parseNetworkName)
            ( long "network"
                <> metavar "NAME"
                <> help "mainnet | preprod | preview | devnet"
            )

parseNetworkName :: String -> Either String Text
parseNetworkName raw = case raw of
    "mainnet" -> Right "mainnet"
    "preprod" -> Right "preprod"
    "preview" -> Right "preview"
    "devnet" -> Right "devnet"
    other ->
        Left
            ( "unknown network name: "
                <> other
                <> " (expected mainnet|preprod|preview|devnet)"
            )

{- | Resolve the canonical network name. Returned in @Either@ form for
source compatibility with upstream wallet-tooling APIs that surface
custom network magics; always 'Right' here.
-}
resolveNetworkName :: GlobalOpts -> Either String Text
resolveNetworkName = Right . goNetworkName

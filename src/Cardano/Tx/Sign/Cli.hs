{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Tx.Sign.Cli
Description : Top-level CLI parser for the tx-sign executable
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Composes the @vault@ and @witness@ subcommands. The single
@--network@ option is required and decides which network the vault
identity is bound to.
-}
module Cardano.Tx.Sign.Cli (
    TxSignCommand (..),
    runTxSign,
    txSignParser,

    -- * Re-exports
    GlobalOpts (..),
    globalOptsP,
    resolveNetworkName,
) where

import Options.Applicative (
    Parser,
    ParserInfo,
    command,
    execParser,
    fullDesc,
    helper,
    hsubparser,
    info,
    progDesc,
    (<**>),
 )

import Cardano.Tx.Sign.Cli.Common (
    GlobalOpts (..),
    globalOptsP,
    resolveNetworkName,
 )
import Cardano.Tx.Sign.Cli.Vault (
    VaultCommand (..),
    runVaultCommand,
    vaultCommandP,
 )
import Cardano.Tx.Sign.Cli.Witness (
    WitnessOpts,
    runWitness,
    witnessOptsP,
 )

-- | Top-level tx-sign command.
data TxSignCommand
    = TxSignVault VaultCommand
    | TxSignWitness WitnessOpts
    deriving stock (Eq, Show)

-- | Parser for the full tx-sign CLI.
txSignParser :: ParserInfo (GlobalOpts, TxSignCommand)
txSignParser =
    info
        ( ((,) <$> globalOptsP <*> commandP)
            <**> helper
        )
        ( fullDesc
            <> progDesc
                "Create or use an encrypted Cardano signing-key vault, and emit detached vkey witnesses for unsigned Conway transactions."
        )

commandP :: Parser TxSignCommand
commandP =
    hsubparser
        ( command
            "vault"
            ( info
                (TxSignVault <$> vaultCommandP)
                (progDesc "Manage an encrypted Cardano signing-key vault")
            )
            <> command
                "witness"
                ( info
                    (TxSignWitness <$> witnessOptsP)
                    ( progDesc
                        "Create a detached vkey witness for an unsigned Conway transaction"
                    )
                )
        )

-- | Run the tx-sign CLI parser and dispatch the chosen subcommand.
runTxSign :: IO ()
runTxSign = do
    (g, cmd) <- execParser txSignParser
    case cmd of
        TxSignVault vault -> runVaultCommand g vault
        TxSignWitness opts -> runWitness g opts

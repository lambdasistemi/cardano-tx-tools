{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.Tx.Sign.Cli
Description : Top-level CLI parser for the tx-sign executable
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Composes the @vault@ and @witness@ subcommands. The single
@--network@ option is required and decides which network the vault
identity is bound to.

The 'runTxSign' entry point takes a 'CliBanner' so the parser can
plumb @github-release-check:optparse@'s 'versionOption' via
@\<**\>@ — that renders @--version@ as
@\"\<cliExe\> \<showVersion cliVersion\>\"@. The banner is
typically the same value the executable's @Main@ passes to
'GitHub.Release.Check.withCli'.
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

import GitHub.Release.Check (CliBanner)
import GitHub.Release.Check.OptParse (versionOption)

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

{- | Parser for the full tx-sign CLI. The caller supplies a
'CliBanner' so @--version@ is rendered by the sublibrary's
'versionOption' helper (kept consistent with the other
@tx-*@ executables in this repo).
-}
txSignParser :: CliBanner -> ParserInfo (GlobalOpts, TxSignCommand)
txSignParser banner =
    info
        ( ((,) <$> globalOptsP <*> commandP)
            <**> helper
            <**> versionOption banner
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

{- | Run the tx-sign CLI parser and dispatch the chosen
subcommand. The 'CliBanner' is threaded into the parser so the
@--version@ flag prints @\"tx-sign \<semver\>\"@ via
@github-release-check:optparse@'s 'versionOption'.
-}
runTxSign :: CliBanner -> IO ()
runTxSign banner = do
    (g, cmd) <- execParser (txSignParser banner)
    case cmd of
        TxSignVault vault -> runVaultCommand g vault
        TxSignWitness opts -> runWitness g opts

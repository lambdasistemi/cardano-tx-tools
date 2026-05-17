{- |
Module      : Main
Description : tx-sign executable entry point
License     : Apache-2.0

Thin wrapper over 'Cardano.Tx.Sign.Cli.runTxSign'. @main@ is
wrapped in 'GitHub.Release.Check.withCli' so every run prints
the latest-release banner to stderr on exit (suppressed by the
@TX_SIGN_NO_UPDATE_CHECK@ env var); @--version@ short-circuits
via @github-release-check:optparse@'s 'versionOption', plumbed
through 'Cardano.Tx.Sign.Cli.runTxSign'.
-}
module Main (main) where

import GitHub.Release.Check (
    CliBanner (..),
    RepoSlug (..),
    withCli,
 )
import Paths_cardano_tx_tools (version)

import Cardano.Tx.Sign.Cli (runTxSign)

main :: IO ()
main = withCli banner id (runTxSign banner)

{- | Update-check banner bundle handed to
'GitHub.Release.Check.withCli' and to
'Cardano.Tx.Sign.Cli.runTxSign'. The opt-out env var is
@TX_SIGN_NO_UPDATE_CHECK@; set it to any value to silence the
banner.
-}
banner :: CliBanner
banner =
    CliBanner
        { cliRepo = RepoSlug "lambdasistemi" "cardano-tx-tools"
        , cliExe = "tx-sign"
        , cliVersion = version
        , cliOptOutEnvVar = "TX_SIGN_NO_UPDATE_CHECK"
        }

{- |
Module      : Main
Description : tx-validate executable entry point (placeholder)
License     : Apache-2.0

Placeholder entry. The argument parser and the validation driver
land in slice T002 of spec 015. This revision prints usage and
exits with the configuration-error code.
-}
module Main (main) where

import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
    hPutStrLn stderr usage
    exitWith (ExitFailure 2)

usage :: String
usage =
    unlines
        [ "Usage: tx-validate"
        , "    --input PATH | -"
        , "    --n2c-socket PATH"
        , "    [--network-magic WORD32]"
        , "    [--output human|json]"
        , ""
        , "tx-validate: placeholder build; full CLI lands in"
        , "https://github.com/lambdasistemi/cardano-tx-tools/issues/19"
        ]

{- |
Module      : Cardano.Tx.Rewrite
Description : Consumer-facing API for the two-stage @tx-inspect@
              rewriting rules (collapse + rename).
License     : Apache-2.0

This module is the public API for the rewriting-rules /language/. The
underlying Haskell types — 'RewriteRules', 'RenameRules', 'RenameRule',
'AddressMatch', 'AddressTarget' — and the 'FromJSON' instances live in
'Cardano.Tx.Diff' so the diff core's 'Cardano.Tx.Diff.HumanRenderOptions'
record can store a 'RenameRules' field without an import cycle. This
module is the canonical address for downstream consumers (the predicate
DSL in lambdasistemi\/cardano-tx-tools#15, the @tx-inspect@ executable,
golden tests); none of them have to know the types are physically
defined in 'Cardano.Tx.Diff'.

There are two stages, fixed in order regardless of YAML key order:

1. __Collapse__ — recognise a repeated structural skeleton and replace
   it with a named shape exposing only per-instance variable slots.
   Reuses 'Cardano.Tx.Diff.CollapseRule'(s) unchanged.

2. __Rename__ — substitute leaf identifiers (payment addresses, script
   hashes) with names from an address book.

Slice S1 of @specs\/032-tx-inspect@ ships only the types and the
'parseRewriteRulesYaml' loader. The application paths
(@applyRewriteRules@ / @applyRename@ / @applyCollapseFromRewriteRules@)
land in S2 (collapse) and S3 (rename); deliberately omitted from this
slice to keep the diff additive.

The grammar parsed by 'parseRewriteRulesYaml' is documented in
@specs\/032-tx-inspect\/contracts\/rules-yaml-grammar.md@.
-}
module Cardano.Tx.Rewrite (
    -- * Top-level rewriting wrapper
    RewriteRules (..),
    defaultRewriteRules,

    -- * Stage 2 — rename rules
    RenameRule (..),
    RenameRules (..),
    AddressMatch (..),
    AddressTarget (..),
    emptyRenameRules,

    -- * Parser
    parseRewriteRulesYaml,
) where

import Cardano.Tx.Diff (
    AddressMatch (..),
    AddressTarget (..),
    RenameRule (..),
    RenameRules (..),
    RewriteRules (..),
    defaultRewriteRules,
    emptyRenameRules,
    parseRewriteRulesYaml,
 )

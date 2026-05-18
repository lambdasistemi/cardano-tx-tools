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

Slice S1 of @specs\/032-tx-inspect@ shipped the types and the
'parseRewriteRulesYaml' loader. Slice S2 adds the collapse plumbing —
'applyCollapseFromRewriteRules' — which moves the stage-1 rules from a
'RewriteRules' record into 'Cardano.Tx.Diff.HumanRenderOptions' so the
shared render core ('Cardano.Tx.Diff.renderConwayTxHuman') can consult
them on its trie walk. The stage-2 rename application
(@applyRename@ \/ @applyRewriteRules@) lands in S3; deliberately omitted
from this slice to keep the diff additive.

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

    -- * Stage 1 — collapse plumbing
    applyCollapseFromRewriteRules,
) where

import Cardano.Tx.Diff (
    AddressMatch (..),
    AddressTarget (..),
    HumanRenderOptions (..),
    RenameRule (..),
    RenameRules (..),
    RewriteRules (..),
    defaultRewriteRules,
    emptyRenameRules,
    parseRewriteRulesYaml,
 )

{- | Stage-1 plumbing: lift the 'rewriteCollapse' field of a 'RewriteRules'
value into 'HumanRenderOptions' so the shared render core
('Cardano.Tx.Diff.renderConwayTxHuman') consults the same
'humanCollapseRules' channel the diff renderer already consults.

The application semantics are uniform across @tx-inspect@ and @tx-diff@:
the renderer walks its projection, looks up matching 'CollapseRule's at
each array site, and emits the named-shape view plus the
'collapseRawView'-gated raw subtree. Empty rule lists are a no-op (the
renderer's @collapseRulesAt@ never finds a match), so feeding
'defaultRewriteRules' through this helper is safe and idempotent.

This helper is the only stage-1 application surface 'Cardano.Tx.Rewrite'
exposes today. Slice S3 of @specs\/032-tx-inspect@ adds the stage-2
counterpart @applyRename@ and the composite @applyRewriteRules@.
-}
applyCollapseFromRewriteRules ::
    RewriteRules -> HumanRenderOptions -> HumanRenderOptions
applyCollapseFromRewriteRules rr opts =
    opts{humanCollapseRules = Just (rewriteCollapse rr)}

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
'parseRewriteRulesYaml' loader. Slice S2 of @specs\/032-tx-inspect@
added the collapse plumbing ('applyCollapseFromRewriteRules'). Slice S3
of @specs\/032-tx-inspect@ adds the rename plumbing
('applyRenameFromRewriteRules') and the composite 'applyRewriteRules'
that wires both stages into a single 'HumanRenderOptions' transformer.
The render-time stage order (collapse first, rename second) is enforced
by the shared render core in 'Cardano.Tx.Diff' — rename matches at leaf
sites (payment addresses, scripts) while collapse matches at array
sites; the two never race.

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

    -- * Application
    applyCollapseFromRewriteRules,
    applyRenameFromRewriteRules,
    applyRewriteRules,
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
-}
applyCollapseFromRewriteRules ::
    RewriteRules -> HumanRenderOptions -> HumanRenderOptions
applyCollapseFromRewriteRules rr opts =
    opts{humanCollapseRules = Just (rewriteCollapse rr)}

{- | Stage-2 plumbing: lift the 'rewriteRename' field of a 'RewriteRules'
value into 'HumanRenderOptions' so the shared render core consults the
'humanRenameRules' channel when it visits a payment-address or script
leaf.

The application semantics, per FR-009 of @specs\/032-tx-inspect@:

* 'Cardano.Tx.Diff.ConwayAddressValue' leaves are looked up against
  each address rule — 'Cardano.Tx.Diff.MatchFull' compares the full
  'Cardano.Ledger.Address.Addr' byte-for-byte; the default
  'Cardano.Tx.Diff.MatchPayment' compares the payment credential only
  (one rule covers every stake variant of the same payment script).
* 'Cardano.Tx.Diff.ConwayScriptValue' and the @SJust@ branch of
  'Cardano.Tx.Diff.ConwayReferenceScriptValue' leaves are hashed and
  looked up against each script rule.
* First match wins. An unmatched identifier renders verbatim (FR-010);
  rename never causes a failure or a missing structural element.

Empty rule lists are a no-op (the rename lookup is short-circuit on the
list-empty path). Feeding 'defaultRewriteRules' is safe and idempotent.
-}
applyRenameFromRewriteRules ::
    RewriteRules -> HumanRenderOptions -> HumanRenderOptions
applyRenameFromRewriteRules rr opts =
    opts{humanRenameRules = Just (rewriteRename rr)}

{- | Composite stage-1 + stage-2 plumbing: populate both
'humanCollapseRules' and 'humanRenameRules' from a single
'RewriteRules' value. The order in which the two plumbing helpers are
composed is irrelevant — the *render-time* stage order is hard-wired by
the shared render core in 'Cardano.Tx.Diff' (rename matches at leaf
sites, collapse matches at array sites — the two never race regardless
of which order they were stamped into 'HumanRenderOptions'). This is
the rendering invariant SC-004 of @specs\/032-tx-inspect@ pins down.

This is the helper @app\/tx-inspect\/Main.hs@ calls: one composite that
covers both stages, plus the back-compat fallbacks the per-stage
helpers expose for callers that need exactly one stage.
-}
applyRewriteRules ::
    RewriteRules -> HumanRenderOptions -> HumanRenderOptions
applyRewriteRules rr =
    applyCollapseFromRewriteRules rr . applyRenameFromRewriteRules rr

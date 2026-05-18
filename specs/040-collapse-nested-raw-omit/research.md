# Research: collapse engine — nested rules + `raw: omit`

**Branch**: `040-collapse-nested-raw-omit` | **Date**: 2026-05-18

Phase 0 of `/speckit.plan`. Resolves the technical decisions the plan
depends on. Alternatives considered are documented so future readers
understand the trade-off space.

## R1. Nested-rule recursion: path rewriting at recursion time, no engine-state stack

**Decision**: When a parent `CollapseRule` matches an item at index `idx` under array path `basePath`, the engine recurses into the matched item's subtree by:

1. Computing the matched-item base path: `itemBase = basePath </> show idx`.
2. Rewriting each child rule in `parent.collapseRuleNested` to an absolute-path rule by setting its `at:` to `itemBase </> childAt`. The child's `collapseRuleRequired` and `collapseRuleNested` are carried through unchanged (they are also relative — required leaves are relative to the matched item, grandchild `at:` is relative to its parent match).
3. Building a per-item augmented rules value: top-level rules unchanged + the rewritten child rules concatenated. Wrapping it in `Maybe CollapseRules`.
4. Passing the augmented rules to the existing recursive `collectValueTrie` / `collectValueTriePruned` call inside `walkRaw` / `walkPruned`.

The existing `collapseRulesAt` (path-exact-equality lookup) needs **no changes** — it sees the augmented rules and finds the absolute-path child entries at the right depths.

**Rationale**:

- Minimal blast radius. `collectValueArray`'s body grows by one helper function call per matched item (the path-rewrite step). `collapseRulesAt`, `collectValueRequiredLeaves`, `collapseCoveredValueLeafPaths`, `insertValueCollapseView`, `groupValueLeaves`, and `collectValueTriePruned` are unchanged.
- No new engine state to thread (no rule-scope stack, no environment passed through every call).
- The recursion respects the existing per-item subtree boundary because the rewritten paths are anchored at `itemBase`. A grandchild rule whose absolute path coincidentally collides with a top-level rule's `at:` at a different depth would NOT fire spuriously at that depth — the recursion only matches at the rewritten absolute path.

**Alternatives considered**:

- **Option B — Engine-state rule-scope stack.** Pass a `[CollapseRules]` stack through every walker call; `collapseRulesAt` consults the head + the matching frames. Rejected — wider blast radius (every walker call gains a parameter), no benefit over path rewriting for the spec's bounded use case (Amaru fixture depth 2, synthetic test depth 3, no current need for cross-cutting rule scoping).
- **Option C — Recursive rule-flattening at parse time.** Walk the parsed rules at load time and flatten every nested rule into a single top-level list with `at:` paths pre-rewritten. Rejected — requires the loader to know about every possible parent-match path, which is data-dependent (the parent rule's `at:` is `body.outputs`, but the matched item indices are unknown until the tx is rendered). The path rewriting MUST happen at apply time.
- **Option D — A new "scope" parameter in `CollapseRule`.** Add `collapseRuleScope :: Maybe DiffPath` that the engine interprets as "only fire under this prefix". Rejected — duplicates information already implicit in the parent-child link, adds a public-API field the spec does not require.

**Site list note**: the recursion happens at every `collectValueArray` site in the engine — both the explicit array sites (`body.outputs`, `body.inputs`, etc.) and any array site reached deeper in the tree as we walk an `OpenValue` / `ConwayDiffValue`. The engine ALREADY recurses into arbitrary array sites today; this feature only changes which rules are visible at each recursion frame.

**Empty-default invariant**: a missing `nested:` key parses to `[]`, which the recursion step treats as a no-op (no rules to merge). This is the load-bearing backwards-compat property — existing documents go through the new code path but the new code path is a no-op for them.

---

## R2. `raw: omit` engine semantics: matched-item suppression, unmatched siblings unchanged

**Decision**: Add a fourth branch to the trailing `case` in `collectValueArray`:

```haskell
case (hasView, collapseRawViewEnabled collapseConfig) of
    (False, _)                  -> walkRaw path trie
    (True,  CollapseRawShow)    -> walkRaw (path </> "raw") withViews
    (True,  CollapseRawHide)    -> walkPruned path withViews
    (True,  CollapseRawOmit)    -> withViews                 -- NEW
```

The new branch returns the trie carrying the bucket views inserted by `insertValueCollapseView`, with **no** walk of the matched items' subtrees — neither verbatim (`walkRaw`) nor pruned (`walkPruned`).

The `(False, _) -> walkRaw path trie` branch is what handles "unmatched siblings render verbatim" — when no rule matched any item at this array site, the engine falls through to verbatim, and `CollapseRawOmit` does not change this. The spec's "matched item subtree-suppressed, unmatched siblings rendered verbatim" property is enforced by the engine's pre-existing `hasView` flag, which is `True` only when at least one rule's `insertValueCollapseView` matched at least one item.

**Rationale**:

- Symmetric with the existing `CollapseRawShow` / `CollapseRawHide` cases; the engine's structure is preserved.
- The `hasView` flag already discriminates between "this array site has at least one matched item" and "this site has zero matched items". `omit` reuses that discrimination — it is a third behavior gated on the same flag, not a new flag.
- The "matched-item-only" suppression is a property of `hasView`, not of `omit`. A `views.raw: omit` document with zero collapse rules has `hasView = False` everywhere and falls through to verbatim — this is the SC-005 no-op identity, automatic from the engine structure.

**Subtle invariant — mixed-matched-and-unmatched at the same array site**: today, the `walkRaw` / `walkPruned` branches walk **every** item under the array site, not just the matched ones. Under `omit`, **no item** is walked — the matched items are deliberately suppressed, AND the unmatched items at the same array site are ALSO suppressed.

This is a spec edge-case decision. The spec (Edge Cases section) says "Mixed matched / unmatched items under `raw: omit`: items matching a rule are suppressed below the bucket; items NOT matching any rule render verbatim. The bucket and the un-matched siblings coexist on screen." That is INCOMPATIBLE with the "trailing case returns `withViews` for `(True, CollapseRawOmit)`" approach, because that approach also drops the unmatched siblings.

**Correction**: the engine must walk the **unmatched** items only under `omit`, the same way it walks all items under `hide` with the matched-coverage-pruning applied to matched items. The implementation is:

```haskell
case (hasView, collapseRawViewEnabled collapseConfig) of
    (False, _)                  -> walkRaw path trie
    (True,  CollapseRawShow)    -> walkRaw (path </> "raw") withViews
    (True,  CollapseRawHide)    -> walkPruned path withViews
    (True,  CollapseRawOmit)    -> walkRawUnmatched path withViews
```

Where `walkRawUnmatched` is a new helper analogous to `walkRaw` but iterating only over items whose index is **not** in `coveredLeaves`'s keyset (i.e. items that no rule matched). This preserves the spec's "unmatched siblings render verbatim" edge case.

A second variant — walk **all** items but skip those that matched any rule — is functionally equivalent but slightly different in the rendered output ordering. The spec does not pin ordering; in practice unmatched siblings are typically interleaved with matched ones (e.g. a `body.outputs` array with output 0 = swap, output 1 = treasury-leftover, output 2 = user-payment). The `walkRawUnmatched` helper renders the unmatched outputs in their original index order, which is the spec's implicit expectation ("the bucket and the un-matched siblings coexist on screen" — implies the un-matched siblings appear in their natural order).

**Decision (final)**: implement `walkRawUnmatched` as the per-item walker filtered by `idx ∉ coveredLeaves.keys`. The S2 subagent will surface in WIP.md whether the simpler "skip via map filter" approach is cleaner than introducing a new helper; the orchestrator decides at review time.

**Rationale for the correction**: a strict reading of "matched items do not render below the bucket" naturally extends to "and unmatched items DO render below the bucket" — the same way `hide` walks every item with covered-leaf pruning, `omit` walks unmatched items only. Anything else would silently drop unmatched items the user did not opt into collapsing.

**Alternatives**:

- **Option B — Drop all items under `omit`, matched and unmatched.** Rejected — surprises the user when an array site mixes matched and unmatched items. The spec's explicit edge case in `spec.md` rules this out.
- **Option C — A separate per-rule `omit:` flag on each `CollapseRule`.** Rejected — orthogonal to `raw:` which is global on the document. The issue's text consistently scopes `omit` as a document-level `views.raw:` value.
- **Option D — Treat `omit` as engine-private and synthesise it from `hide` + an extra pruning pass.** Rejected — adds a redundant render pass; the spec's "no measurable performance regression" is easier to argue with a single-case dispatch.

---

## R3. `collapseRuleNested` defaults to `[]` at the parse layer, not via a Smart Constructor

**Decision**: The `FromJSON CollapseRule` instance reads `nested:` via `value .: ?"nested" .!= []`. The Haskell type's `collapseRuleNested` field has no default-via-smart-constructor; every internal construction site adds `, collapseRuleNested = []` explicitly (or, where the value matters, the actual list).

**Rationale**:

- Mirrors the existing pattern for `collapseRules :: [CollapseRule]` in `CollapseRules` — the top-level list has no default, every construction site supplies it.
- Adding a Smart Constructor `mkCollapseRule :: Text -> DiffPath -> [DiffPath] -> CollapseRule` would shrink the diff in test files but expand the public API surface — the type, the field accessor, the constructor name, AND the smart constructor — all of which would need to be re-exported from `Cardano.Tx.Rewrite`. The cost-benefit doesn't justify it for nine call sites.
- Open question P1 (plan.md) lists the nine sites; the S1 subagent edits them in the same commit.

**Alternatives**:

- **Smart constructor `mkCollapseRule`**: rejected per above.
- **`Default` instance on `CollapseRule`**: rejected — `CollapseRule` has no sensible default (the name, at-path, and required list are all mandatory).
- **`HasField` typeclass dispatch**: out of scope — we are not introducing a typeclass for one field.

---

## R4. Documentation lives in the existing `docs/rewriting-rules.md`, not a new file

**Decision**: Extend `docs/rewriting-rules.md` (created by #32's S5 slice) with two new sections — "Nested rules" and "`raw: omit`" — and update the existing "Pattern — keep payment addresses out of `required:`" section + worked example.

**Rationale**: The grammar doc is the canonical home for the rewriting-rules language. Splitting nested rules and `raw: omit` into a separate file would force the reader to follow cross-references and would create a doc-fragment that is hard to navigate. The doc already documents `CollapseRule` and `RenameRule`; nested rules and `raw: omit` are CollapseRule extensions and belong in the same place.

**Alternatives**:

- **Separate `docs/collapse-nested-rules.md` and `docs/raw-omit.md`** files: rejected — increases the surface a reader has to cover; we'd then need a "see also" pattern from the main grammar doc back to two separate files.
- **Inline documentation in Haddock only, no docs/ update**: rejected — `docs/rewriting-rules.md` is what the operator command (`tx-inspect`) links to from `docs/tx-inspect.md`; inline Haddock is not surfaced through the mkdocs site.

---

## R5. Synthetic depth-3 fixture in `Rewrite.ApplySpec`, not a checked-in CBOR fixture

**Decision**: The US5 / FR-004 / SC-004 depth-3 nested-rule assertion uses a hand-crafted `ConwayDiffValue` (or `OpenValue`) tree in `test/Cardano/Tx/Rewrite/ApplySpec.hs`, not a real Amaru / mainnet CBOR transaction.

**Rationale**:

- The Amaru `swap-1` fixture exercises depth 2 (parent `SwapOrder` + child `ScopeOwners`); no current real-tx fixture reaches depth 3.
- The depth-3 property is a property of the **engine**, not of any specific transaction shape. A synthetic tree with three nested array sites + carefully-chosen `required:` leaves at each level is sufficient.
- Adding a depth-3 real fixture would mean acquiring a real on-chain transaction with that shape — which currently doesn't exist (no Amaru-style protocol uses depth-3 datums today). The bar is artificial.

**Alternatives**:

- **Use a hand-crafted CBOR fixture under `test/fixtures/synthetic/`**: rejected — the engine is the unit under test, not the CBOR decoder. Going through CBOR adds a decoder round-trip that obscures the engine assertion.
- **Defer depth > 2 to a follow-up ticket**: rejected — the spec commits to arbitrary depth as a property of the engine; not testing it now means the next ticket that needs depth 3 has to re-prove the engine works at depth 3 from scratch.

---

## R6. The `tx-diff` cross-tool symmetry property is preserved automatically; no new tx-diff test

**Decision**: FR-015 (cross-tool symmetry) is preserved automatically by S3's golden recapture, because the existing #032 `tx-diff` Amaru cross-check describe block in `InspectSpec.hs` already feeds `tx-diff` through the same `applyRewriteRules` → `renderConwayTxHuman` chain that `tx-inspect` uses. When `rules/amaru-treasury.yaml` changes in S3, both `tx-inspect` and `tx-diff` recapture against the same new bucket-only render. No new tx-diff-specific test is needed.

**Rationale**:

- The shared-substrate property is structural: both tools call `parseRewriteRulesYaml` → `applyRewriteRules` → `renderConwayTxHuman` on each side. Any engine change here is observed identically on both sides.
- Adding a new tx-diff-specific golden for the nested + omit shape would duplicate the assertion already implicit in the existing shared-substrate cross-check.

**Verification**: S3 subagent's WIP.md must record the tx-diff cross-check describe block name (from the existing InspectSpec) and confirm its golden is recaptured alongside the `tx-inspect` golden in the same slice. If the cross-check describe block is structured to recapture independently (separate golden file), both files are updated in the same commit.

**Alternatives**:

- **A new tx-diff-specific test in `test/Cardano/Tx/Diff/CliSpec.hs`**: rejected — duplicative.
- **Defer cross-tool verification to a follow-up `chore:`**: rejected — FR-015 requires it in this PR.

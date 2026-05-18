# Feature Specification: collapse engine — nested rules + `raw: omit` mode for usable tx review

**Feature Branch**: `040-collapse-nested-raw-omit`
**Created**: 2026-05-18
**Status**: Draft
**Input**: GitHub issue #40 — "Make the rewriting-rules collapse engine usable for real tx review by adding two related primitives: (1) Nested collapse rules — a `CollapseRule` can carry child rules whose `at:` is interpreted relative to each matched item's subtree. Lets one rule express recurring nested patterns without per-output literal-path duplication and without positional wildcards. (2) `raw: omit` mode (or revised `raw: hide` semantics) — a collapsed-and-fully-summarised item is NOT rendered again as raw detail below the bucket. Today `raw: hide` only prunes the leaves the rule covered; the per-item subtree still renders, producing per-output noise."

## Background

This feature extends the **stage-1 collapse engine** of the unified rewriting-rules pipeline shipped by `tx-inspect` (issue #32). Stage 2 (rename) and the cross-tool sharing with `tx-diff` are unchanged.

The motivating fixture is the **Amaru treasury swap**: a real treasury transaction with **33 chunked outputs** (one logical swap intent realised as 33 ledger outputs because of the Amaru chunking scheme). Today's render with the checked-in `rules/amaru-treasury.yaml`:

- The `SwapOrder` collapse bucket correctly surfaces `coin: 0..31 / 32` and `datum.constructor: 0..32`. The bucket itself is correct and useful.
- However, **for each of the 33 outputs the FULL datum tree is also rendered below the bucket.** Each datum tree contains the same committee-owners list (4 key-hashes) at `datum.fields.1.fields.0` — the engine has no way to express "the committee list inside every `SwapOrder` item" without positional wildcards.
- Result: a 33-chunk swap renders ≈ 33 × 100 lines of redundant per-output trees. The bucket header is buried; the diff between two swap fixtures is unreadable.

The collapse engine is **already correct** at the matching level — what's missing is (a) a way to attach child rules to a parent rule so the child runs on each matched item's subtree, and (b) a render-time mode that suppresses the per-item raw view when the bucket is the entire desired output. This feature adds both. Nothing else in the rewriting-rules pipeline changes — `CollapseRule`'s existing fields, `RenameRule`(s), `RewriteRules`, `parseRewriteRulesYaml`, and the engine's stage ordering are all preserved.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Treasury reviewer scans the 33-chunk Amaru swap as one bucket (Priority: P1)

A treasury reviewer holds the Amaru treasury swap CBOR transaction (33 chunked outputs, one logical intent). They want to see one `SwapOrder` bucket header naming the four variable slots (per-output address ranges, coin ranges, datum-constructor ranges, committee-owner list) — **and nothing else** under `body.outputs`. They edit `rules/amaru-treasury.yaml` to add a `nested:` child rule for the committee-owners list and switch `views.raw` to `omit`:

```yaml
collapse:
  - name: "SwapOrder"
    at: body.outputs
    match:
      required:
        - coin
        - datum.constructor
    nested:                                  # NEW
      - name: "ScopeOwners"
        at: datum.fields.1.fields.0          # relative to each SwapOrder item
        match:
          required:
            - constructor
            - fields.0
views:
  raw: omit                                  # NEW
```

They re-run `tx-inspect <tx> --rules rules/amaru-treasury.yaml`. The `body.outputs` section now shows one `SwapOrder` bucket header + its four variable-slot rows. The 33 per-output subtrees that used to follow the bucket are gone.

**Why this priority**: This is the load-bearing user experience the issue describes. Without these two primitives the rewriting-rules language can describe identifiers but not the structural shape of a real tx in a way a reviewer can scan. Both primitives are exercised together here; the orthogonal stories (US2–US5) prove each primitive works in isolation and under backwards-compat constraints.

**Independent Test**: Render the 33-chunk Amaru treasury swap fixture with the YAML above and assert the golden output: one `SwapOrder` header, one `ScopeOwners` nested header, the four variable-slot rows, and zero per-output detail trees under `body.outputs`. Compare line count against the pre-change golden — the new render is at least an order of magnitude shorter (target: ≤ 5% of the prior line count for `body.outputs`).

**Acceptance Scenarios**:

1. **Given** the Amaru 33-chunk swap CBOR transaction and a rewriting-rules YAML carrying the `SwapOrder` rule with a `ScopeOwners` nested rule and `views.raw: omit`, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the rendered `body.outputs` section contains exactly one `SwapOrder` bucket header, one `ScopeOwners` nested bucket header, and the four variable-slot rows — and no per-output detail tree appears below the bucket; exit code is 0.
2. **Given** the same inputs, **When** the reviewer compares the rendered line count for the `body.outputs` section against the pre-change render, **Then** the new render is at least an order of magnitude shorter (committee-owners list collapsed once, per-output trees suppressed).

---

### User Story 2 — Backwards compatibility: every existing rules YAML parses and renders byte-identically (Priority: P1)

Every collapse-rules YAML file that parses today via `parseRewriteRulesYaml` (issue #32) MUST continue to parse and render byte-identically after this feature lands. This includes:

- Documents with `collapse:` rules and no `nested:` key.
- Documents with `views.raw: show` (the default) or `views.raw: hide`.
- The checked-in `rules/amaru-treasury.yaml` at its current shape (no `nested:` key, `views.raw: hide`).

**Why this priority**: This is the migration safety net. P1 because issue #40 explicitly demands byte-identical behaviour for existing rules (acceptance criterion: "Backwards compatibility: existing rules (no `nested:` key) parse and render byte-identically"). It is co-equal in importance with US1: the feature is incomplete if existing fixtures regress, and the same goldens that prove US1 must also prove the bytes-equal property on a separate fixture.

**Independent Test**: Run the **existing** S2 `collapse-only.txt` and S4 Amaru both-stages goldens (from `specs/032-tx-inspect/`) unchanged. The bytes must equal the existing checked-in goldens. Additionally, parse the existing `rules/amaru-treasury.yaml` and assert the parsed `RewriteRules` value's `rewriteCollapse` field equals the pre-change result (deep equality at the type level).

**Acceptance Scenarios**:

1. **Given** any rewriting-rules YAML file accepted by the pre-change `parseRewriteRulesYaml` (no `nested:` key, `views.raw` in `{show, hide}`), **When** the post-change loader parses the file, **Then** the resulting `RewriteRules` value is equal — at the Haskell level — to the pre-change parser result (the only difference is that every `CollapseRule` now carries an empty `collapseRuleNested` list, which is a parse-time default, not a semantic change).
2. **Given** the existing `specs/032-tx-inspect/` Amaru goldens (collapse-only, rename-only, both-stages, baseline verbatim), **When** they are re-run after this feature lands, **Then** every golden produces byte-identical output and the goldens are NOT recaptured.

---

### User Story 3 — Nested rules without `raw: omit` (Priority: P2)

A reviewer adds a `nested:` rule to the `SwapOrder` collapse rule (committee-owners list) but leaves `views.raw: hide` (the current default in `rules/amaru-treasury.yaml`). The nested rule fires on each matched `SwapOrder` item: each item's per-instance subtree renders below the bucket as it does today, but **inside that subtree** the committee-owners list now also appears as a `ScopeOwners` named bucket with its own variable-slot rows.

**Why this priority**: P2 because nested rules and `raw: omit` are orthogonal primitives — each must work in isolation. This story proves the nested-rule recursion works under existing raw-view modes (`show` and `hide`). Without this story, a reviewer who wants nested buckets but keeps the per-item raw view (for instance, while still investigating an unknown field of a swap output) would be forced into `raw: omit`.

**Independent Test**: Render the Amaru 33-chunk swap fixture with a YAML that adds `nested: [ScopeOwners]` to `SwapOrder` and leaves `views.raw: hide`. Assert the rendered output: the `SwapOrder` bucket header + its slot rows; AND, below the bucket, each per-output subtree renders pruned (existing `hide` semantics on covered leaves) AND inside each per-output subtree the committee-owners list appears under a `ScopeOwners` nested header. The non-nested fixtures (US2) keep rendering byte-identically.

**Acceptance Scenarios**:

1. **Given** the Amaru 33-chunk swap fixture and a rules YAML with `SwapOrder` carrying a `ScopeOwners` nested rule and `views.raw: hide`, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the output contains one `SwapOrder` bucket header, the per-output subtrees render below the bucket with `hide` semantics (covered leaves pruned), and inside each per-output subtree the committee-owners list appears under a `ScopeOwners` nested header; exit code is 0.
2. **Given** the same inputs but with `views.raw: show`, **When** the renderer runs, **Then** the per-output subtrees render verbatim (existing `show` semantics — no leaves pruned), and inside each per-output subtree the committee-owners list **also** appears under a `ScopeOwners` nested header in addition to the verbatim render of the committee-owners list (the `ScopeOwners` bucket is purely additive on top of `show`'s verbatim render).

---

### User Story 4 — `raw: omit` without nested rules (Priority: P2)

A reviewer uses the existing checked-in `rules/amaru-treasury.yaml` shape — one flat `SwapOrder` collapse rule, no `nested:` key — but switches `views.raw` from `hide` to `omit`. The 33 per-output detail trees disappear; only the bucket header and the variable-slot rows remain.

**Why this priority**: P2 alongside US3 — the second leg of the "two orthogonal primitives" story. A reviewer who does not yet need nested buckets but already wants the per-item noise gone gets value from this feature with a one-key change to their YAML.

**Independent Test**: Render the Amaru 33-chunk swap fixture with the existing flat `SwapOrder` rule and `views.raw: omit`. Assert the rendered `body.outputs` section contains exactly the bucket header and its variable-slot rows — no per-output detail subtrees. Per-output items that did NOT match the `SwapOrder` rule (treasury-leftover, user-payment outputs) continue to render normally.

**Acceptance Scenarios**:

1. **Given** the Amaru 33-chunk swap fixture and a rules YAML with the existing flat `SwapOrder` rule and `views.raw: omit`, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the rendered `body.outputs` section contains exactly the `SwapOrder` bucket header and its variable-slot rows; the treasury-leftover and user-payment outputs render normally below it; exit code is 0.
2. **Given** the same fixture with `views.raw: hide`, **When** the renderer runs, **Then** the per-output subtrees for matched items DO render (with covered leaves pruned), proving `omit` and `hide` differ exactly at the matched-item subtree-suppression step.

---

### User Story 5 — Deep nesting (depth > 1) (Priority: P3)

A reviewer authors a nested rule that itself carries a `nested:` list. The engine MUST recurse to arbitrary depth, applying each generation's rule with `at:` interpreted relative to the previously-matched item's subtree.

**Why this priority**: P3 because no checked-in Amaru fixture currently requires depth > 1, but the spec must commit to it so future identifier-family follow-ups (a committee whose voters carry nested annotations, a swap whose datum carries a nested order book, etc.) do not require a re-architecture. A synthetic test fixture (a hand-crafted YAML + a fixture that exercises the third level) is sufficient.

**Independent Test**: Build a synthetic test in `Rewrite.ApplySpec` with a depth-3 rule chain (parent → child → grandchild) and a fixture where each level matches. Assert the rendered output contains one bucket header at every depth and the grandchild's variable slots appear with `omit` mode suppressing the deepest verbatim subtree.

**Acceptance Scenarios**:

1. **Given** a synthetic fixture and a rules YAML with three levels of `nested:` rules, **When** the renderer runs with `views.raw: omit`, **Then** the rendered output contains a bucket header at each of the three depths and the grandchild's variable-slot rows; no verbatim subtree from any matched item appears.
2. **Given** the same setup with `views.raw: hide`, **When** the renderer runs, **Then** each level's bucket header appears, the per-item subtree below the bucket renders pruned, and the recursion continues into the pruned subtree (a nested rule whose parent's `hide` removed the carrier path is gracefully a no-op for that item — no crash, no error).

---

### Edge Cases

- **Empty `nested:` list**: A `CollapseRule` whose `nested:` key parses to `[]` is semantically identical to one with no `nested:` key — the engine never recurses, the existing render path is taken verbatim. (Tested via parse equality in US2.)
- **`nested:` key absent**: Same as above — `collapseRuleNested = []` is the parser default for legacy documents, and the engine treats it as "no recursion".
- **Nested rule whose `at:` is not present in a matched item**: The nested rule's matcher finds no array site at the relative path. The engine MUST NOT crash and MUST NOT emit a bucket header for the missing site; rendering of the parent item proceeds under the current `raw:` mode.
- **Nested rule whose parent did not match**: The nested rule never runs against that item (the recursion is gated on the parent match). It MAY run against a sibling item if that sibling matched.
- **`raw: omit` with no matching items**: If a `CollapseRule`'s parent `at:` site has zero items matched (e.g. an array of one element none of whose required leaves resolve), the engine MUST behave as if no rule were present — the array site renders verbatim, no bucket header is emitted. `omit` does not suppress unmatched items.
- **Mixed matched / unmatched items under `raw: omit`**: At a single array site (e.g. `body.outputs`), items matching a rule are suppressed below the bucket; items NOT matching any rule render verbatim. The bucket and the un-matched siblings coexist on screen.
- **`raw: omit` with no collapse rules at all**: A document with `views.raw: omit` and an empty `collapse:` list MUST render every array site verbatim (no items are matched, so no items are omitted). The setting becomes a no-op rather than an error.
- **Loader rejects malformed `nested:`**: A `nested:` value that is not a YAML list, or whose entries are not valid `CollapseRule` shapes, MUST produce a `Left <parse-error>` — same failure mode as a malformed top-level `collapse:` entry today.
- **Loader rejects unknown raw-view value**: `views.raw: <anything other than show / hide / omit>` MUST produce a `Left <parse-error>` naming the offending value and listing the accepted set.
- **Deep nesting and large fixtures**: The engine MUST handle the 33-chunk Amaru swap fixture (depth 2: `SwapOrder` parent + `ScopeOwners` child) without measurable performance regression vs. the current flat render. Performance work beyond "no measurable regression on the Amaru fixture" is **out of scope** (see Out of Scope).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `CollapseRule` Haskell type MUST gain a new field `collapseRuleNested :: [CollapseRule]` representing the rule's nested children. Existing fields (`collapseRuleName`, `collapseRuleAt`, `collapseRuleRequired`) MUST remain unchanged in name, type, and semantics. The new field MUST be appended (not interleaved) for source-diff readability and so unrelated call sites compile unchanged when they construct `CollapseRule` via record syntax.
- **FR-002**: The YAML loader (`parseRewriteRulesYaml`) MUST accept an optional `nested:` key on each `CollapseRule` entry carrying a list of `CollapseRule` entries. A missing `nested:` key MUST parse to `collapseRuleNested = []`. The legacy compatibility property of `parseRewriteRulesYaml` (issue #32) MUST be preserved: every document accepted by the pre-change loader MUST parse to a `RewriteRules` value equal to the pre-change result modulo the new empty `collapseRuleNested` defaults.
- **FR-003**: The collapse engine — specifically the array-site walker that today consults `collapseRulesAt` at each `body.outputs` / `body.inputs` / similar — MUST recurse into each matched item's subtree applying every child rule in `collapseRuleNested`. The child's `collapseRuleAt` MUST be interpreted **relative** to the matched item's base path (not absolute from the tx root).
- **FR-004**: The recursion MUST support arbitrary depth: a nested child can itself carry a non-empty `collapseRuleNested`, and the engine MUST apply it relative to that child's matched items. There MUST NOT be a hard-coded depth limit.
- **FR-005**: The `CollapseRawView` enum MUST gain a new constructor `CollapseRawOmit`. Existing constructors (`CollapseRawShow`, `CollapseRawHide`) MUST remain unchanged.
- **FR-006**: The YAML loader MUST accept `views.raw: omit` as a third value alongside the existing `show` / `hide`. The accepted value list in the parse-error path for an unknown raw-view MUST be updated to enumerate all three (`show | hide | omit`).
- **FR-007**: When the document-global `collapseRawView` is `CollapseRawOmit`, the engine at each array site where at least one collapse rule matched MUST suppress the per-item raw rendering for every **matched** item — neither verbatim (`show`-like) nor pruned (`hide`-like) detail trees are emitted for matched items. Items at the same array site that did NOT match any rule MUST continue to render under the engine's default verbatim path (independent of `omit`).
- **FR-008**: Existing `CollapseRawShow` semantics ("walk every item verbatim under the bucket") and `CollapseRawHide` semantics ("walk every item with the covered leaves pruned") MUST be unchanged for inputs that do not use the new features. This is the regression contract enforced by the goldens recaptured-as-unchanged property in US2.
- **FR-009**: The checked-in `rules/amaru-treasury.yaml` MUST be updated to use both new features: add a `ScopeOwners` nested rule under `SwapOrder` covering the committee-owners list at `datum.fields.1.fields.0`, and set `views.raw: omit`. The motivation for this change MUST be documented inline in the YAML comments alongside the existing stage-2 comments (rename rules block).
- **FR-010**: A new golden test (or recaptured Amaru golden) MUST drive `tx-inspect` against the existing Amaru 33-chunk swap CBOR fixture with the updated `rules/amaru-treasury.yaml` (nested + omit) and assert the rendered output matches the recaptured golden, demonstrating the bucket-only view of the swap.
- **FR-011**: `test/Cardano/Tx/Rewrite/LoadSpec.hs` MUST be extended with:
  - one or more `it` blocks covering `nested:` parsing (a rule with `nested:`, a rule with empty `nested: []`, a rule with no `nested:` key parses to `collapseRuleNested = []`);
  - one or more `it` blocks covering deeply-nested fixtures (a YAML with `nested:` carrying a child that itself carries `nested:` parses successfully);
  - one or more `it` blocks covering parse errors (malformed `nested:`, `views.raw: omit` accepted, unknown raw-view rejected with a message listing the accepted set);
  - one or more `it` blocks covering legacy compatibility (every existing collapse-only fixture in this spec parses to a `RewriteRules` value equal to the pre-change result).
- **FR-012**: `test/Cardano/Tx/Rewrite/ApplySpec.hs` MUST be extended with:
  - matched-item recursion: a parent rule's match triggers the child rule's matcher on the matched item's subtree (assert the child's `at:` is interpreted relative to the item base);
  - non-matched item: a sibling item that did not match the parent MUST NOT have the child rule evaluated against it;
  - depth > 1: a depth-3 rule chain matches at every level (uses a synthetic fixture; no real-tx fixture is required at depth 3 — see Assumptions);
  - `omit` semantics: a matched item under `omit` has zero per-item subtree emitted; an unmatched sibling at the same array site renders verbatim;
  - `omit` no-op: a rules document with `omit` but no collapse rules renders verbatim.
- **FR-013**: `test/Cardano/Tx/InspectSpec.hs` MUST be extended with at least one new fixture-driven `describe` block that loads the recaptured Amaru `rules/amaru-treasury.yaml` (with `nested:` + `views.raw: omit`) and asserts the rendered output equals the recaptured Amaru both-stages golden file (FR-010). The other Amaru goldens (verbatim, collapse-only, rename-only — defined in `specs/032-tx-inspect`) MUST continue to pass byte-identically (US2 regression contract).
- **FR-014**: `docs/rewriting-rules.md` MUST be extended with:
  - a new section "Nested rules" describing the `nested:` key on `CollapseRule`, the relative `at:` semantics, depth, and a worked example (the Amaru `SwapOrder` + `ScopeOwners` rule pair);
  - a new section "`raw: omit`" describing the new raw-view mode, the matched / unmatched item distinction, and the no-op behaviour when no rules match;
  - an update to the existing "Pattern — keep payment addresses out of `required:`" section noting that nested rules give an alternative path to collapsing identifier-bearing subtrees without bypassing the rename layer (since the nested rule, like the parent rule, leaves un-`required:`ed leaves available to the rename pass);
  - an update to the worked example at the end of the doc to reflect the new `rules/amaru-treasury.yaml` shape (nested + omit).
- **FR-015**: The cross-tool symmetry guaranteed by issue #32 (one loader, one engine, one docs page; `tx-diff` and `tx-inspect` consume the same file format through the same loader) MUST be preserved. Specifically: the same updated `rules/amaru-treasury.yaml` MUST drive `tx-diff` on a pair of Amaru swap fixtures with the new collapse behaviour applied identically on both sides of the diff. The `tx-diff` Amaru cross-check golden (the existing S4 cross-check from `specs/032-tx-inspect`) MUST be recaptured to the same line-count-reduction target as the `tx-inspect` golden, but no new `tx-diff`-specific golden file is introduced — the existing cross-check fixture is reused.

### Key Entities *(include if feature involves data)*

- **`CollapseRule`** *(existing, extended)* — Gains a new field `collapseRuleNested :: [CollapseRule]` carrying the rule's nested children. Defaults to `[]` for documents that omit the `nested:` key. Existing fields unchanged.
- **`CollapseRules`** *(existing)* — Unchanged. The recursion lives at the engine level, not in the type, because `CollapseRule` already carries its own nesting via the new field.
- **`CollapseRawView`** *(existing, extended)* — Gains a new constructor `CollapseRawOmit`. Existing `CollapseRawShow` and `CollapseRawHide` unchanged. YAML accepts `show | hide | omit`.
- **`RewriteRules`** *(existing)* — Unchanged. Stage 2 (rename) and the stage-order invariant (engine-enforced, not document-driven) are out of scope; the only field that changes meaning is `rewriteCollapse.collapseRawView`, which gains the new value.
- **`HumanRenderOptions`** *(existing)* — Unchanged at the type level. The collapse engine reads `humanCollapseRules` and dispatches on the new constructor; no new field is added.
- **`OpenValue` / `DiffPath`** *(existing)* — Unchanged. The relative-`at:` semantics for nested rules are an engine-level interpretation, not a new path type.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The rendered `body.outputs` section of the 33-chunk Amaru treasury swap fixture, under the updated `rules/amaru-treasury.yaml` (nested + omit), is **at least an order of magnitude shorter** than the pre-change render (target: ≤ 5% of the pre-change line count). Specifically: the `SwapOrder` bucket header + `ScopeOwners` nested header + the four variable-slot rows are present; no per-output detail subtree appears.
- **SC-002**: Every existing rewriting-rules YAML fixture in this repository (the checked-in `rules/amaru-treasury.yaml` pre-change shape; every fixture YAML under `test/fixtures/`) parses to a `RewriteRules` value byte-equal to the pre-change parser result modulo the empty `collapseRuleNested` defaults. Zero parsing regressions on existing rules.
- **SC-003**: Every existing golden file in `specs/032-tx-inspect/` (Amaru baseline verbatim, collapse-only, rename-only, and the pre-nested both-stages golden) continues to be reproduced byte-identically when its corresponding rules YAML does not use the new features. Zero render regressions on existing inputs.
- **SC-004**: A depth-3 nested-rule chain (parent → child → grandchild) on a synthetic fixture produces a render with one bucket header per depth and zero verbatim subtrees under `views.raw: omit`. The engine handles depth > 2 without a code path specific to depth 2.
- **SC-005**: A `views.raw: omit` document with zero collapse rules, fed to `tx-inspect` on any tx, renders identically to the same tx rendered with `views.raw: show` and zero collapse rules — `omit` is a no-op when no items are matched.
- **SC-006**: An unknown `views.raw:` value (e.g. `skip`, `redact`, the empty string) produces a `Left <parse-error>` that names the offending value and enumerates the accepted set (`show`, `hide`, `omit`). The parse error is produced at load time, not at render time.
- **SC-007**: The cross-tool symmetry property holds: `tx-diff` over two Amaru treasury swap fixtures with the new `rules/amaru-treasury.yaml` produces a diff where the `body.outputs` section on each side is the bucket-only view, and the rendered output is identical to what `tx-inspect` produces for each side independently.

## Assumptions

- The "33-chunk Amaru treasury swap fixture" referenced in US1 / FR-010 / SC-001 is the **existing** Amaru swap fixture(s) checked into `test/fixtures/` by `specs/032-tx-inspect/` (the spec does not require a new fixture). If the existing fixture is the 2-output swap rather than a 33-chunk swap, the spec's "33-chunk" framing reduces to a maximally-chunked Amaru swap fixture available in the test corpus; the line-count-reduction property (SC-001) is asserted on whichever Amaru swap fixture is available, scaled to its chunk count.
- The motivating "≈ 100 lines per per-output tree" figure cited in the issue is illustrative; the spec asserts the relative reduction (≤ 5% of pre-change line count) on whichever Amaru fixture ships, not an absolute line count.
- The synthetic depth-3 fixture required by US5 / FR-012 / SC-004 lives in `test/Cardano/Tx/Rewrite/ApplySpec.hs` as in-test data, not as a checked-in CBOR fixture. Synthetic fixtures for engine-level invariants are acceptable in this spec — the cross-tool fidelity of US1–US4 covers the real-fixture path.
- The committee-owners path `datum.fields.1.fields.0` in US1's worked example is the path the issue cites. The spec assumes this is correct for the current Amaru swap fixture; if planning reveals the actual path differs, the spec's worked-example YAML is updated to match the actual path without altering any FR or SC.
- The rename layer (stage 2) is **not** affected by this feature. Nested rules surface variable slots that are still subject to rename in the same way the parent rule's variable slots are. No new rename behaviour is required.

## Out of Scope

The following are explicitly **not** delivered by this feature and remain available as separate follow-up tickets:

- **Wildcards in `at:`**. Nested rules are the deliberate alternative; the issue rejects path wildcards as "positional and brittle, and the nested-rules design covers the same use cases without the path-syntax ambiguity".
- **A subtree-shape query language** (pattern matching against datum structure). Same reasoning as above — nested rules + `required:` already express the matching idiom needed for the Amaru fixture; a richer query language is a separate axis.
- **Plutus blueprint integration for typed field names**. Tracked as a follow-up to issue #39's synthesis: once datums carry typed field names (rather than positional `fields.N` paths), nested rules will become more readable, but the type system itself is out of scope here.
- **Renaming inside `OpenValue` / datum subtrees**. Tracked as issue #39. This feature gives the collapse engine the ability to *name* recurring leaves (via `ScopeOwners` and similar nested rules); using those names to substitute 28-byte leaves inside datum trees is the orthogonal second axis #39 addresses.
- **Performance work on the recursive walker**. The engine MUST handle the Amaru fixture without measurable performance regression (SC-003 implicitly — existing goldens still pass), but no profiling-driven optimisation or asymptotic-complexity guarantee is required by this spec. Performance work is a separate ticket.
- **A renamed-or-redesigned `views.raw:` key**. The new value (`omit`) is additive on the existing key. Renaming the key, splitting it into separate per-rule flags, or generalising it to other axes (e.g. per-stage suppression) is out of scope.

## Command Recovery

Per the resolve-ticket command-recovery rule, this feature ships **no new operator command**: the operator surface is the existing `tx-inspect` CLI from issue #32 (and, by the cross-tool symmetry of FR-015, the existing `tx-diff` CLI). The new YAML keys (`nested:` and `views.raw: omit`) are inputs to those existing commands.

The operator command remains:

```bash
tx-inspect <tx-input> --rules <path> [--n2c-socket-path <socket> | --web2-… <args>]
```

And the smoke proof for the same path remains `just smoke-inspect`, exercising the same `tx-inspect` executable end-to-end through the same `main`. No new test-only renderer entry point is introduced; the golden tests in FR-010 drive the production command path via `renderConwayTxHuman` (the shared render entry point shipped by `specs/032-tx-inspect`).

The library- and parser-level changes (the new `CollapseRule.collapseRuleNested` field, the new `CollapseRawOmit` constructor, the YAML keys) MUST surface through the same operator command without a new flag, subcommand, or executable.

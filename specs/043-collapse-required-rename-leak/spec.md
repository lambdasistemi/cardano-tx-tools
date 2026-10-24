# Feature Specification: collapse no longer disables rename for `required:`-pinned leaves

**Feature Branch**: `043-collapse-required-rename-leak`
**Created**: 2026-05-18
**Status**: Draft
**Input**: GitHub issue #43 — "The rewriting-rules pipeline advertises `collapse:` and `rename:` as two orthogonal stages run in engine-enforced order (collapse first, rename second). In practice, when a collapse rule's `required:` list pins a payment-address path, the address at that path bypasses the rename layer entirely. … Same address, two different sites, two different renderings."

## Background

The rewriting-rules pipeline shipped by #32 defines two orthogonal stages: **collapse** (structural shape primitive — fold repeated structural skeletons into named buckets) and **rename** (identifier-substitution primitive — substitute payment addresses and script hashes with address-book names). The shared engine documentation in `docs/rewriting-rules.md` explicitly characterises stage order as "engine-enforced (collapse first, rename second)" with the implicit promise that the two stages compose orthogonally — a rule in one stage does not silently disable a rule in the other.

In practice, this orthogonality breaks at one specific seam: when a `CollapseRule`'s `required:` list pins a **payment-address path** (e.g. `resolved.address`, or any path whose leaf is a Conway `Addr` value), the engine snapshots that leaf as an opaque `Aeson.Value` during the collapse pre-extraction step. The rename layer, which only fires on **typed** `ConwayAddressValue` / `ConwayScriptValue` leaves, never sees the snapshot. Result: the same address renders **with** its address-book name at every site EXCEPT the collapse bucket's required-slot rows, where it renders as the raw bech32 / hex.

The same defect almost certainly affects `kind: script` rules when a script-hash path is pinned in `required:` — the snapshot mechanism is symmetric. The issue speculates this is the case; this feature commits to fixing both axes as one orthogonality fix, not two independent bugs.

The current `docs/rewriting-rules.md` ships a workaround section titled *"Pattern — keep payment addresses out of `required:`"* that teaches the operator to leave identifier-bearing paths in the per-instance remainder. That section IS the bug — it shifts the defect onto the operator. The feature deletes that section as part of the fix; the orthogonality guarantee is then unconditional.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Treasury reviewer collapses inputs by payment address AND renames them (Priority: P1)

A treasury reviewer holds a real-world Cardano transaction (the contingency-disburse fixture from `lambdasistemi/amaru-treasury-tx#170`) with multiple inputs from the same payment script and a per-intent rules YAML that:

1. Collapses `body.inputs` into an `Input` bucket whose required slots include `resolved.address` and `resolved.coin`.
2. Renames the contingency-self payment script to `amaru-treasury.contingency.account`.

They run:

```bash
tx-inspect contingency-disburse.cbor.hex --rules rules/contingency-disburse.yaml
```

Each input's `resolved.address` row in the `Input` bucket appears as `amaru-treasury.contingency.account` — the same name that appears at the body-output `address` site that was NEVER collapsed. The two rendering paths are byte-identical for the same address.

**Why this priority**: This is the load-bearing operator experience. The reviewer's expectation is "same address, same name everywhere"; the current pipeline breaks that expectation at one specific seam (collapsed required-slot rows). Per the issue, this is what drove the bug report — the operator originally diagnosed it as a broken rename rule before identifying the pre-extraction snapshot as the actual cause.

**Independent Test**: Render the contingency-disburse fixture under reproducer-A's rules YAML (`resolved.address` in `required:`) and reproducer-B's rules YAML (`resolved.address` removed from `required:`). The two renders MUST be byte-identical for the address-rendering path — both show `amaru-treasury.contingency.account` at every input's `resolved.address` site. The bucket vs no-bucket distinction is the only legitimate structural difference between the two renders.

**Acceptance Scenarios**:

1. **Given** a Cardano transaction with two or more inputs sharing the same payment credential and a rules YAML that pins `resolved.address` in a collapse rule's `required:` list AND carries an address rename rule for that payment credential, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the rendered output shows the address-book name at every input's `resolved.address` row inside the bucket; no raw bech32 or hex appears for a renamed address; exit code is 0.
2. **Given** the same transaction with the address path **removed** from `required:` (reproducer B from issue #43), **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the rendered address line at the un-collapsed `inputs.0.resolved.address` site equals the bucket-rendered line from scenario 1 — same name, same string, same bytes for the address-rendering path.

---

### User Story 2 — Backwards compatibility: every existing rules YAML and every existing golden remains byte-identical (Priority: P1)

Every collapse-rules YAML file that parses and renders today MUST continue to parse and render byte-identically after this feature lands, provided **no rename rule matches a `required:`-pinned leaf** in the file. This covers:

- Documents with `collapse:` rules whose `required:` lists do NOT pin identifier paths (the dominant case — the checked-in `rules/amaru-treasury.yaml`'s `SwapOrder` rule pins `coin` and `datum.constructor`, neither of which carries an address or script hash).
- Documents with no `rename:` section at all.
- Every existing fixture YAML under `test/fixtures/` and every operator-facing rules YAML in `rules/`.

**Why this priority**: This is the migration safety net. P1 because shipping an engine fix that retroactively changes the rendered bytes of an existing golden — even when "more correct" — is a regression for operators tracking diffs of `tx-inspect` output (e.g. release-validation pipelines, on-call review scripts). The feature is incomplete if a single existing golden recaptures inadvertently.

The byte-identical property is conditional on "no rename rule matches a `required:`-pinned leaf": YAML files that pin an address path AND carry a rename rule for that address WILL legitimately render differently after this feature — that is the User Story 1 fix observable as bytes. The regression check covers only the orthogonal-input case (no matching rename rule).

**Independent Test**: Run the full existing `Cardano.Tx.InspectSpec` suite. Every pre-existing golden (`inspect.verbatim.txt`, `inspect.collapse-only.txt`, `inspect.rename-only.txt`, the Amaru `swap-1.both.txt` and `swap-1.both.resolved.txt`, the corresponding `*.unresolved.txt` variants) MUST be reproduced byte-identically by the post-feature engine. Zero recaptures.

**Acceptance Scenarios**:

1. **Given** any rules YAML in the repository whose `collapse:` rules' `required:` lists do NOT pin a path whose leaf is an address or script-hash, **When** that YAML is fed to the post-feature engine, **Then** the rendered output is byte-identical to the pre-feature render.
2. **Given** the full `Cardano.Tx.InspectSpec` suite as it stands before this feature lands, **When** the suite is re-run after the feature lands, **Then** every test passes with zero golden recaptures.

---

### User Story 3 — Symmetric fix for `kind: script` paths (Priority: P1)

A reviewer authors a rules YAML that:

1. Collapses an array of script witnesses whose required slot is a script-hash path.
2. Renames the script-hash via a `kind: script` rule.

The reviewer expects the script's address-book name at the bucket's required-slot row, the same way the un-collapsed witness-set / reference-script renderings produce the name.

**Why this priority**: P1 because the issue speculates the defect is symmetric and the engine inspection confirms it: the same pre-extraction snapshot mechanism strips `ConwayScriptValue` typed identity the same way it strips `ConwayAddressValue` typed identity. Fixing only one axis would leave a known parallel defect and the orthogonality claim still false. Co-P1 with User Story 1 because the fix MUST cover both axes in the same engine change — they are the same code path, not two independent bugs.

**Independent Test**: Construct a synthetic test fixture in `Cardano.Tx.Rewrite.ApplySpec` with a collapse rule pinning a script-hash path in `required:` and a `kind: script` rename rule for that hash. Assert the rendered output shows the rename name at the bucket's required-slot row.

**Acceptance Scenarios**:

1. **Given** a transaction with multiple script-hash references and a rules YAML pinning the script-hash path in `required:` with a matching `kind: script` rename rule, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the script-hash rows inside the collapse bucket render the rename name; no raw 56-character hex appears for a renamed script.

---

### User Story 4 — Operator-visible documentation: the workaround section is deleted (Priority: P2)

A reviewer reading `docs/rewriting-rules.md` after this feature lands MUST NOT find any text instructing them to "keep payment addresses out of `required:`" or warning that pinning identifier paths in `required:` disables rename. The orthogonality promise is unconditional in the docs — the same as it now is in the engine.

**Why this priority**: P2 because the engine fix is the load-bearing change; the docs deletion is a follow-on once the engine no longer needs the workaround. But the deletion MUST land in the same PR — leaving the docs warning in place while the engine has been fixed creates a worse confusion than the original defect ("the docs say I have to do X, but the engine seems to be fine when I don't?").

**Independent Test**: After the feature lands, `grep -i 'keep payment addresses\|payment-address.*required\|pre-extraction' docs/rewriting-rules.md` MUST return no matches. The grammar doc's `CollapseRule` section MUST NOT describe any interaction between `required:` and the rename layer.

**Acceptance Scenarios**:

1. **Given** the post-feature `docs/rewriting-rules.md`, **When** a reviewer reads the document end-to-end, **Then** there is no section, note, caveat, or paragraph describing a `required:`–rename interaction. The two stages are documented as orthogonal without exception.

---

### User Story 5 — `LoadSpec` and `ApplySpec` cover the cross-stage property (Priority: P2)

The bug surfaces from a cross-stage interaction (`collapse.required:` × `rename.kind:`) that no existing test covers. Even after the engine fix, the test suite MUST include at least one test that asserts the "rename idempotent across collapse" property: render the same transaction twice, once with the path pinned in `required:` and once without; assert the address-rendering path is byte-identical between the two renders.

**Why this priority**: P2 because the User Story 1 / 3 acceptance scenarios already exercise the fix at the goldens level. The property test is what catches a future regression that the goldens would not — e.g. if a refactor of the snapshot mechanism reintroduces the typed-identity loss. Co-P2 with User Story 4 because both are non-load-bearing for the bug fix itself but load-bearing for the long-term correctness invariant.

**Independent Test**: A new `it` block in `Cardano.Tx.Rewrite.ApplySpec` (or `Cardano.Tx.InspectSpec`) that constructs the same fixture under two rules YAMLs (one pinning the address path, one not) and asserts the rendered address row is identical between the two outputs. The bucket-header vs no-bucket-header structural difference is the only legitimate diff.

**Acceptance Scenarios**:

1. **Given** a fixture transaction and two rules YAMLs differing only in whether an address path appears in a collapse rule's `required:` list, **When** the engine renders both, **Then** the address-rendering line at the relevant site is identical between the two renders (string-equality on the renamed name).

---

### Edge Cases

- **`required:` path resolves to a non-identifier leaf** (e.g. `coin`, `datum.constructor`, an integer or numeric leaf): the engine continues to snapshot the `Aeson.Value` and render it via `renderJsonValue` — there is no rename rule that matches a numeric leaf, so the behaviour is unchanged. The fix is identifier-only (address + script-hash) and does NOT change rendering of non-identifier required leaves.
- **`required:` path resolves to a `ConwayAddressValue` but NO rename rule matches**: the engine snapshots the typed value, attempts a rename lookup, gets `Nothing`, and falls back to rendering via the existing JSON-value path (the same render the snapshot would have produced today). Behaviour unchanged — best-effort rename preserved.
- **`required:` path resolves to a `ConwayAddressValue` and BOTH `match: payment` and `match: full` rules could apply** (e.g. a `match: full` rule for the exact bech32 plus a `match: payment` rule for the payment credential): existing rename-layer semantics apply unchanged — first-match-wins in YAML file order. The fix does not change rename precedence.
- **The same path is pinned in `required:` by multiple collapse rules** (e.g. two rules both list `resolved.address`): each rule's bucket independently consults the rename rules for its grouped rows. Both bucket renderings show the same rename name.
- **Cross-bucket grouping of renamed addresses**: today's grouping logic groups indices that share the same `Aeson.Value` (line 1311-1312 in `Cardano.Tx.Diff`). After the fix, two addresses that share a *payment credential* but differ in the *stake credential* would still be distinct `Aeson.Value`s — but both would render as the same rename name under `match: payment`. The grouping logic MUST therefore group by **rendered output** (the post-rename string), not by the raw `Aeson.Value`. Otherwise the bucket would show two adjacent rows with the same rename name but different index ranges, which is operator-confusing.
- **`required:` path inside a nested array site**: the engine recursion is unchanged by this feature — the snapshot mechanism's typed-identity preservation applies at every depth. (#40's nested-collapse feature is independent; this fix is at the leaf-snapshot layer.)
- **Resolved-input rendering**: the `body.inputs.*.resolved.address` site only exists when the resolver chain successfully resolved the input. An unresolved input has no `resolved.address` leaf, and the collapse rule's `required:` match fails (the path does not resolve) — the rule does not fire for that item. Unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A collapse rule whose `required:` list includes a path whose leaf is a `ConwayAddressValue` MUST preserve the value's typed identity end-to-end through the snapshot mechanism. The snapshot MUST carry enough information for the rename layer to fire on it.
- **FR-002**: A collapse rule whose `required:` list includes a path whose leaf is a `ConwayScriptValue` or a `ConwayReferenceScriptValue` (in its `SJust` branch) MUST preserve the value's typed identity end-to-end through the snapshot mechanism. Symmetric to FR-001.
- **FR-003**: When the rename layer matches a typed-leaf snapshot under FR-001 or FR-002, the bucket's required-slot row for that item MUST render the rename name (e.g. `amaru-treasury.contingency.account`), NOT the raw bech32 / hex.
- **FR-004**: When the rename layer does NOT match a typed-leaf snapshot (no rule matches the address or hash), the bucket's required-slot row MUST render via the same `Aeson.Value` path used today — backwards-compatible behaviour for the unmatched case.
- **FR-005**: The cross-bucket grouping of identical renamed addresses MUST group items by **rendered output** (the post-rename string), not by raw `Aeson.Value`. Specifically: two `body.inputs.*.resolved.address` leaves whose payment credentials match the same `match: payment` rule but whose stake credentials differ MUST appear as a SINGLE grouped index-range row in the bucket, not as two adjacent rows.
- **FR-006**: Every existing rewriting-rules YAML in the repository whose `collapse:` rules' `required:` lists do NOT pin a path whose leaf is an `Addr` or script-hash MUST render byte-identically pre- and post-feature. Zero recaptures of existing goldens. (US2 backwards-compatibility contract.)
- **FR-007**: A new `it` block in `Cardano.Tx.Rewrite.ApplySpec` MUST assert the "rename idempotent across collapse" property: render the same fixture under two rules YAMLs differing only in whether an address path appears in `required:`, and assert the renamed address row is string-identical between the two outputs.
- **FR-008**: A new `it` block (or extended fixture) in `Cardano.Tx.InspectSpec` MUST drive the engine on a real-world fixture (e.g. the existing `swap-cancel-issue-8` body or a checked-in synthetic CBOR) under a rules YAML that pins an address in `required:` AND carries a rename rule for that address. Golden bytes MUST show the rename name at the bucket's required-slot row.
- **FR-009**: A new `it` block in `Cardano.Tx.Rewrite.ApplySpec` MUST cover the symmetric `kind: script` case (US3 acceptance): pin a script-hash path in `required:`, register a `kind: script` rename rule, assert the bucket row shows the rename name.
- **FR-010**: `docs/rewriting-rules.md` MUST be edited to:
  - **Delete** the *"Pattern — keep payment addresses out of `required:`"* section in its entirety. No replacement section, no "previously documented as" pointer.
  - Confirm in the existing "Match semantics" / `CollapseRule` sections that `required:`-pinned identifier paths are subject to the rename layer the same as any other identifier site. (The wording is at the doc author's discretion; the only invariant is that no operator-visible caveat about `required:` × rename interaction survives.)
- **FR-011**: The fix MUST be additive to public-API surface: no type rename, no constructor rename, no exported-symbol removal in `Cardano.Tx.Diff` / `Cardano.Tx.Rewrite`. The engine-internal snapshot type (`Maybe Aeson.Value` → some richer type) is allowed to change because it is not exported.

### Key Entities *(include if feature involves data)*

- **`CollapseRule`** *(existing)* — Unchanged at the type level. The `collapseRuleRequired` field continues to carry a `[DiffPath]`. The change is in how the engine **interprets** the leaves resolved by those paths.
- **`RenameRule`** *(existing)* — Unchanged at the type level. The lookup logic (`lookupAddressRename`, `lookupScriptRename`) is reused unchanged on the typed-leaf snapshot.
- **`ConwayDiffValue`** *(existing)* — Unchanged at the type level. The engine-internal change is to carry `ConwayDiffValue` (or a subset constructor) through the snapshot mechanism instead of projecting to `Aeson.Value` at the bottom of `lookupValueAtPath`.
- **Engine-internal snapshot type** *(internal)* — The type that flows from `collectValueRequiredLeaves` to `insertValueCollapseView` changes from `[(DiffPath, Aeson.Value)]` to a richer type that preserves the source `ConwayDiffValue`. Not exported; not a public-API concern.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The contingency-disburse reproducer-A fixture (issue #43) renders with `amaru-treasury.contingency.account` at every `body.inputs.*.resolved.address` row of the `Input` bucket, AND at the un-collapsed `outputs.0.address` site. The two address-rendering paths produce string-identical output for the same payment credential.
- **SC-002**: The full pre-feature `Cardano.Tx.InspectSpec` suite passes against the post-feature engine with zero golden recaptures. Every checked-in golden under `test/fixtures/` whose source YAML does NOT pin an identifier path in `required:` renders byte-identically.
- **SC-003**: The symmetric `kind: script` fix is verifiable: a synthetic test fixture with a script-hash path pinned in `required:` and a matching `kind: script` rename rule renders the rename name at the bucket's required-slot row.
- **SC-004**: `docs/rewriting-rules.md` does NOT contain the substrings *"Pattern — keep payment addresses out of `required:`"*, *"keep payment addresses out of"*, or any equivalent operator-visible caveat about `required:` × rename interaction. (Grep-verifiable.)
- **SC-005**: The cross-bucket grouping behaviour is correct: a fixture with two inputs whose payment credentials match the same `match: payment` rule but whose stake credentials differ produces a SINGLE index-range row in the bucket. Specifically: the rendered output for `inputs.Input.resolved.address.0,1 → "amaru-treasury.contingency.account"`, NOT two separate rows.
- **SC-006**: The cross-stage property test (FR-007) catches a regression: if a future engine refactor reintroduces the typed-identity loss, the new `it` block fails with a string-mismatch on the renamed-address row. Independently of the goldens.
- **SC-007**: No exported symbol in `Cardano.Tx.Diff` or `Cardano.Tx.Rewrite` is renamed, removed, or breaking-changed by this feature. `cabal check` continues to pass with no Hackage-API violations.

## Assumptions

- The "contingency-disburse" fixture referenced in User Story 1 is the live ruleset under development at `lambdasistemi/amaru-treasury-tx#170`; the fixture itself does NOT need to land in `cardano-tx-tools` for this feature. A representative synthetic CBOR fixture (the existing `swap-cancel-issue-8` body augmented with an `Input` collapse rule + a matching rename rule) is sufficient to exercise the engine fix at the goldens level. The contingency-disburse fixture is the load-bearing real-world story but is acquired and verified out-of-tree by the operator.
- The symmetric `kind: script` defect is real (engine inspection of `collectValueRequiredLeaves` + `lookupValueAtPath` confirms the same `Aeson.Value` projection strips both address and script typed identity). The spec commits to fixing both axes as one engineering change; the plan will determine the exact implementation shape.
- The cross-bucket grouping change (FR-005) is a load-bearing edge case the issue does NOT explicitly call out but the engine demands. If grouping continued to compare raw `Aeson.Value`s, addresses that share a payment credential but differ in stake credential would render as adjacent same-name rows — operator-confusing. The spec promotes this to FR-005 / SC-005 so the implementation cannot accidentally regress on it.
- The fix is at the engine layer (`Cardano.Tx.Diff` internals) only. No change to the YAML grammar. No change to `Cardano.Tx.Rewrite`'s public API. No new rule kind, no new `match:` value, no new field on `CollapseRule` or `RenameRule`.

## Out of Scope

- Performance work on the recursive walker (carried over from issue #43's Out-of-Scope).
- The interactions called out as separate tickets in #43: #39 (datum-bytes rename inside `OpenValue` subtrees), #40 (nested rules + `raw: omit`).
- Adding a new `kind:` for vkey hashes or any other identifier family — separate tickets, one per family.
- Renaming inside `OpenValue` / datum subtrees — issue #39's axis.
- Renaming or refactoring the existing `CollapseRule` / `CollapseRules` / `RenameRule` / `RenameRules` types. Additive at the public-API level only.
- Operator-facing flags or subcommands to control the typed-identity preservation — the fix is unconditional, not opt-in.
- The predicate / invariant DSL (#15).

## Command Recovery

Per the resolve-ticket command-recovery rule, this feature ships **no new operator command**: the operator surface is the existing `tx-inspect` CLI from issue #32 (and, by the cross-tool symmetry of the rewriting-rules pipeline, the existing `tx-diff` CLI). The bug is observed by running `tx-inspect <tx> --rules <yaml>` on the contingency-disburse fixture; the fix is observed by running the same command and seeing the rename name at every address site.

The operator command remains:

```bash
tx-inspect <tx-input> --rules <path> [--n2c-socket-path <socket> | --web2-… <args>]
```

And the smoke proof for the same path remains `just smoke-inspect`, exercising the same `tx-inspect` executable end-to-end through the same `main`. No new test-only renderer entry point is introduced; the golden tests in FR-007 / FR-008 / FR-009 drive the production command path via `renderConwayTxHuman` (the shared render entry point shipped by `specs/032-tx-inspect`).

# Implementation Plan: collapse engine — nested rules + `raw: omit`

**Branch**: `040-collapse-nested-raw-omit` | **Date**: 2026-05-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/040-collapse-nested-raw-omit/spec.md`

## Summary

Extend the stage-1 collapse engine with two strictly-additive primitives:

1. **Nested collapse rules** — `CollapseRule` gains `collapseRuleNested :: [CollapseRule]` (default `[]`). When a parent rule matches an item at an array site, the engine recurses with each child rule, interpreting the child's `at:` as **relative** to the matched item's base path (`<parent at> </> <idx>`).
2. **`raw: omit` mode** — `CollapseRawView` gains `CollapseRawOmit`. YAML accepts `views.raw: omit`. When this mode is active at an array site, items matched by a collapse rule do **not** render below the bucket at all; unmatched siblings continue to render verbatim.

Both primitives target the same user experience (US1): a real Amaru treasury swap renders as a bucket header + variable-slot rows, with the per-output noise gone.

The work lands as **five bisect-safe vertical slices** (S1–S4 subagent-driven + S5 orchestrator final). Order is "primitive-by-primitive, then integration":

- **S1** — Nested rules end-to-end (type field + parser + engine recursion + LoadSpec + ApplySpec, including the depth-3 synthetic fixture from US5). Existing goldens unchanged.
- **S2** — `raw: omit` end-to-end (constructor + parser + engine omit case + LoadSpec + ApplySpec + a flat-rule synthetic `omit` golden under `swap-cancel-issue-8`). Existing `show`/`hide` goldens unchanged.
- **S3** — Integration: update `rules/amaru-treasury.yaml` to use both new features, recapture the Amaru both-stages golden (`swap-1.both.txt`, `swap-1.both.resolved.txt`, and the tx-diff cross-check). SC-001 line-count reduction observed.
- **S4** — Docs: extend `docs/rewriting-rules.md` with "Nested rules" + "`raw: omit`" sections, update the worked example, update the payment-address pattern note.
- **S5** — Orchestrator: drop `gate.sh`, mark PR ready.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (existing pin, constitution Operational Constraints).
**Primary Dependencies**: No change. The engine edits live in `src/Cardano/Tx/Diff.hs`, which already pulls `aeson`, `yaml`, `cardano-ledger-*`, `text`, `bytestring`. `Cardano.Tx.Rewrite` is unchanged (it only re-exports the affected types).
**Storage**: None at runtime. Test fixtures on disk under `test/fixtures/amaru-treasury-swap/` (existing) and `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/` (existing).
**Testing**: existing `unit-tests` test-suite. New `it` blocks added to `Cardano.Tx.Rewrite.LoadSpec` (parser), `Cardano.Tx.Rewrite.ApplySpec` (engine semantics with synthetic depth-3 fixture), and `Cardano.Tx.InspectSpec` (recaptured Amaru golden + new `omit`-on-flat-rule golden under `swap-cancel-issue-8`). Per-slice live-boundary smoke in `gate.sh` via the existing `just smoke-inspect` recipe.
**Target Platform**: Linux/Darwin via `haskell.nix`.
**Project Type**: Haskell library + five shipped executables (unchanged — no new CLI). The new YAML keys feed the existing `tx-inspect` (and, by FR-015 cross-tool symmetry, the existing `tx-diff`).
**Performance Goals**: "No measurable regression on the existing Amaru fixture". The depth-3 synthetic fixture in `ApplySpec` is small (≤ 10 items per array site), so any recursion blow-up shows up trivially. No profiling-driven optimisation is required (Out-of-Scope).
**Constraints**: strictly additive at every existing public surface — `collapseRuleNested` is the only new field on `CollapseRule`; `CollapseRawOmit` is the only new constructor on `CollapseRawView`; the parser remains additive (an absent `nested:` key parses to `[]`, an absent `views.raw:` parses to `show`); the engine's existing `show` / `hide` semantics are unchanged for inputs that do not use the new features. Every existing call site that constructs `CollapseRule` via record syntax compiles unchanged (we use record-update or named fields).
**Scale/Scope**: ~30 LOC in `src/Cardano/Tx/Diff.hs` (type field, FromJSON, engine), ~150 LOC across the three test specs, ~20 LOC in `rules/amaru-treasury.yaml`, ~80 LOC of new sections + worked-example update in `docs/rewriting-rules.md`. Net diff probably 400–600 LOC including the recaptured Amaru goldens (smaller because the bucket-only render is shorter than the pre-change render).

## Constitution Check

The seven core principles apply. Walked one by one:

- **I. One-Way Dependency On Node-Clients** — No new `cardano-node-clients` import. The change lives in `src/Cardano/Tx/Diff.hs` and test files only. **Pass.**
- **II. Module Namespace Discipline** — No new module. All edits to existing `Cardano.Tx.*` modules. **Pass.**
- **III. Conway-Only Era** — Unchanged. **Pass.**
- **IV. Hackage-Ready Quality** — Every new public surface gains Haddock:
  - `collapseRuleNested` field carries Haddock describing the "relative `at:`" semantics, the empty-list default, and the depth-unboundedness.
  - `CollapseRawOmit` constructor carries Haddock distinguishing it from `CollapseRawHide`.
  - The parser's new acceptance for `nested:` / `views.raw: omit` is documented in the existing module-level rewriting-rules grammar docstring (or in the `Cardano.Tx.Rewrite` re-export module — to be decided per slice).
  `cabal check` continues to pass. **Pass.**
- **V. Strict Warnings, No `-Werror` Escape Hatches** — The new field on `CollapseRule` will trigger `-Wmissing-fields` if any internal site constructs the record positionally. **Open question P1** (see below): are there positional-construction sites today? Mitigation: switch positional sites to named-field construction in the same commit, or supply a Smart Constructor `mkCollapseRule` if record-syntax churn turns out to be large. Same applies for any pattern-match that destructures `CollapseRule` positionally. **Pass with P1.**
- **VI. Default-Offline Semantics** — Unchanged. **Pass.**
- **VII. TDD With Vertical Bisect-Safe Commits** — Five slices below are each RED+GREEN-folded; each commit on the branch compiles, the full unit suite passes, and `gate.sh` (build + unit + smoke-inspect + lint) is green. **Pass.**

**Operational Constraints**:

- GHC 9.12.3 via `haskell.nix` — unchanged.
- `nix flake check --no-eval-cache` local gate — extended only by the existing smoke recipe (no new recipe needed; `just smoke-inspect` already exercises the executable end-to-end and the recaptured Amaru golden assertion picks up any regression).
- Lint stack (fourmolu, hlint, cabal-fmt) — already in `gate.sh`.
- Released binaries that perform HTTPS bundle a CA store — N/A; this feature touches no network code.

**Resolver Architecture** — Untouched. The collapse engine consumes whichever resolver chain `tx-inspect` was already invoked with.

**No exceptions tracked.** Complexity Tracking table at the bottom is empty.

## Project Structure

### Documentation (this feature)

```text
specs/040-collapse-nested-raw-omit/
|-- plan.md                         # this file
|-- spec.md                         # 5 user stories, FR-001..FR-015
|-- research.md                     # Phase 0 output (research decisions)
|-- data-model.md                   # Phase 1 output (collapseRuleNested, CollapseRawOmit)
|-- quickstart.md                   # Phase 1 output (operator-facing quick path for the two new keys)
|-- contracts/
|   `-- rewriting-rules-extensions.md  # Phase 1 output (delta to docs/rewriting-rules.md)
|-- checklists/
|   `-- requirements.md             # spec quality checklist
`-- tasks.md                        # /speckit.tasks output (next phase)
```

### Source code (repository root)

```text
src/Cardano/Tx/
  Diff.hs                           # EDITED — additive:
                                    #   * `data CollapseRule` gains `collapseRuleNested ::
                                    #     [CollapseRule]`. Existing fields unchanged in name/type.
                                    #   * `data CollapseRawView` gains `CollapseRawOmit`.
                                    #   * `instance FromJSON CollapseRule` accepts optional
                                    #     `nested:` key (defaults to []).
                                    #   * `instance FromJSON CollapseRawView` accepts "omit"
                                    #     alongside "show" / "hide"; error message updated to
                                    #     enumerate all three.
                                    #   * `collectValueArray` engine:
                                    #     - For each matched item under a parent rule, recurse
                                    #       into the matched item's subtree with the original
                                    #       top-level rules PLUS the parent's `collapseRuleNested`
                                    #       rewritten to absolute `at:` paths under
                                    #       `(basePath </> show idx)`.
                                    #     - New `case (hasView, ..., CollapseRawOmit) -> withViews`
                                    #       branch in the trailing `case` — items matched by ANY
                                    #       rule are suppressed below the bucket. Items NOT matched
                                    #       still walk via `walkRaw` (preserving the spec's
                                    #       "unmatched siblings render verbatim" edge case).
                                    #   * Haddock on every new field / constructor + a short
                                    #     "see also" pointing at the grammar doc.
  Rewrite.hs                        # UNCHANGED — re-exports `CollapseRule`, `CollapseRules`,
                                    #             `CollapseRawView` which automatically pick up
                                    #             the new field / constructor.
app/tx-inspect/Main.hs              # UNCHANGED — the new YAML keys feed through the existing
                                    #             parser + HumanRenderOptions plumbing.
test/Cardano/Tx/
  Rewrite/
    LoadSpec.hs                     # EDITED — new `it`s for:
                                    #   - nested parsing: with / without / deeply-nested fixtures
                                    #   - `views.raw: omit` accepted; unknown raw-view error
                                    #     message lists all three accepted values
                                    #   - legacy compat: every existing rules YAML fixture
                                    #     parses byte-equal to the pre-change result
    ApplySpec.hs                    # EDITED — new `it`s for:
                                    #   - matched-item recursion (parent matches → child fires
                                    #     on the matched item's subtree)
                                    #   - non-matched item (parent doesn't match → child silent)
                                    #   - depth-3 synthetic fixture (US5)
                                    #   - `omit` matched-item suppression
                                    #   - `omit` unmatched siblings render verbatim
                                    #   - `omit` with empty rules is no-op
  InspectSpec.hs                    # EDITED — two new fixture-driven `describe` blocks:
                                    #   1) S2: `swap-cancel-issue-8` with a small
                                    #      `collapse-only.omit.yaml` and a new
                                    #      `inspect.collapse-only.omit.txt` golden — proves
                                    #      `omit` on a flat rule shape.
                                    #   2) S3: the recaptured Amaru both-stages golden
                                    #      (`swap-1.both.txt` + `swap-1.both.resolved.txt`)
                                    #      with the updated `rules/amaru-treasury.yaml`.
                                    # The four pre-existing #032 InspectSpec describes are
                                    # NOT touched and continue to assert byte-equality on
                                    # their existing goldens (US2 regression contract).
test/fixtures/mainnet-txbuild/swap-cancel-issue-8/
  collapse-only.omit.yaml           # NEW — copy of existing collapse-only.yaml with
                                    #       `views.raw: omit` added. S2 only.
  inspect.collapse-only.omit.txt    # NEW — golden for the `omit` variant. S2 only.
test/fixtures/amaru-treasury-swap/golden/
  swap-1.both.txt                   # RECAPTURED (S3) — bucket-only view with the new
                                    #                  ScopeOwners nested rule + omit.
  swap-1.both.resolved.txt          # RECAPTURED (S3) — same.
rules/
  amaru-treasury.yaml               # EDITED (S3) — add `nested: [{ name: "ScopeOwners", at:
                                    #               datum.fields.1.fields.0, match: { required:
                                    #               [constructor, fields.0] } }]` under the
                                    #               SwapOrder rule; flip `views.raw` from
                                    #               `hide` to `omit`; inline comment block
                                    #               explaining the new shape.
docs/rewriting-rules.md             # EDITED (S4) — new sections:
                                    #   * "Nested rules" — grammar, relative-`at:` semantics,
                                    #     depth, worked example (SwapOrder + ScopeOwners).
                                    #   * "`raw: omit`" — semantics, matched vs unmatched item
                                    #     distinction, no-op when no rules match.
                                    #   * Updated "Pattern — keep payment addresses out of
                                    #     `required:`" — note that nested rules give an
                                    #     alternative path to collapsing identifier-bearing
                                    #     subtrees without bypassing the rename layer.
                                    #   * Worked example at the end updated to reflect the
                                    #     new `rules/amaru-treasury.yaml` shape (nested + omit).
gate.sh                             # UNCHANGED — bootstrapped at branch creation and dropped
                                    #             in S5; the existing recipe set
                                    #             (build + unit + smoke-inspect + lint)
                                    #             is sufficient for every slice.
```

**Structure Decision**: keep the single-library-plus-N-executables layout. No new module is introduced. The engine edits live in `Cardano.Tx.Diff` because that is where the collapse engine and the `CollapseRule` / `CollapseRawView` types live; introducing a new sibling module purely for the recursion helper would shatter cohesion without buying anything.

## Orchestrator vs Subagent Ownership

| Asset | Owner |
|---|---|
| `spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/*`, `tasks.md`, `checklists/*` | **Orchestrator** |
| `gate.sh` (initial create; final drop) | **Orchestrator** |
| `src/Cardano/Tx/Diff.hs` — type field, FromJSON, engine recursion | **Subagent of S1** |
| `src/Cardano/Tx/Diff.hs` — `CollapseRawOmit` constructor, FromJSON, engine omit case | **Subagent of S2** |
| `test/Cardano/Tx/Rewrite/LoadSpec.hs` (nested + omit parsing + legacy-compat) | **Subagent of S1 and S2** (each adds its own `it` blocks) |
| `test/Cardano/Tx/Rewrite/ApplySpec.hs` (nested recursion + depth-3 + omit semantics) | **Subagent of S1 and S2** |
| `test/Cardano/Tx/InspectSpec.hs` — new `omit`-on-flat-rule golden | **Subagent of S2** |
| `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/collapse-only.omit.yaml` + `inspect.collapse-only.omit.txt` | **Subagent of S2** |
| `test/Cardano/Tx/InspectSpec.hs` — recaptured Amaru both-stages golden assertion | **Subagent of S3** |
| `test/fixtures/amaru-treasury-swap/golden/swap-1.both*.txt` (recapture) | **Subagent of S3** |
| `rules/amaru-treasury.yaml` (nested + omit edit) | **Subagent of S3** |
| `docs/rewriting-rules.md` (nested + omit sections, worked-example update) | **Subagent of S4** |
| PR body, issue closing, post-merge cleanup | **Orchestrator** |

## Vertical Commit Slices

Five implementation slices in dependency order. Each = one subagent run = one bisect-safe commit. S5 = orchestrator final drop of `gate.sh`.

### S1 — Nested collapse rules (type field + parser + engine recursion + tests)

**Subject**: `feat(040): add nested collapse rules`

**Acceptance**: A `CollapseRule` can carry `nested: [CollapseRule]` in the YAML; when the parent matches an item, each child rule fires on the matched item's subtree with `at:` interpreted relative to that subtree. Arbitrary depth supported. Every existing rules YAML and every existing golden remains byte-identical (no document in the test corpus uses `nested:` until S3).

**Files (subagent-owned)**:

- `src/Cardano/Tx/Diff.hs`:
  - Add `collapseRuleNested :: [CollapseRule]` field to `CollapseRule`. Use record syntax for every internal construction site (sweep ahead of the field addition if any positional construction sites exist — see open question P1).
  - Extend `instance FromJSON CollapseRule` to read optional `nested:` key (`.: ?"nested" .!= []`).
  - In `collectValueArray`: after `insertValueCollapseView` produces `withViews`, recurse into each matched item's subtree (`walkRaw` and `walkPruned` both already iterate items; extend their inner lambdas to call a helper that, when the item matched any rule with non-empty `collapseRuleNested`, rewrites those child rules to absolute `at:` paths under the item's base and merges them into the `Maybe CollapseRules` passed to the recursive `collectValueTrie[Pruned]` call).
  - Haddock on `collapseRuleNested` describing the relative-`at:` semantics + depth.
- `test/Cardano/Tx/Rewrite/LoadSpec.hs`:
  - `it "parses CollapseRule with empty nested: list"`.
  - `it "parses CollapseRule with one nested child"`.
  - `it "parses CollapseRule with deeply nested children (depth 3)"`.
  - `it "defaults collapseRuleNested to [] when nested: key is absent (legacy compat)"`.
  - `it "rejects nested: that is not a YAML list"`.
- `test/Cardano/Tx/Rewrite/ApplySpec.hs`:
  - `it "fires nested child rule on each matched item's subtree"` — synthetic `ConwayDiffValue` fixture: parent rule at `body.outputs`, child rule at `datum.fields`; assert the child's bucket header appears in the rendered output for each matched item.
  - `it "does not fire nested child on items the parent did not match"` — same fixture, plus a sibling item missing the parent's `required:` leaves.
  - `it "applies depth-3 rule chain"` — synthetic fixture with parent → child → grandchild; assert all three bucket headers appear.
- `gate.sh`: unchanged. The existing recipe (build + unit + `just smoke-inspect` + lint) is sufficient — `smoke-inspect` already exercises `tx-inspect` end-to-end and `unit` picks up the new ApplySpec / LoadSpec `it`s.

**RED (subagent observes failing before implementation)**:

1. The new LoadSpec `it "parses CollapseRule with one nested child"` is added with the expected `CollapseRule { …, collapseRuleNested = [child] }` value; it fails to compile until the `collapseRuleNested` field exists.
2. The new ApplySpec `it "fires nested child rule on each matched item's subtree"` is added; it fails until the engine recursion is wired.

**GREEN**:

- `nix develop --quiet -c just build` passes.
- `nix develop --quiet -c just unit` passes (full suite, including the four pre-existing #032 InspectSpec describes — US2 regression contract).
- `nix develop --quiet -c just smoke-inspect` passes (existing fixture has no `nested:` so its render is byte-stable).
- `./gate.sh` passes.

**Live-boundary diagnostic** (per workflow): the engine recursion is purely a code-level change to a pure function; no live boundary is crossed that the unit suite cannot reach. `gate.sh smoke-inspect` runs the binary end-to-end as a backstop and asserts the unchanged-golden property. No new boundary smoke is required.

**`tasks.md` IDs (forecast)**: T001–T005.

---

### S2 — `raw: omit` mode (constructor + parser + engine + tests + flat-rule golden)

**Subject**: `feat(040): add CollapseRawOmit view mode`

**Acceptance**: A rewriting-rules YAML can set `views.raw: omit`; under this mode, items matched by ANY collapse rule at an array site are not rendered below the bucket. Unmatched siblings continue to render verbatim. Existing `show` / `hide` semantics unchanged.

**Files (subagent-owned)**:

- `src/Cardano/Tx/Diff.hs`:
  - Add `CollapseRawOmit` constructor to `CollapseRawView`. Haddock distinguishing it from `CollapseRawHide`.
  - Extend `instance FromJSON CollapseRawView` to accept `"omit"`; update the error path to enumerate `show | hide | omit`.
  - In `collectValueArray`'s trailing `case`: add `(True, CollapseRawOmit) -> withViews` — when at least one rule matched and the view is `omit`, return the trie with the bucket views inserted but **no** per-item walk (neither `walkRaw` nor `walkPruned`). For unmatched-item sites (`hasView = False`), the existing `walkRaw path trie` fall-through still fires, so unmatched siblings render verbatim — this is the spec's explicit edge case.
- `test/Cardano/Tx/Rewrite/LoadSpec.hs`:
  - `it "parses views.raw: omit"`.
  - `it "rejects views.raw: <other> with an error listing show | hide | omit"`.
- `test/Cardano/Tx/Rewrite/ApplySpec.hs`:
  - `it "suppresses per-item subtree for matched items under omit"` — synthetic fixture.
  - `it "leaves unmatched siblings verbatim under omit"` — synthetic fixture mixing matched and unmatched items.
  - `it "omit with empty collapse rules is a no-op"` — assert render under `omit` + empty rules equals render under `show` + empty rules.
- `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/collapse-only.omit.yaml`: copy of the existing `collapse-only.yaml` with `views: { raw: omit }` added.
- `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/inspect.collapse-only.omit.txt`: new golden. Subagent captures on first run after the engine change is in place; second run asserts byte-equality.
- `test/Cardano/Tx/InspectSpec.hs`:
  - New describe block: `"Cardano.Tx.Diff.renderConwayTxHuman (slice S2 (040) collapse-only with omit)"`. Loads `collapse-only.omit.yaml`, runs the existing test harness, asserts equality against `inspect.collapse-only.omit.txt`.
  - The four pre-existing #032 InspectSpec describes are NOT touched (US2 regression contract).
- `gate.sh`: unchanged.

**RED**:

1. The new ApplySpec `it "suppresses per-item subtree for matched items under omit"` fails because the engine still walks per-item under `Hide`/`Show` (the only existing cases).
2. The new LoadSpec `it "parses views.raw: omit"` fails because the FromJSON instance rejects `"omit"`.
3. The new InspectSpec describe block fails (golden file not yet captured); after capture and rerun it passes — the same RED→GREEN observation pattern as the #032 Amaru goldens.

**GREEN**:

- `just build`, `just unit`, `just smoke-inspect`, `./gate.sh` all pass.
- The four pre-existing #032 InspectSpec describes still pass byte-identically (US2 regression contract for `show`/`hide`).

**Live-boundary diagnostic**: same as S1 — pure-function change; the existing `smoke-inspect` exercises the binary end-to-end.

**`tasks.md` IDs (forecast)**: T006–T010.

---

### S3 — Amaru rules update + Amaru both-stages golden recapture

**Subject**: `feat(040): collapse Amaru committee-owners list with nested rule + omit`

**Acceptance**: `rules/amaru-treasury.yaml` adds a `ScopeOwners` nested rule under `SwapOrder` covering the committee-owners list (at `datum.fields.1.fields.0` relative to each matched output), and sets `views.raw: omit`. The Amaru `swap-1.both.txt` and `swap-1.both.resolved.txt` goldens are recaptured to the bucket-only view. Line count for `body.outputs` is at least an order of magnitude shorter than the pre-change render (SC-001).

**Files (subagent-owned)**:

- `rules/amaru-treasury.yaml`:
  - Add `nested:` to the existing `SwapOrder` rule:
    ```yaml
    nested:
      - name: "ScopeOwners"
        at: datum.fields.1.fields.0
        match:
          required:
            - constructor
            - fields.0
    ```
  - Change `views.raw` from `hide` to `omit`.
  - Add inline comment block explaining the new shape (matches the existing comment style for the rename block).
- `test/fixtures/amaru-treasury-swap/golden/swap-1.both.txt`: recapture. Subagent captures from the first run of the InspectSpec describe block under the updated rules; orchestrator inspects the captured file in review (specifically: confirms the new render is ≤ 5% of the pre-change line count, the `ScopeOwners` bucket appears, and no per-output detail subtree remains).
- `test/fixtures/amaru-treasury-swap/golden/swap-1.both.resolved.txt`: recapture, same pattern.
- `test/Cardano/Tx/InspectSpec.hs`: no new describe block — the existing S4 describe block for the Amaru both-stages golden (shipped by #032) continues to assert against the **recaptured** golden files. The `it` block is unchanged; only the on-disk golden bytes change. (The orchestrator confirms this is enough by re-reading `InspectSpec.hs`'s existing S4 describe block before dispatching the subagent.)
- WIP.md entry by the subagent (per the resolve-ticket live-tail invariant): the line counts pre-change and post-change for `swap-1.both.txt` must be recorded so the orchestrator can verify SC-001 at review time.
- `gate.sh`: unchanged.

**RED**:

1. With the updated YAML in place but before the goldens are recaptured, the existing `it` block for the Amaru both-stages golden fails (rendered output no longer equals the pre-change golden bytes).
2. After capture, rerun observes GREEN.

**GREEN**:

- `just build`, `just unit`, `just smoke-inspect`, `./gate.sh` all pass.
- The recaptured `swap-1.both.txt` shows the bucket-only view for `body.outputs` (≤ 5% of pre-change line count, per SC-001).
- The cross-tool symmetry property (FR-015) is preserved automatically: the existing `tx-diff` cross-check golden (`specs/032-tx-inspect`-era describe block) recaptures the same way because both sides of the diff feed through the same engine.

**Live-boundary diagnostic**: yes — the render bytes are the diagnostic. The recaptured golden is the live-boundary proof at fixture level; the orchestrator's "line count ≤ 5%" check in WIP.md is the operator-visible artifact.

**`tasks.md` IDs (forecast)**: T011–T013.

---

### S4 — Documentation: `docs/rewriting-rules.md`

**Subject**: `docs(040): document nested collapse rules and raw: omit`

**Acceptance**: `docs/rewriting-rules.md` carries two new sections ("Nested rules", "`raw: omit`"), an updated "Pattern — keep payment addresses out of `required:`" note, and a refreshed worked-example block at the end (the new `rules/amaru-treasury.yaml` shape). `mkdocs build --strict` passes.

**Files (subagent-owned)**:

- `docs/rewriting-rules.md`:
  - Insert "Nested rules" section after the `CollapseRule` section. Covers: `nested:` YAML grammar, relative-`at:` semantics, depth, the worked SwapOrder + ScopeOwners example.
  - Insert "`raw: omit`" section after the "Match semantics" section (or wherever the existing `raw:` discussion sits — subagent verifies the actual structure first and surfaces in WIP.md before editing). Covers: omit semantics, the matched vs unmatched item distinction, the no-op when no rules match.
  - Update the existing "Pattern — keep payment addresses out of `required:`" section: add a paragraph noting that nested rules give an alternative path to collapsing identifier-bearing subtrees without bypassing rename, since nested rules — like the parent rule — leave un-`required:`ed leaves available to the rename pass.
  - Update the worked-example block at the bottom to reflect the new `rules/amaru-treasury.yaml` shape (nested + omit). Add a one-line note under the example explaining the line-count reduction observed in S3.
  - **Subagent's first task in S4 is to confirm the current section layout** of `docs/rewriting-rules.md` (it may have shifted since #032 shipped). Confirmation via `grep -n '^## ' docs/rewriting-rules.md`. Surface in WIP.md before editing.
- No other files. `mkdocs.yml` does not need editing (the file is already in nav).
- `gate.sh`: unchanged.

**RED**: `nix develop --quiet -c just build-docs` (mkdocs strict mode) is the gate. It fails before the new sections are inserted if a cross-reference is broken (e.g. a new heading link not yet resolving); after the sections are inserted it passes.

**GREEN**: `just build-docs` passes; `just ci` passes; `./gate.sh` passes.

**Live-boundary diagnostic**: no — docs build is the boundary. `mkdocs build --strict` is the gate.

**`tasks.md` IDs (forecast)**: T014–T015.

---

### S5 — Drop `gate.sh` (orchestrator chore)

**Subject**: `chore(040): drop gate.sh (ready for review)`

**Owner**: orchestrator. After finalization audit passes and every `[ ]` in `tasks.md` is `[X] T###`.

## Proof Strategy Summary

| Slice | RED | GREEN | Live-boundary smoke in `gate.sh`? |
|---|---|---|---|
| S1 | new LoadSpec / ApplySpec `it`s + depth-3 synthetic fixture fail until field + parser + engine recursion are wired | full unit + smoke pass; pre-existing #032 goldens unchanged | yes — existing `smoke-inspect` |
| S2 | new LoadSpec / ApplySpec `it`s + `omit`-on-flat-rule golden fail until constructor + parser + engine omit case are wired | full unit + smoke pass; pre-existing #032 `show`/`hide` goldens unchanged | yes — existing `smoke-inspect` |
| S3 | existing Amaru both-stages `it` fails (golden bytes no longer match) until goldens are recaptured | full unit + smoke pass; recaptured golden shows ≤ 5% of pre-change line count | yes — existing `smoke-inspect` |
| S4 | `mkdocs build --strict` fails on broken cross-refs | `just build-docs` passes | no — docs build is the gate |
| S5 | n/a (`gate.sh` removal) | finalization audit passes; `gh pr ready` | n/a |

## gate.sh evolution

`gate.sh` is created at branch bootstrap with the canonical recipe (build + unit + smoke-inspect + lint) and is **NOT extended per slice** — the existing recipe set is sufficient for every slice because:

- S1 / S2 engine changes are pure-function code reachable from `unit` + `smoke-inspect`.
- S3 golden recapture is detected by `unit` (the existing Amaru describe block).
- S4 docs are not exercised by `gate.sh` (mkdocs is the docs gate, run manually before the docs commit; `gate.sh` does not invoke it because adding it would slow every slice's gate run by ~30s for the docs build, which only changes once).

S5 deletes `gate.sh`. This is a deliberate deviation from #032, which extended `gate.sh` per slice — that pattern was load-bearing for #032 because each slice added a new executable / fixture surface; for #040, every slice exercises the same single surface.

## Open Questions

The spec-level decisions are resolved (see `spec.md`'s explicit Out-of-Scope). The following are **planning-level open questions** the subagent for the named slice surfaces in `WIP.md` and the orchestrator answers before that slice's GREEN observation:

- **P1 (S1, resolved at plan time)**: All current `CollapseRule` construction sites use **named-field syntax** (verified via `grep -A4 'CollapseRule$' src/ test/`). Nine sites need a `, collapseRuleNested = []` line added in the same S1 commit — no positional-to-record sweep is required. The sites are:
  - `src/Cardano/Tx/Diff.hs:664` (the FromJSON instance — supplies it via `.: ?"nested" .!= []` rather than hard-coding `[]`).
  - `test/Cardano/Tx/Diff/CoreSpec.hs:383, 409, 477, 492, 516, 544` (six sites in the existing `Cardano.Tx.Diff.Core` tests — they predate the rename layer).
  - `test/Cardano/Tx/Rewrite/ApplySpec.hs:145, 317` (two sites in the existing collapse-application tests).
  All nine fields land in S1 alongside the new field declaration. The subagent's RED step still observes the new LoadSpec / ApplySpec `it`s failing for the right reason (semantic, not "missing field warning"). Mitigation against a missed site: `nix develop --quiet -c just build` (S1 GREEN) emits an unambiguous compile error per missed site.
- **P2 (S3, advisory)**: Is the committee-owners path actually `datum.fields.1.fields.0` for the current Amaru `swap-1` fixture, or has the underlying datum schema shifted between #32's fixture acquisition and this slice's edit? Subagent verifies by reading `swap-1.both.resolved.txt` (the pre-change golden) and grepping for the 4-element key-hash list; surfaces the actual path in WIP.md. If different, the subagent uses the actual path and notes the deviation in the commit body.
- **P3 (S4, advisory)**: Does `docs/rewriting-rules.md` currently have a single `## raw:` section that the new omit doc extends, or is `raw:` documented inline inside a "Match semantics" / "Document shape" section? Subagent confirms by `grep -n '^##\? *raw' docs/rewriting-rules.md` and reports in WIP.md before editing. Default: insert a top-level `## Raw-view modes` section if `raw:` is currently inline.

Each is captured as the first step of its slice's subagent brief.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *(none)* | — | — |

The plan introduces no new module, no new sublibrary, no new direct dependency, no new resolver kind, no new test framework, no schema migration, and no public-API breaking change. Every existing call site that constructs `CollapseRule` via record syntax compiles unchanged once the open question P1 sweep (if any) is complete.

# Tasks: tx-inspect — shared-substrate transaction renderer with two-stage rewriting

**Input**: Design documents from `/specs/032-tx-inspect/`
**Prerequisites**: [plan.md](./plan.md) (required), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

## Tests

Tests are **required** for this feature. The spec mandates three golden tests (FR-012, FR-013, FR-014) and the live-boundary smoke (FR-016 + the command-recovery rule). Each implementation slice ships a RED proof (failing test/smoke) and a GREEN observation (passing) folded into one bisect-safe commit.

## Format

`[ID] [P?] [Story?] Description with absolute path`

- **[P]**: parallel-safe **within the same slice's subagent run** (touches a different file; no dependency on an earlier task in the same slice).
- **[Story]**: `[US1]`–`[US4]` per the user stories in [spec.md](./spec.md). Cross-cutting setup / foundational / chore tasks omit the story label.
- Paths are absolute under `/code/cardano-tx-tools-issue-32/`.

## Path conventions

- Library + 5 executables, layout pinned in [plan.md § Project Structure](./plan.md). `src/Cardano/Tx/`, `app/<exe>/`, `test/Cardano/Tx/`, `test/fixtures/`, `rules/`, `docs/`.

## Slice ↔ commit mapping

Every implementation slice (S1–S6) is **one bisect-safe commit produced by one subagent run** (per [plan.md § Vertical Commit Slices](./plan.md)). Subagent briefs live in plan.md; this file is the actionable task checklist the subagent ticks off. RED-before-GREEN is required within every slice — if RED and GREEN are listed as separate tasks below, the slice's brief states they fold into the single commit (see plan.md per-slice "RED" / "GREEN" entries).

---

## Phase 1: Setup (already complete)

Carried by the bootstrap commits ahead of this tasks file. Listed for traceability.

- [X] T000 Worktree + branch `032-tx-inspect` + draft PR #33 created (carrier commits: `d50e8f5`, `2b3c6d1`, `8a08079`, `86df888`).
- [X] T000a `gate.sh` initial commit landed (carrier: `d50e8f5`).

---

## Phase 2: Foundational — S1 (slice S1, one subagent run, one commit)

**Goal**: Land the `tx-inspect` executable with the bare render path (empty rules → verbatim render). Extract the per-side renderer from `tx-diff` and prove tx-diff output is byte-identical afterwards. Introduce `Cardano.Tx.Rewrite` (types + parser only; application logic lands in later slices).

**Independent Test**: `cabal run -v0 -O0 tx-inspect -- --rules /tmp/empty.yaml test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex` exits 0; output matches the captured baseline golden. tx-diff goldens unchanged.

**Subagent brief**: [plan.md § S1](./plan.md#s1--tx-inspect-baseline-bare-executable--render-core-extraction)

**⚠️ Subsequent slices depend on S1 — do not start S2/S3/S4 until S1's commit is reviewed and stamped.**

### RED (subagent observes failing first)

- [X] T001 (commit: 596d064) [P] Add `gate.sh smoke-inspect` line (the new just recipe is invoked by gate.sh — fails because `exe:tx-inspect` does not exist yet). Edit `/code/cardano-tx-tools-issue-32/gate.sh`.
- [X] T002 (commit: 596d064) [P] Add `Cardano.Tx.Rewrite.LoadSpec` cases at `/code/cardano-tx-tools-issue-32/test/Cardano/Tx/Rewrite/LoadSpec.hs`. RED = module `Cardano.Tx.Rewrite` does not exist. Cases:
    - **(a) legacy compatibility**: existing collapse-only `{ version: 1, collapse: [...] }` document round-trips through `parseRewriteRulesYaml` to the same `CollapseRules` `parseCollapseRulesYaml` produces.
    - **(b) rename parsing**: each `RenameRule` variant parses correctly — `kind: address` with `match: full`, `kind: address` with `match: payment` (and default), `kind: script`. Parse-error cases per [contracts/rules-yaml-grammar.md § Parse errors](./contracts/rules-yaml-grammar.md) (invalid bech32, wrong-length hex, missing `name`, unknown `kind`, invalid `match`, wrong `version`).
    - **(c) stage-order invariance (SC-004)**: a document with `rename:` before `collapse:` parses to a `RewriteRules` value equal (by `(==)`) to the same document with the keys in reverse order.
    - **(d) empty document**: `{}` parses to `defaultRewriteRules`.

### GREEN (implementation, one commit)

- [X] T003 (commit: 596d064) Implement `/code/cardano-tx-tools-issue-32/src/Cardano/Tx/Rewrite.hs` per [data-model.md](./data-model.md): `RewriteRules`, `RenameRule(s)`, `parseRewriteRulesYaml`, Haddock. No application logic (no `applyRewriteRules` yet; types + parser only).
- [X] T004 (commit: 596d064) Add two new exported functions to `/code/cardano-tx-tools-issue-32/src/Cardano/Tx/Diff.hs` (per the planning-phase correction in [research.md R1](./research.md#r1-renderer-extraction-a-new-top-level-entry-sharing-the-projection--render-primitives)):
    - `renderConwayTxHuman :: HumanRenderOptions -> TxDiffOptions -> ConwayTx -> Text` — the top-level entry tx-inspect's Main calls. Walks `conwayDiffProjection` into a `RenderTrie` reusing the existing internal `RenderTrie` / `renderForest` / `renderJsonValue` primitives. No diff comparison.
    - `renderOpenValueHuman :: OpenValue -> Text` and `renderOpenValueHumanWith :: HumanRenderOptions -> OpenValue -> Text` — primitives that render an `OpenValue` subtree directly. S3's rename layer will use them on datum subtrees.
  Add `humanRenameRules :: Maybe RenameRules` field to `HumanRenderOptions` with `Nothing` default in `defaultHumanRenderOptions`. Export the new render functions and `humanRenameRules`. **Do NOT touch `renderDiffNodeHuman[With]` / `renderDiffNodeTree` / `renderDiffNodeLines`** — tx-diff output stays byte-identical trivially.
- [X] T005 (commit: 596d064) Create `/code/cardano-tx-tools-issue-32/app/tx-inspect/Main.hs` — `withCli` + `versionOption` (mirror `app/tx-diff/Main.hs`), `--rules PATH` optional flag, resolver flags lifted from `Cardano.Tx.Diff.Cli` (same `--n2c-socket-path`, `--web2-…` surface), call `parseRewriteRulesYaml` if `--rules`, set `humanCollapseRules` from `rewriteCollapse rr` (rename plumbing lands in S3), call `renderConwayTxHuman` on the decoded `ConwayTx`, exit 0.
- [X] T006 (commit: 596d064) [P] Edit `/code/cardano-tx-tools-issue-32/cardano-tx-tools.cabal`:
    - library: `exposed-modules += Cardano.Tx.Rewrite`.
    - new `executable tx-inspect` stanza mirroring `executable tx-diff` exactly (same `build-depends`, same warning flags, `werror` flag plumbing, `other-modules: Paths_cardano_tx_tools`).
    - unit-tests: `other-modules += Cardano.Tx.InspectSpec, Cardano.Tx.Rewrite.LoadSpec, StaticResolver`.
- [X] T007 (commit: 596d064) [P] Edit `/code/cardano-tx-tools-issue-32/flake.nix` — add `apps.tx-inspect` entry (mirror `apps.tx-diff`).
- [X] T008 (commit: 596d064) [P] Edit `/code/cardano-tx-tools-issue-32/justfile` — add `smoke-inspect` recipe (mirror `smoke-sign`); add `just smoke-inspect` invocation to `ci`.
- [X] T009 (commit: 596d064) Create `/code/cardano-tx-tools-issue-32/test/StaticResolver.hs` — loads `cardano-cli`-shaped `utxo.json` from a path, returns `Resolver { resolverName = "static", resolveInputs = \askedFor -> pure (Map.restrictKeys loaded askedFor) }`. Test-only, not in `exposed-modules`.
- [X] T010 (commit: 596d064) Create `/code/cardano-tx-tools-issue-32/test/Cardano/Tx/InspectSpec.hs` — baseline golden: decode `swap-cancel-issue-8/body.cbor.hex` into a `ConwayTx` via `decodeConwayTxInput`, resolve its inputs via `staticResolver` against `swap-cancel-issue-8/producer-txs/`, render via `renderConwayTxHuman defaultHumanRenderOptions defaultTxDiffOptions tx`, and assert output matches `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/inspect.verbatim.txt`. First run: capture + commit the file from observed output; second run: assert match. NOTE: the resolved UTxO map is fed into the renderer via `humanRenderOptions` or whatever channel `renderConwayTxHuman` exposes for resolved-inputs — confirm the channel matches what `renderDiffNodeHumanWith` uses today (likely `TxDiffOptions`'s `txDiffResolvedInputs`). The smoke at T011 uses a different golden (`inspect.verbatim.unresolved.txt`) because it runs the production CLI without a resolver flag.
- [X] T011 (commit: 596d064) Edit `/code/cardano-tx-tools-issue-32/gate.sh` per T001 — `smoke-inspect` recipe now passes. In the same recipe, add **three smoke assertions** covering FR-016 / SC-005 (the per-exe `--version` / banner contract the four pre-existing CLIs already ship):
    - `tx-inspect --version` exits 0 and the first stdout line equals `tx-inspect <semver>` (semver from `Paths_cardano_tx_tools.version`).
    - `tx-inspect --help` exits 0.
    - `TX_INSPECT_NO_UPDATE_CHECK=1 tx-inspect --version` exits 0 with no banner on stderr (assert stderr is empty or carries only the version output).

### Acceptance for slice S1

- [X] T012 (commit: 596d064) [US1] [US2] [US3] [US4] `./gate.sh` green end-to-end. All existing tx-diff golden tests pass byte-identically (proves the per-side render extraction is byte-stable). `nix develop --quiet -c just ci` passes. **Single commit** subject `feat(032): tx-inspect baseline — wire executable, extract per-side renderer, parse RewriteRules` carrying `Tasks: T001, T002, T003, T004, T005, T006, T007, T008, T009, T010, T011`.

**Checkpoint**: foundational stack is live; S2/S3 can begin.

---

## Phase 3: Collapse application — S2 (one subagent run, one commit) → delivers **US2**

**Goal**: `tx-inspect --rules <collapse-only.yaml>` collapses output shapes per the supplied `CollapseRule`s; raw hashes verbatim in exposed slots.

**Independent Test**: per [spec.md US2 Independent Test](./spec.md). Smoke against the existing `swap-cancel-issue-8` body with a hand-crafted collapse-only YAML next to the fixture.

**Subagent brief**: [plan.md § S2](./plan.md#s2--collapse-application-through-rewriterules)

### RED

- [X] T013 (commit: ac2dac5) [P] [US2] Create `/code/cardano-tx-tools-issue-32/test/fixtures/mainnet-txbuild/swap-cancel-issue-8/collapse-only.yaml` (a `{ version: 1, collapse: [<rule for swap-cancel order output>] }` document).
- [X] T014 (commit: ac2dac5) [US2] Add Golden #1 case to `/code/cardano-tx-tools-issue-32/test/Cardano/Tx/InspectSpec.hs` asserting render with `--rules collapse-only.yaml` matches `inspect.collapse-only.txt`. First run: capture+commit golden; second: assert match.
- [X] T015 (commit: ac2dac5) [US2] Add `Rewrite.ApplySpec` to `/code/cardano-tx-tools-issue-32/test/Cardano/Tx/Rewrite/ApplySpec.hs` — pure-function: `applyCollapseFromRewriteRules` on a hand-crafted `RewriteRules` sets `humanCollapseRules` as expected; empty rules leave it unchanged from default.
- [X] T015a (commit: ac2dac5) [US2] Extend `InspectSpec.hs` with a **shared-substrate cross-check at the collapse-only level** (covers spec.md US2 Acceptance #2): render `swap-cancel-issue-8/body.cbor.hex` via `tx-inspect ... --rules collapse-only.yaml` AND via `tx-diff body.cbor.hex body.cbor.hex --rules collapse-only.yaml` (self-diff), extract one side from the diff output, assert byte-equal. If tx-diff's self-diff mode does not emit a per-side render (the implementing subagent confirms by inspecting tx-diff's output format on the existing fixtures), then skip this assertion, note the reason in `WIP.md`, and tag T033 (S4's Amaru cross-check using `rules/amaru-treasury.yaml`) as the sole explicit shared-substrate evidence — US2 Ac#2 remains satisfied by-construction via S1's render-core extraction (T004) plus S2's collapse application.

### GREEN

- [X] T016 (commit: ac2dac5) [US2] Add `applyCollapseFromRewriteRules :: RewriteRules -> HumanRenderOptions -> HumanRenderOptions` to `/code/cardano-tx-tools-issue-32/src/Cardano/Tx/Rewrite.hs`. Body: `\rr opts -> opts { humanCollapseRules = Just (rewriteCollapse rr) }`.
- [X] T017 (commit: ac2dac5) [US2] Edit `/code/cardano-tx-tools-issue-32/app/tx-inspect/Main.hs` — after loading `RewriteRules`, call `applyCollapseFromRewriteRules` before `renderOpenValueHuman`.
- [X] T018 (commit: ac2dac5) [P] [US2] Edit `/code/cardano-tx-tools-issue-32/cardano-tx-tools.cabal` — unit-tests `other-modules += Cardano.Tx.Rewrite.ApplySpec`.
- [X] T019 (commit: ac2dac5) [US2] Extend `/code/cardano-tx-tools-issue-32/gate.sh` with `cabal run -v0 -O0 tx-inspect -- --rules test/fixtures/mainnet-txbuild/swap-cancel-issue-8/collapse-only.yaml test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex | diff -q - test/fixtures/mainnet-txbuild/swap-cancel-issue-8/inspect.collapse-only.txt`.

### Acceptance for slice S2

- [X] T020 (commit: ac2dac5) [US2] `./gate.sh` green. **Single commit** `feat(032): apply collapse rules from RewriteRules in tx-inspect` carrying `Tasks: T013, T014, T015, T015a, T016, T017, T018, T019`.

---

## Phase 4: Rename application — S3 (one subagent run, one commit) → delivers **US3**

**Goal**: Rename leaves at every payment-bearing site (body inputs after resolution, body outputs, withdrawals, certificates) and every script-hash site (body, witness set, reference scripts). `match: payment` (default) and `match: full` both work.

**Independent Test**: per [spec.md US3 Independent Test](./spec.md). Smoke against the existing `swap-cancel-issue-8` body with a hand-crafted rename-only YAML.

**Subagent brief**: [plan.md § S3](./plan.md#s3--rename-application-payment-addresses--script-hashes-with-match-full--payment)

### RED

- [X] T021 (commit: c85876d) [P] [US3] Create `/code/cardano-tx-tools-issue-32/test/fixtures/mainnet-txbuild/swap-cancel-issue-8/rename-only.yaml` covering the known identifiers (addresses + script hashes) in the swap-cancel fixture.
- [X] T022 (commit: c85876d) [US3] Add Golden #2 case to `InspectSpec.hs` (rename-only). First-run capture pattern as for S1/S2.
- [X] T023 (commit: c85876d) [US3] Extend `Rewrite.ApplySpec.hs` with the **load-bearing edge cases** from [spec.md Edge Cases](./spec.md):
    - address with `match: payment` against a base address whose stake credential differs → matches;
    - unknown identifier → leaf renders verbatim;
    - same address with `match: full` against a different stake credential → does NOT match;
    - an `OpenValue` carrying an unresolved input (no `.resolved.address`) plus a rename rule that *would* match the resolved address → render emits the structural unresolved marker; no crash.
- [X] T023a (commit: c85876d) [US3] Extend `Rewrite.ApplySpec.hs` with the **render-level stage-order invariance test (SC-004)**: given a `RewriteRules` and a hand-crafted `OpenValue`, the output of `applyRewriteRules` is independent of the order in which `rewriteCollapse` / `rewriteRename` are constructed (collapse always runs first, rename second). Pair with the parsing-level invariance test T002(c).

### GREEN

- [X] T024 (commit: c85876d) [US3] Extend `/code/cardano-tx-tools-issue-32/src/Cardano/Tx/Rewrite.hs`:
    - Complete the `RenameRule` `FromJSON` instance per [contracts/rules-yaml-grammar.md](./contracts/rules-yaml-grammar.md). Extract the payment credential at parse time for `match: payment`.
    - Add `applyRename :: RenameRules -> OpenValue -> OpenValue` walking the `OpenValue` tree, substituting matching leaves. Site list per FR-009.
    - Add `applyRewriteRules :: RewriteRules -> HumanRenderOptions -> OpenValue -> (HumanRenderOptions, OpenValue)` per [data-model.md](./data-model.md) (stage 1 then stage 2; collapse via `applyCollapseFromRewriteRules`, rename via `applyRename`).
- [X] T025 (commit: c85876d) [US3] Edit `/code/cardano-tx-tools-issue-32/src/Cardano/Tx/Diff.hs` — `renderOpenValueHuman` checks `humanRenameRules` and runs `applyRename` on its input `OpenValue` before walking it (so both `tx-inspect` and `tx-diff` apply rename uniformly).
- [X] T026 (commit: c85876d) [US3] Edit `/code/cardano-tx-tools-issue-32/app/tx-inspect/Main.hs` — replace the two-step `applyCollapseFromRewriteRules` + `renderOpenValueHuman` call with the single `applyRewriteRules` + render path.
- [X] T027 (commit: c85876d) [US3] Extend `/code/cardano-tx-tools-issue-32/gate.sh` with the rename-only smoke (`diff -q` against `inspect.rename-only.txt`).

### Acceptance for slice S3

- [X] T028 (commit: c85876d) [US3] `./gate.sh` green. **Single commit** `feat(032): apply rename rules to payment addresses and script hashes in tx-inspect` carrying `Tasks: T021, T022, T023, T023a, T024, T025, T026, T027`.

---

## Phase 5: Amaru fixtures + P1 + shared substrate — S4 (one subagent run, one commit) → delivers **US1**, **US4**

**Goal**: Ship `rules/amaru-treasury.yaml` and the Amaru treasury swap fixtures. Prove the P1 user story end-to-end (US1) and the shared-substrate property (US4).

**Independent Test**: per [spec.md US1 Independent Test](./spec.md) and [US4 Independent Test](./spec.md).

**Subagent brief**: [plan.md § S4](./plan.md#s4--amaru-treasury-swap-fixtures--shared-substrate-cross-check)

### Subagent first-step open question

- [X] T029 (commit: 3b8ee61) [US1] Append a WIP.md entry at `/code/cardano-tx-tools-issue-32/WIP.md` naming: the exact tx hashes chosen for swap-1 and swap-2, the fetch command, and the planned `swap-N.source.md` content. Orchestrator confirms before fixture commit. (Per plan.md § Open Questions.) **Fallback owner**: if the Amaru journal recipe lookup fails AND Blockfrost `/txs/{hash}/cbor` is unreachable, the subagent halts and surfaces to the orchestrator; the orchestrator chooses between (a) selecting a different recipe, (b) committing a synthetic TxBuild-DSL-constructed swap fixture as a temporary stand-in (covered by a follow-up ticket to refresh with real on-chain bytes), or (c) deferring S4 until network reachability returns. **The subagent never silently substitutes a synthetic fixture.**

### RED

- [X] T030 (commit: 3b8ee61) [P] [US1] Create `/code/cardano-tx-tools-issue-32/test/fixtures/amaru-treasury-swap/swap-1.cbor.hex` and `swap-1.utxo.json` and `swap-1.source.md` per the recipe in the slice brief.
- [X] T031 (commit: 3b8ee61) [P] [US1] Same for `swap-2.cbor.hex`, `swap-2.utxo.json`, `swap-2.source.md`.
- [X] T032 (commit: 3b8ee61) [US1] Create `/code/cardano-tx-tools-issue-32/rules/amaru-treasury.yaml` per [contracts/rules-yaml-grammar.md § Example](./contracts/rules-yaml-grammar.md) — `version: 1`, `views: { raw: show }`, collapse rule(s) for the swap output shape, rename rules for the identifiers used in the two fixtures.
- [X] T033 (commit: 3b8ee61) [US1] [US4] Add Golden #3 case (`amaru-swap-1.both.txt`) and the cross-check Golden #3b case (`amaru-swap-1-vs-2.from-tx-diff.txt` — one side of `tx-diff swap-1 swap-2 --rules rules/amaru-treasury.yaml` must equal `amaru-swap-1.both.txt` byte-for-byte) to `InspectSpec.hs`. First-run capture pattern.

### GREEN

No new production code in S4 — the production code is complete after S3. The slice is fixtures + rules + golden. The implementation work consists of:

- [X] T034 (commit: 3b8ee61) [US1] [US4] Extend `/code/cardano-tx-tools-issue-32/gate.sh` with both smokes:
    - `cabal run -v0 -O0 tx-inspect -- --rules rules/amaru-treasury.yaml test/fixtures/amaru-treasury-swap/swap-1.cbor.hex | diff -q - test/fixtures/amaru-treasury-swap/golden/swap-1.both.txt`.
    - `cabal run -v0 -O0 tx-diff -- --rules rules/amaru-treasury.yaml test/fixtures/amaru-treasury-swap/swap-1.cbor.hex test/fixtures/amaru-treasury-swap/swap-2.cbor.hex | <extract-side-1 helper> | diff -q - test/fixtures/amaru-treasury-swap/golden/swap-1.both.txt`. The `<extract-side-1 helper>` is a one-liner `awk`/`sed` selection from the tx-diff per-side output format; the subagent picks the right one when implementing.
- [X] T035 (commit: 3b8ee61) [US1] (no gap surfaced) **Contingency, non-blocking when no gap exists**: if T034 reveals a production-code gap (e.g. an `OpenValue` site rename does not reach), halt the slice, append a `WIP.md` note describing the gap, and surface to the orchestrator. **Do not silently patch S3's code in S4.** The orchestrator decides whether to redispatch S3 (per resolve-ticket — accepted slices are frozen; corrections are forward commits, not in-place restacks). Mark T035 complete on slice acceptance when no gap was found; otherwise T035 stays open and the slice is blocked.

### Acceptance for slice S4

- [X] T036 (commit: 3b8ee61) [US1] [US4] `./gate.sh` green. **Single commit** `feat(032): add Amaru treasury swap fixtures and shared-substrate golden` carrying `Tasks: T029, T030, T031, T032, T033, T034`.

---

## Phase 6: Docs — S5 (one subagent run, one commit, cross-cutting)

**Goal**: `docs/tx-inspect.md` end-to-end docs page; new `rename:` section in the existing rewriting-rules grammar doc; `mkdocs.yml` nav entry; `README.md` CLI list update.

**Subagent brief**: [plan.md § S5](./plan.md#s5--documentation-docstx-inspectmd--rename-section-in-the-existing-grammar-doc)

### Subagent first-step open question

- [ ] T037 Append a WIP.md entry at `/code/cardano-tx-tools-issue-32/WIP.md` naming: the exact file where the existing collapse-rules grammar is documented today (`docs/rewriting-rules.md`, `docs/tx-diff.md`, or inline Haddock in `Cardano.Tx.Diff`). Orchestrator confirms.

### RED

- [ ] T038 Add `tx-inspect.md` nav entry to `/code/cardano-tx-tools-issue-32/mkdocs.yml`. `nix develop --quiet -c just build-docs` (`mkdocs build --strict`) fails because the file does not yet exist.

### GREEN

- [ ] T039 Create `/code/cardano-tx-tools-issue-32/docs/tx-inspect.md` per [quickstart.md](./quickstart.md) — operator-facing end-to-end docs (input forms, `--rules`, resolver flags, output shape, exit codes, the two-stage pipeline).
- [ ] T040 Edit the grammar doc identified by T037 — add a new section documenting the `rename:` grammar per [contracts/rules-yaml-grammar.md](./contracts/rules-yaml-grammar.md).
- [ ] T041 [P] Edit `/code/cardano-tx-tools-issue-32/README.md` — `## CLIs` (or equivalent) row added for `tx-inspect`.

### Acceptance for slice S5

- [ ] T042 `./gate.sh` green; `nix develop --quiet -c just build-docs` passes. **Single commit** `docs(032): document tx-inspect and the rename rule kind` (no `Tasks:` trailer required — `docs:` is exempt per the commit message gate).

---

## Phase 7: Release pipeline wiring — S6 (one subagent run, one commit, cross-cutting)

**Goal**: Every release pipeline site that names a CLI today also names `tx-inspect` after this commit (FR-017).

**Subagent brief**: [plan.md § S6](./plan.md#s6--release-pipeline-wiring-homebrew-tap-appimage-debrpm-docker-release-please)

### Subagent first-step open question

- [ ] T043 Append a WIP.md entry at `/code/cardano-tx-tools-issue-32/WIP.md` listing every `.github/workflows/*.yaml` + `release-please*` site that names any of `{tx-validate, tx-diff, tx-sign, cardano-tx-generator}`. Orchestrator confirms list completeness before edits.

### RED

- [ ] T044 Add the local in-repo grep gate to `/code/cardano-tx-tools-issue-32/gate.sh`: `! grep -L 'tx-inspect' .github/workflows/release*.yaml` (every release workflow that names tx-diff must also name tx-inspect). Fails until T045 lands.

### GREEN

- [ ] T045 Edit every file from T043 to also name `tx-inspect`. Auto-discovery channels need no edit; record any such in the commit body as "no edit required for channel X — already auto-discovered via flake apps iteration".

### Acceptance for slice S6

- [ ] T046 `./gate.sh` green (including the grep gate). **Single commit** `chore(032): wire tx-inspect into the release pipeline` (no `Tasks:` trailer required — `chore:` is exempt). PR body gains an **Operator follow-up** section naming `paolino` as the owner of the post-merge release verification (`gh release view v<next> --json assets` must list `tx-inspect`).

---

## Phase 8: Finalization — S7 (orchestrator chore, one commit)

- [ ] T047 Orchestrator runs the finalization audit (`commit_gate` over every commit on the branch; `tasks.md` has no unchecked `[ ]`). Per the [gate-script](../../gate-script) skill.
- [ ] T048 Orchestrator drops `gate.sh` (`git rm gate.sh && git commit -m "chore: drop gate.sh (ready for review)"`). Per the gate-script skill.
- [ ] T049 Orchestrator updates the PR body to reflect ready-for-review status, then `gh pr ready 33`.

---

## Dependencies

- **S1 blocks every later slice.** Foundational extraction + types are not partial.
- **S2 ↔ S3 are independent of each other** but both depend on S1. S3 also extends the parser to handle `rename:` entries, so if S2 ships first the unused parser code lands silently; if S3 ships first the `applyCollapseFromRewriteRules` does not yet exist. Either order works; my plan ships S2 first (smaller diff, faster RED→GREEN cycle).
- **S4 depends on S1, S2, S3** (needs all three stages to render the Amaru golden correctly).
- **S5 depends on S4** (the grammar doc's `rename:` section examples reference the Amaru rules file, and the docs need the P1 path to be live to describe).
- **S6 depends on S1** (release pipeline only needs the executable to exist); ordering before or after S4/S5 is OK. Plan ships S6 last so the docs page is in place when the first release ships.

## Parallel opportunities

**Across slices**: none. Each slice is one subagent run = one commit, and they have a strict dependency chain (S1 → {S2, S3} → S4 → S5, with S6 anywhere after S1).

**Within a slice**: tasks marked `[P]` (e.g. T001/T002 in S1, T013 in S2, T021 in S3) are file-disjoint inside the slice and can be edited in any order by the subagent. They still fold into a single commit at slice acceptance.

## Implementation strategy

1. **MVP scope = S1 + S2 OR S1 + S3.** Either US2 (collapse-only) or US3 (rename-only) is a viable MVP increment that proves stage independence. The plan delivers both (S2 before S3) because the additional implementation cost is small once S1 is in place.

2. **Full P1 = S1 + S2 + S3 + S4.** The treasury reviewer's operator command is only fully proved by S4's Amaru fixtures and the shared-substrate cross-check.

3. **Ready for review = S1..S6 + S7.** S5 and S6 are cross-cutting concerns that must land before the PR can be marked ready.

## Format validation (orchestrator self-check)

- [x] Every task has a checkbox.
- [x] Every task has an ID (T000..T049).
- [x] Every task has an absolute file path or names a clearly-identified existing file.
- [x] Tasks within a slice are marked `[P]` only when file-disjoint inside the slice.
- [x] `[US#]` labels appear on every task that moves a user story forward; setup/foundational/chore tasks omit the label.
- [x] Each slice's RED/GREEN section is named explicitly and folded into one bisect-safe commit.
- [x] Every behavior-changing slice's commit body trailer (`Tasks: T###[, T###]`) is named in its Acceptance task.
- [x] Docs and chore commits are exempt from the Tasks: trailer per the commit message gate.

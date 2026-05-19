# Implementation Plan: Test-fixture harness — ten reproducible Conway transactions + Turtle/text golden infrastructure

**Branch**: `45-harness-conway-fixtures-045` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/033-rewrite-redesign-harness/spec.md`

## Summary

The harness delivers a static contract under `test/fixtures/rewrite-redesign/`: ten fixture directories — each carrying a Haskell `Tx ConwayEra` builder, the operator rules YAML, the expected Turtle graph (post-signal), and the expected text rendering — plus two CIP-57 blueprint files and one Hspec module (`Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec`) wired into the existing `unit-tests` suite. The suite registers three Hspec items per fixture: a structural check that runs actively, and two `pending` items naming `#47` (emitter MVP) and `#51` (cli-tree SPARQL view) as the upstream dependencies. The harness ships no emitter and no SPARQL runtime; its sole job is to lock the contract on disk so downstream waves of epic `#46` (045-graph-emit-pivot) have a runnable target.

The harness is split into an **A side** (vocab-independent: builders, rules.yaml, blueprints, expected.txt, suite scaffolding) that lands ahead of `cardano-knowledge-maps#53` Phase A, and a **B side** (vocab-pinned: every `expected.ttl`) that lands after the kmaps#53 Phase A release signal arrives. Side A is the bulk of the work; Side B is one Turtle file per fixture, hand-authored against the URIs Phase A actually publishes.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (`compiler-nix-name = "ghc9123"`, constitution Operational Constraints).
**Primary Dependencies**: Existing `cardano-tx-tools` library + `unit-tests` test-suite. The harness lives entirely under `test/`. Test-suite deps used: `hspec`, `cardano-ledger-conway`, `cardano-ledger-core`, `cardano-ledger-mary`, `cardano-ledger-alonzo`, `cardano-ledger-api`, `cardano-ledger-shelley`, `cardano-slotting`, `cardano-strict-containers`, `aeson`, `bytestring`, `containers`, `data-default`, `microlens`, `cardano-tx-tools` (the library). All already in the `unit-tests` build-depends. Phase 0 evaluates whether a Turtle parser dep is added or a thin internal shim suffices.
**Storage**: N/A. The harness is on-disk fixtures + a pure Hspec module.
**Testing**: `hspec` driven from `test/unit-main.hs`. Pending items via `Test.Hspec.pendingWith`. Invoked via `nix develop --quiet -c just unit` (the existing `./gate.sh` unit step).
**Target Platform**: Linux dev shell + CI; no runtime platform — the harness is build-time artifacts plus a test-suite.
**Project Type**: Library + CLI repo. This feature is a test-asset addition only — no library exposed-modules change, no new executable. One additive module under `test/Cardano/Tx/Rewrite/`.
**Performance Goals**: The new spec must add < 5 seconds to `just unit` wall-time when all fixtures are present. Each fixture's structural check is a constant-time builder invocation; the suite scales linearly in fixture count (10). No `O(n²)` walks.
**Constraints**: `./gate.sh` MUST exit 0 on every commit of this PR (resolve-ticket invariant). No regression of existing `Cardano.Tx.InspectSpec` or other 032/014/015 specs. No new library exposed module (preserves API surface).
**Scale/Scope**: 10 fixture directories; ~30 source files in total (10 × `Tx.hs` + 10 × `rules.yaml` + 10 × `expected.txt` + post-signal 10 × `expected.ttl` + 2 × blueprint JSON + 1 × `Helpers.hs` + 1 × `RewriteRedesignGoldenSpec.hs`). Bounded by the 044 user-story count; no growth pressure.

## Constitution Check

*Gate evaluated against `.specify/memory/constitution.md` v1.0.0.*

| Principle | Status | Note |
|---|---|---|
| I. One-Way Dependency On Node-Clients | PASS | Harness is test-only; no library API change; no new dep on `cardano-node-clients`. |
| II. Module Namespace Discipline | PASS | The constitution's `Cardano.Tx.*` rule governs **library exposed modules**. The harness adds one library-adjacent module under that namespace — the goldens spec `Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec` — which lives in the `unit-tests` test-suite as `other-modules`, not as a library exposed module, and obeys the namespace anyway for editorial consistency with the existing test tree. **The fixture modules use a deliberate test-side carve-out** under the `Fixtures.RewriteRedesign.*` namespace (`Fixtures.RewriteRedesign.Helpers`, `Fixtures.RewriteRedesign.S<NN>_<…>`), recorded in `research.md` D9. Rationale: pulling test fixtures into `Cardano.Tx.*` would imply library API status; `Fixtures.*` makes their test-only nature load-bearing at the module-name level. No `Node.Client.*` introduction. No library exposed-modules churn. |
| III. Conway-Only Era | PASS | Every fixture produces a `Tx ConwayEra` value. No pre-Conway types. |
| IV. Hackage-Ready Quality | PASS | Test modules carry Haddock module headers and `-Wall -Werror`-clean code. `cardano-tx-tools.cabal` already lists test sources; new `other-modules` entries are added in the `unit-tests` test-suite. |
| V. Strict Warnings, No `-Werror` Escape Hatches | PASS | All new modules compile under the existing `common warnings` import — no escape. |
| VI. Default-Offline Semantics | PASS | The harness is pure on-disk content. No network access. |
| VII. TDD With Vertical Bisect-Safe Commits | PASS | Each fixture lands as one bisect-safe commit (per the resolve-ticket-additive slice plan below). `./gate.sh` runs green at every HEAD. |

No constitution violations. No complexity tracking entries required.

### resolve-ticket additions on the plan

- **Orchestrator / subagent ownership**:
  - **Orchestrator owns**: `spec.md`, `plan.md`, `tasks.md`, the three contracts files under `contracts/`, the `kmaps#53` signal coordination (waiting for the release signal from epic pane), the gate-script extension if any, PR body & metadata, post-merge cleanup. The orchestrator also writes the optional `feat(rewrite)` YAML-parser-extension slice when the fixtures land an extension that the existing `parseRewriteRulesYaml` cannot accept — that slice is small and additive, not a per-fixture concern.
  - **Implementation subagents own**: producing one commit per slice: scaffolding the suite (S1), shared helpers (S2), blueprints (S3), each fixture (S5..S14), each post-signal `expected.ttl` file (S15..S24), and the final `chore: drop gate.sh` (S26).
- **Vertical, bisect-safe slices**: every slice below maps to **one** subagent run. The subagent brief carries the slice's owned files + RED/GREEN proof.
- **Proof strategy per slice**: RED is a failing structural check before the slice's content (the registry entry that names a missing fixture; the empty Hspec `describe` block that asserts a missing builder). GREEN is the fixture content satisfying the check. RED and GREEN fold into one commit per slice. See `tasks.md` for the per-slice RED/GREEN naming.
- **Live-boundary diagnostic**: *"What system boundary does this exercise that the unit suite cannot?"* — **None**. The harness is pure on-disk artifacts and an Hspec module. No node socket, no database, no HTTP API. Every property the harness contracts (Tx builds, YAML parses, Turtle parses, text byte-equal) is exercised by `just unit` itself. No live-boundary smoke is required, and no operator follow-up is deferred.
- **Carry-forward invariant for the epic**: the harness's URI shape MUST equal whatever kmaps#53 Phase A publishes. The orchestrator gates `expected.ttl` slices on the explicit release signal posted to the epic pane (see `contracts/kmaps-signal.md`). No `expected.ttl` slice is dispatched before that signal arrives.

## Project Structure

### Documentation (this feature)

```text
specs/033-rewrite-redesign-harness/
├── plan.md              # This file
├── research.md          # Phase 0 — research decisions
├── data-model.md        # Phase 1 — fixture / registry data shapes
├── quickstart.md        # Phase 1 — how an engine implementer wires the emitter against the suite
├── contracts/
│   ├── harness-directory.md   # Filesystem contract for test/fixtures/rewrite-redesign/
│   ├── goldens-suite.md       # Hspec scaffolding contract
│   └── kmaps-signal.md        # kmaps#53 Phase A release-signal protocol
├── checklists/
│   └── requirements.md  # Spec quality checklist (filled in by speckit-specify)
├── spec.md              # Feature specification
└── tasks.md             # Phase 2 — task breakdown (filled in by speckit-tasks)
```

### Source Code (repository root)

The fixture tree splits into a **Haskell module subtree** (path = module name, GHC's requirement) and **data-file directories** (reviewer-friendly `<NN>-<kebab-slug>/` for `rules.yaml` / `expected.txt` / `expected.ttl`). Haskell modules cannot resolve from Haskell-illegal directory names (e.g. `02-alice-bob-ada`), so the per-fixture `Tx.hs` files live under `Fixtures/RewriteRedesign/S<NN>_<CamelCaseSlug>.hs`, not inside the kebab data-file directories. The two halves are linked by the fixture's `StoryId` (the kebab directory name) and `mkFixturePaths` (which derives the data-file paths from the `StoryId`).

```text
test/
├── unit-main.hs                                          # extended: import + register RewriteRedesignGoldenSpec
├── Cardano/
│   └── Tx/
│       └── Rewrite/
│           ├── ApplySpec.hs                              # untouched
│           ├── LoadSpec.hs                               # untouched
│           └── RewriteRedesignGoldenSpec.hs              # NEW — the goldens suite (S1)
└── fixtures/
    └── rewrite-redesign/                                 # NEW
        ├── Fixtures/                                     # Haskell module subtree (path == module name)
        │   └── RewriteRedesign/
        │       ├── Helpers.hs                            # Fixtures.RewriteRedesign.Helpers (S2)
        │       ├── S01_AmaruTreasurySwap.hs              # one per fixture
        │       ├── S02_AliceBobAda.hs
        │       ├── S03_MultiAssetTransfer.hs
        │       ├── S04_MintSpendScriptOverlap.hs
        │       ├── S05_WithdrawalScriptStake.hs
        │       ├── S06_StakePoolDelegation.hs
        │       ├── S07_VoteDelegation.hs
        │       ├── S08_ContingencyDisburse.hs
        │       ├── S09_MpfsFactsRequest.hs
        │       └── S10_GovernanceTreasuryWithdrawal.hs
        ├── blueprints/                                   # CIP-57 data files (S3)
        │   ├── swap-v2-datum.cip57.json
        │   └── mpfs-fact.cip57.json
        ├── 01-amaru-treasury-swap/                       # per-fixture data-file directory
        │   ├── rules.yaml
        │   ├── expected.txt                              # vocab-independent (lands ahead of signal)
        │   └── expected.ttl                              # post-signal
        ├── 02-alice-bob-ada/
        │   ├── rules.yaml
        │   ├── expected.txt
        │   └── expected.ttl
        ├── 03-multi-asset-transfer/
        │   └── ...
        ├── 04-mint-spend-script-overlap/
        │   └── ...
        ├── 05-withdrawal-script-stake/
        │   └── ...
        ├── 06-stake-pool-delegation/
        │   └── ...
        ├── 07-vote-delegation/
        │   └── ...
        ├── 08-contingency-disburse/
        │   └── ...
        ├── 09-mpfs-facts-request/
        │   └── ...
        └── 10-governance-treasury-withdrawal/
            └── ...

cardano-tx-tools.cabal                                    # extended: unit-tests other-modules + hs-source-dirs
```

**Structure Decision**: The harness extends the existing `test/` tree only. No new library exposed-modules, no new executable, no new test-suite. One additive Hspec module plus a Haskell-source fixture tree alongside the existing `test/fixtures/` content (`tx-sign`, `mainnet-txbuild`, `amaru-treasury-swap`). The fixture builders live as Haskell modules under `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S<NN>_<CamelCaseSlug>.hs` so the unit-tests suite can import them directly — no test-time CBOR loading, no on-disk serialization detour. The cabal `unit-tests` `other-modules` list grows by 1 helpers module + 1 goldens spec + 10 fixture modules; the existing `hs-source-dirs: test` is extended with `hs-source-dirs: test test/fixtures/rewrite-redesign`.

## Complexity Tracking

No constitution violations. Section intentionally empty.

## Vertical Slices

The harness lands as the slice sequence below. Each slice = one subagent run = one bisect-safe commit. Detailed task-level steps live in `tasks.md`. The orchestrator does NOT dispatch any `expected.ttl` slice (S15..S24) until the kmaps#53 Phase A release signal arrives — see `contracts/kmaps-signal.md`.

| # | Slice | Side | Subject | Depends on |
|---|---|---|---|---|
| S1 | Scaffold goldens suite | A | `chore(045): scaffold RewriteRedesignGoldenSpec + empty registry + wire into unit-tests` | — |
| S2 | Builder helpers | A | `test(045): builder helpers for rewrite-redesign fixtures` | S1 |
| S3 | Blueprints | A | `test(045): CIP-57 blueprints — swap-v2-datum + mpfs-fact` | S2 |
| S4 | YAML extension (conditional) | A | `feat(rewrite): extend parseRewriteRulesYaml for 045 entity/blueprint sugars` (only if fixture YAMLs cannot parse on the existing parser) | S2 |
| S5 | Fixture 02 (Alice → Bob) | A | `test(045): fixture 02-alice-bob-ada` | S2 |
| S6 | Fixture 03 (multi-asset) | A | `test(045): fixture 03-multi-asset-transfer` | S2 |
| S7 | Fixture 05 (withdrawal) | A | `test(045): fixture 05-withdrawal-script-stake` | S2 |
| S8 | Fixture 06 (delegation) | A | `test(045): fixture 06-stake-pool-delegation` | S2 |
| S9 | Fixture 07 (vote-deleg) | A | `test(045): fixture 07-vote-delegation` | S2 |
| S10 | Fixture 04 (mint+spend) | A | `test(045): fixture 04-mint-spend-script-overlap` | S2, S3 |
| S11 | Fixture 08 (contingency) | A | `test(045): fixture 08-contingency-disburse` | S2 |
| S12 | Fixture 10 (governance) | A | `test(045): fixture 10-governance-treasury-withdrawal` | S2 |
| S13 | Fixture 01 (Amaru swap) | A | `test(045): fixture 01-amaru-treasury-swap` | S2, S3, S10, S11 |
| S14 | Fixture 09 (MPFS facts) | A | `test(045): fixture 09-mpfs-facts-request` | S2, S3 |
| **— BLOCK ON kmaps#53 Phase A SIGNAL —** | | | | |
| S15..S24 | `expected.ttl` per fixture (10 slices) | B | `test(045): pin <story-id> expected.ttl to kmaps#53 Phase A vocab` | corresponding A-slice, signal |
| S25 | Finalization | — | docs / README / CHANGELOG sync | all prior |
| S26 | Drop gate.sh | — | `chore: drop gate.sh (ready for review)` | S25 |

The A-side order goes simplest-first (S5: Alice → Bob) and converges on the load-bearing P1 fixture (S13: Amaru swap) once the builder helpers + blueprint scaffolding + the contingency-disburse precedent are in place.

S4 is conditional. The first A-side fixture slice (S5: Alice → Bob) uses only existing 044 YAML grammar (no `entities:` list, no `blueprints:`). Once the structural shape is locked, the next fixture that needs the 045 sugar triggers S4 if needed. If the existing parser accepts the 044 YAMLs unchanged, S4 is dropped.

## Risks And Migration Concerns

1. **kmaps#53 Phase A signal delay**: the worst case is that Phase A doesn't land during this PR's lifetime. Mitigation: A-side delivers a complete, structurally-checked harness independently of the signal. If the signal does not arrive before the PR is otherwise ready, the orchestrator carves out the B-side slices into a follow-up issue, updates `tasks.md` to reflect the deferral, and marks the PR ready with the B-side as a documented follow-up. The goldens suite's two `pending` items keep the contract honest in either case.
2. **kmaps#53 Phase A URI churn**: the signal locks the URIs at one commit, but a kmaps follow-up may rename. Mitigation: all `expected.ttl` files derive from a single set of vocab constants. A rename is a mechanical sed; the harness's "every URI under `cardano:` prefix" check catches drift.
3. **Existing parser cannot accept 045 YAML sugars**: S4 covers the additive extension. If the extension turns out to be invasive (touches more than the YAML parser), the orchestrator pauses A-side fixture slices and re-cuts the plan.
4. **Whitespace canon drift**: `expected.txt` files must match a canon a future SPARQL projection can hit. Mitigation: each `expected.txt` ships with a top-of-file `# canon: stripped trailing whitespace; one final newline` comment (where the surrounding format permits — e.g. inside a YAML-like header). The goldens suite includes a static canon-check item per fixture.
5. **Test-suite wall time**: ten new fixture builders + ten Turtle parse checks adds time. Mitigation: builder helpers compile once; Turtle parse uses a thin internal shim (no heavyweight RDF lib). Phase 0 finalises the choice.
6. **No regression of `Cardano.Tx.InspectSpec`**: the existing `InspectSpec` covers the legacy text rendering. Adding a parser extension (S4) could change parse outcomes. Mitigation: S4's RED check explicitly enumerates the legacy-grammar YAMLs that must continue to round-trip identically.

## Live-Boundary Diagnostic

For each behaviour change in this plan, ask: *"What system boundary does this exercise that the unit suite cannot?"*

- The harness ships fixtures + a pure Hspec module. **No system boundary** is exercised. The unit suite (which is the harness's own home) is sufficient. No live-boundary smoke is required; no operator follow-up is deferred.

The conditional S4 (YAML parser extension) likewise exercises only pure parsing. No boundary.

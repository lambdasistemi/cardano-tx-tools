---

description: "Task list for harness #45 (ten Conway tx fixtures + Turtle/text goldens, 045 re-aim)"
---

# Tasks: Test-fixture harness — ten Conway tx fixtures + Turtle/text goldens

**Input**: Design documents from `specs/033-rewrite-redesign-harness/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`
**Tests**: Yes — the harness IS test infrastructure. The Hspec `RewriteRedesignGoldenSpec` and its per-fixture `it` blocks are the harness's deliverables.

**Organization**: Each task = one bisect-safe slice = one subagent commit. Slice id `T###` doubles as the `S###` in `plan.md`. Every behaviour-changing commit carries `Tasks: T###` in the body trailer and the corresponding checkbox in this file is checked in the same amended slice commit (resolve-ticket invariant).

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel with other [P] tasks in the same phase.
- **[Story]**: US1..US11 from `spec.md`. Foundational and polish tasks carry no story label.

## A/B split

- **A-side** (vocab-independent): every task from T001 through T014 plus T025 / T026. Lands ahead of the `kmaps#53` Phase A release signal.
- **B-side** (vocab-pinned): T015..T024. **BLOCKED** on the kmaps#53 Phase A signal arriving as `/tmp/epic-046/tx-45/answers/A-NNN-kmaps-phase-a.md`. See `contracts/kmaps-signal.md`.

## Path Conventions

- Library: `src/Cardano/Tx/`
- Existing tests: `test/Cardano/Tx/`
- Goldens-suite module: `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`
- Fixture tree: `test/fixtures/rewrite-redesign/`
- Cabal: `cardano-tx-tools.cabal`
- Gate: `gate.sh`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The worktree, draft PR #55, `gate.sh`, and the existing `unit-tests` test-suite are already in place. No additional setup is required beyond Phase 2's foundational scaffolding.

No tasks in this phase.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Wire the empty goldens spec into `unit-tests`; ship the shared fixture helpers and the two CIP-57 blueprints; conditionally extend the YAML parser. Every user-story (fixture) task depends on these.

**⚠️ CRITICAL**: No fixture task (T005..T014) starts until T001, T002, and T003 are done.

- [X] T001 Scaffold `Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec` with an empty fixture registry; wire it into `test/unit-main.hs` and the `unit-tests` cabal `other-modules`; add `test/fixtures/rewrite-redesign` to `hs-source-dirs`. `./gate.sh` MUST be green at HEAD with the suite reporting zero examples for the empty registry. Files: `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `test/unit-main.hs`, `cardano-tx-tools.cabal`.
- [X] T002 Add `Fixtures.RewriteRedesign.Helpers` module exporting `mkTx`, canonical bech32 addresses (alice, bob, treasury, network-wallet, contingency, recipient, operator, mpfs.oracle, foundation.ops), smart constructors (inputs, outputs, withdrawals, certs, proposals), the `ada` / `lovelace` units, the `ExpectedShape` record + `baseShape`, and the `assertShape` helper. Files: `test/fixtures/rewrite-redesign/Helpers.hs`, `cardano-tx-tools.cabal`. *(Landed: 380250e — file actually placed at `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/Helpers.hs` per GHC module-name path-resolution; address constants and smart constructors deferred per per-fixture growth model; planning-doc tree reconciliation tracked in follow-up `docs(045): reconcile fixture module-path layout`.)*
- [X] T003 [P] Ship the two CIP-57 blueprints: `swap-v2-datum.cip57.json` (constructor `SwapOrder` with `recipient: Credential`) and `mpfs-fact.cip57.json` (constructor `Fact` with `requester: PubKeyHash`). Add a foundational Hspec item to `RewriteRedesignGoldenSpec` asserting both files exist on disk and parse as JSON. Files: `test/fixtures/rewrite-redesign/blueprints/swap-v2-datum.cip57.json`, `test/fixtures/rewrite-redesign/blueprints/mpfs-fact.cip57.json`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`. *(Landed: 0e1ae9b — two active `it` items in foundational `describe "blueprints"` block; 124 examples total.)*
- [ ] T004 *(conditional — DROPPED by T005 preflight on 2026-05-19: existing parser accepts the 044 Story 2 YAML; top-level `entities:` is silently ignored by Aeson's `withObject` default. Real entity parsing belongs to #47/#48 rules loader, not the harness. T004 stays unchecked as a record; can be removed in S25 finalization.)* Extend `parseRewriteRulesYaml` to accept the 045 entity sugars (`entities:` list, `blueprints:` section, new `kind:` values for `pool` / `drep` / `asset` if needed). The extension MUST be additive: every legacy 032/044 YAML continues to parse identically (RED test list: every YAML under `test/Cardano/Tx/Rewrite/LoadSpec.hs`). Drop this task if the first fixture (T005) reveals the existing parser already accepts the 045 YAMLs. Files: `src/Cardano/Tx/Rewrite.hs`, `test/Cardano/Tx/Rewrite/LoadSpec.hs`, `cardano-tx-tools.cabal` (only if a new build-dep is required).

**Checkpoint**: Foundation ready — fixture stories (US2..US11) can be implemented sequentially in dependency order.

---

## Phase 3: User Story 1 (US1) — scaffolding (already covered)

US1 from `spec.md` is the suite scaffolding itself. It is delivered by Phase 2 (T001 / T002 / T003). No separate phase needed.

---

## Module-path convention for per-fixture slices

Per `data-model.md` (post-S2 reconciliation) and `contracts/harness-directory.md`: each per-fixture Haskell module lives at `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S<NN>_<CamelCaseSlug>.hs` (GHC module-name resolution requires this — kebab-cased directories aren't valid Haskell module paths). The kebab data-file directories `test/fixtures/rewrite-redesign/<NN>-<kebab-slug>/` hold only `rules.yaml`, `expected.txt`, and (B-side) `expected.ttl`. Each fixture's `S<NN>_<CamelCaseSlug>` module references its kebab directory via its `StoryId` constructor + `mkFixturePaths`.

## Phase 4: User Story US3 — 02-alice-bob-ada (Priority: P2, simplest A-side fixture) 🎯 first MVP fixture

**Goal**: Land the simplest fixture as the first per-fixture slice, validating the scaffold + helpers contract end-to-end against a real `ConwayTx` and a real `rules.yaml`.

**Independent Test**: `nix develop --quiet -c just unit -- --match "RewriteRedesignGoldens/02-alice-bob-ada"` reports the structural item PASS and the two pending items PENDING. `./gate.sh` green at HEAD.

- [X] T005 [US3] **Preflight**: before writing any code, parse the planned `02-alice-bob-ada/rules.yaml` (the verbatim 044 Story 2 YAML) against the **current** `Cardano.Tx.Rewrite.parseRewriteRulesYaml` in `ghci`. If the parse fails, **halt**, log a STATUS.md `NOTE T005 preflight: rules.yaml does not parse on existing parser; triggering T004`, write a question file naming the parser gap, and dispatch **T004 first**; T005 lands on top of T004. If the parse succeeds, proceed with T005 normally and drop T004 from the plan in a follow-up `docs(045)` slice. Then: ship fixture `02-alice-bob-ada`: `Tx.hs` (1 input from Alice, 2 outputs to Bob + Alice change), `rules.yaml` (verbatim from 044 Story 2), `expected.txt` (verbatim canon-stripped from 044 Story 2). Append the `Fixtures.RewriteRedesign.S02_AliceBobAda` module to the cabal `other-modules`. Append one `FixtureEntry` to `fixtureRegistry` in `RewriteRedesignGoldenSpec`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S02_AliceBobAda.hs`, `test/fixtures/rewrite-redesign/02-alice-bob-ada/rules.yaml`, `test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.txt`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`.

**Checkpoint**: First fixture lives; the registry pattern is validated; remaining fixtures repeat the shape.

---

## Phase 5: User Story US4 — 03-multi-asset-transfer (Priority: P2)

**Goal**: Multi-asset value with two declared assets. Adds asset-class entity surface.

**Independent Test**: Match `--match "03-multi-asset-transfer"`; structural item PASS; pending items PENDING.

- [X] T006 [P] [US4] Ship fixture `03-multi-asset-transfer`: `Tx.hs` (1 input from Alice, 2 outputs carrying USDM + MEME), `rules.yaml` (verbatim from 044 Story 3), `expected.txt`. Append to `other-modules` + `fixtureRegistry`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S03_MultiAssetTransfer.hs`, `test/fixtures/rewrite-redesign/03-multi-asset-transfer/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`.

---

## Phase 6: User Story US6 — 05-withdrawal-script-stake (Priority: P2)

**Goal**: Stake reward withdrawal from a script-controlled stake account.

- [X] T007 [P] [US6] Ship fixture `05-withdrawal-script-stake`: `Tx.hs` (1 input from Alice, 1 output to Alice, 1 withdrawal at the script-stake), `rules.yaml` from 044 Story 5, `expected.txt`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S05_WithdrawalScriptStake.hs`, `test/fixtures/rewrite-redesign/05-withdrawal-script-stake/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`.

---

## Phase 7: User Story US7 — 06-stake-pool-delegation (Priority: P2)

**Goal**: `StakeDelegation` certificate referencing a pool key hash.

- [X] T008 [P] [US7] Ship fixture `06-stake-pool-delegation`: `Tx.hs` (1 input, 1 output, 1 cert), `rules.yaml` from 044 Story 6, `expected.txt`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S06_StakePoolDelegation.hs`, `test/fixtures/rewrite-redesign/06-stake-pool-delegation/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`.

---

## Phase 8: User Story US8 — 07-vote-delegation (Priority: P2)

**Goal**: `VoteDelegation` cert + the `AlwaysAbstain` variant.

- [X] T009 [P] [US8] Ship fixture `07-vote-delegation`: `Tx.hs` (1 input, 1 output, 1 vote-delegation cert), `rules.yaml` from 044 Story 7, `expected.txt`. Carries a sibling micro-fixture path for the `AlwaysAbstain` variant case (encoded as a second exported `tx` value if needed; see helpers contract). Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S07_VoteDelegation.hs`, `test/fixtures/rewrite-redesign/07-vote-delegation/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`.

---

## Phase 9: User Story US9 — 08-contingency-disburse (Priority: P2, #43 reproducer)

**Goal**: The #43 reproducer — collapse bucket pinning `resolved.address` in `required:`.

- [X] T010 [US9] Ship fixture `08-contingency-disburse`: `Tx.hs` (2 inputs from the contingency self-script, 1 user-wallet collateral, 1 output to recipient + 1 change to contingency), `rules.yaml` from 044 Story 8 (collapse rule pinning `resolved.address`), `expected.txt`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S08_ContingencyDisburse.hs`, `test/fixtures/rewrite-redesign/08-contingency-disburse/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`. *(No `[P]` — relies on the contingency-self-script address helper; first fixture exercising self-script collateral.)*

---

## Phase 10: User Story US5 — 04-mint-spend-script-overlap (Priority: P2)

**Goal**: Plutus mint + spend overlap where the same hash carries both `PaymentScript` and `Policy` roles.

- [X] T011 [US5] Ship fixture `04-mint-spend-script-overlap`: `Tx.hs` (1 input under the script address, 1 output, mint field, witness-set script), `rules.yaml` from 044 Story 4 (`keys: [PaymentScript, Policy]`), `expected.txt`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S04_MintSpendScriptOverlap.hs`, `test/fixtures/rewrite-redesign/04-mint-spend-script-overlap/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`. *(No `[P]` — requires the witness-set script helpers added in T003.)*

---

## Phase 11: User Story US11 — 10-governance-treasury-withdrawal (Priority: P3)

**Goal**: Conway `ProposalProcedure` of variety `TreasuryWithdrawals`.

- [X] T012 [P] [US11] Ship fixture `10-governance-treasury-withdrawal`: `Tx.hs` (1 deposit input, 1 change output, 1 proposal procedure), `rules.yaml` from 044 Story 10, `expected.txt`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S10_GovernanceTreasuryWithdrawal.hs`, `test/fixtures/rewrite-redesign/10-governance-treasury-withdrawal/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`.

---

## Phase 12: User Story US10 — 09-mpfs-facts-request (Priority: P2, blueprint-using)

**Goal**: MPFS facts-request with 10 chunked outputs to the oracle script, blueprint-decoded `requester` field.

- [X] T013 [US10] Ship fixture `09-mpfs-facts-request`: `Tx.hs` (1 operator input, 10 oracle-script outputs each with inline datum + 1 operator change), `rules.yaml` from 044 Story 9 referencing `blueprints/mpfs-fact.cip57.json`, `expected.txt`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S09_MpfsFactsRequest.hs`, `test/fixtures/rewrite-redesign/09-mpfs-facts-request/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`. *(No `[P]` — uses the blueprint from T003.)*

---

## Phase 13: User Story US2 — 01-amaru-treasury-swap (Priority: P1, load-bearing)

**Goal**: The load-bearing Amaru swap fixture — 33 SwapOrder inputs, blueprint-decoded `recipient` field, nested collapse with `view: omit`, cross-leaf entity identity at body-output + datum-recipient sites, asset-entity rendering.

**Independent Test**: Structural Hspec item passes — 33 inputs, 2 outputs, 1 collateral input, Plutus script witness for `amaru.swap.v2`, every input's inline datum references the swap-v2 blueprint, USDM asset class present in the output mint/value field. Turtle and text items PENDING.

- [X] T014 [US2] Ship fixture `01-amaru-treasury-swap`: `Tx.hs` (33 swap inputs, 2 outputs, 1 collateral, Plutus witness, per-input inline datums decoding `SwapOrder { recipient = … }`), `rules.yaml` from 044 Story 1 (the load-bearing rule set with `entities:`, `blueprints:`, and the `SwapOrderInput` nested-collapse), `expected.txt`. Files: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S01_AmaruTreasurySwap.hs`, `test/fixtures/rewrite-redesign/01-amaru-treasury-swap/{rules.yaml,expected.txt}`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs`, `cardano-tx-tools.cabal`. *(No `[P]` — relies on T003 blueprints, T011 mint/spend helpers, T010 collateral pattern.)*

**Checkpoint**: All ten A-side fixtures landed. `RewriteRedesignGoldens` reports 30 examples: 10 active structural items PASS, 20 PENDING. `./gate.sh` green.

---

## Phase 14: B-side — pin `expected.ttl` per fixture (post-kmaps#53 Phase A signal)

**Purpose**: Add the Turtle golden for each fixture using the URIs published by kmaps#53 Phase A.

**⚠️ BLOCKED**: Every task in this phase is blocked until `/tmp/epic-046/tx-45/answers/A-NNN-kmaps-phase-a.md` exists with the published URI map. See `contracts/kmaps-signal.md`. Tasks in this phase may run [P] once the signal arrives — each `expected.ttl` is in its own directory and is independent.

- [X] T015 [P] [US3] Add `02-alice-bob-ada/expected.ttl` pinned to kmaps#53 Phase A vocab; extend the structural Hspec item to additionally parse `expected.ttl` as well-formed Turtle. Files: `test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.ttl`, `test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs` (optional shared Turtle-parse helper).
- [X] T016 [P] [US4] Add `03-multi-asset-transfer/expected.ttl`. Files: `test/fixtures/rewrite-redesign/03-multi-asset-transfer/expected.ttl`.
- [X] T017 [P] [US6] Add `05-withdrawal-script-stake/expected.ttl`. Files: `test/fixtures/rewrite-redesign/05-withdrawal-script-stake/expected.ttl`.
- [X] T018 [P] [US7] Add `06-stake-pool-delegation/expected.ttl`. Files: `test/fixtures/rewrite-redesign/06-stake-pool-delegation/expected.ttl`.
- [X] T019 [P] [US8] Add `07-vote-delegation/expected.ttl`. Files: `test/fixtures/rewrite-redesign/07-vote-delegation/expected.ttl`.
- [X] T020 [P] [US9] Add `08-contingency-disburse/expected.ttl`. Files: `test/fixtures/rewrite-redesign/08-contingency-disburse/expected.ttl`.
- [X] T021 [P] [US5] Add `04-mint-spend-script-overlap/expected.ttl`. Files: `test/fixtures/rewrite-redesign/04-mint-spend-script-overlap/expected.ttl`.
- [ ] T022 [P] [US11] Add `10-governance-treasury-withdrawal/expected.ttl`. Files: `test/fixtures/rewrite-redesign/10-governance-treasury-withdrawal/expected.ttl`.
- [ ] T023 [P] [US10] Add `09-mpfs-facts-request/expected.ttl` referencing the mpfs-fact blueprint property URIs. Files: `test/fixtures/rewrite-redesign/09-mpfs-facts-request/expected.ttl`.
- [ ] T024 [P] [US2] Add `01-amaru-treasury-swap/expected.ttl` referencing the swap-v2 blueprint property URIs + the nested-collapse rules' entity triples. Files: `test/fixtures/rewrite-redesign/01-amaru-treasury-swap/expected.ttl`.

**Checkpoint**: Every fixture directory holds `expected.ttl` pinned to Phase A URIs. The structural items now actively parse it. Turtle byte-equivalence + text byte-equivalence items remain PENDING (gated on #47 / #51).

---

## Phase 15: Polish & Finalization

**Purpose**: Documentation alignment, PR-body sync, drop `gate.sh`, mark PR ready.

- [ ] T025 Sync `README.md`, `CHANGELOG.md`, and `docs/` with the harness. Add a paragraph in `README.md` pointing at `specs/033-rewrite-redesign-harness/quickstart.md`. Files: `README.md`, `CHANGELOG.md`, `docs/`.
- [ ] T026 Drop `gate.sh` in a final `chore: drop gate.sh (ready for review)` commit and mark PR #55 ready via `gh pr ready 55`. Files: `gate.sh` (removed).

---

## Slice details (subagent briefs)

Each slice below is the orchestrator's pre-baked subagent brief. The orchestrator dispatches one subagent per slice, tails `WIP.md`, and on return reviews + amends with the matching `tasks.md` checkbox.

### S1 / T001 — scaffold goldens suite

- **RED**: `RewriteRedesignGoldenSpec` does not exist; `test/unit-main.hs` does not import it; the cabal `unit-tests` does not list it. Build fails because the new spec module is referenced from `unit-main.hs` but not yet on disk.
- **GREEN**: create the module with an empty `fixtureRegistry`; the `spec` function emits one `describe "RewriteRedesignGoldens"` block with zero items (or one trivial item: "registry is consistent" that always passes); wire into `unit-main.hs`; add to cabal `other-modules`; add `test/fixtures/rewrite-redesign` to `hs-source-dirs`.
- **Subject**: `chore(045): scaffold RewriteRedesignGoldenSpec + wire into unit-tests`

### S2 / T002 — builder helpers

- **RED**: a small `HelpersSpec.hs` (or inline check in `RewriteRedesignGoldenSpec`) asserts `mkTx { txInputs = [] }` returns a `Tx ConwayEra` with `ConwayEra` era and zero inputs — fails because the module does not exist.
- **GREEN**: implement `Fixtures.RewriteRedesign.Helpers` per `data-model.md`. Export `mkTx`, address bech32 constants, smart constructors, `ExpectedShape`/`baseShape`, `assertShape`.
- **Subject**: `test(045): builder helpers for rewrite-redesign fixtures`

### S3 / T003 — CIP-57 blueprints

- **RED**: `RewriteRedesignGoldenSpec` is extended with a `describe "blueprints"` block asserting both files exist and parse as JSON — fails because the files are absent.
- **GREEN**: hand-author both minimal CIP-57 documents; the block now passes.
- **Subject**: `test(045): CIP-57 blueprints — swap-v2-datum + mpfs-fact`

### S4 / T004 — YAML parser extension (conditional)

- **DECISION GATE**: dispatched only after T005 reveals the existing parser cannot accept the 044 YAML form used by the first fixture. If `parseRewriteRulesYaml` already accepts it, **drop this task and update `tasks.md` accordingly**.
- **RED**: a new spec in `LoadSpec.hs` parses the 044 entity-sugar YAML and asserts it round-trips to an `entities:` AST — fails because the parser ignores `entities:`.
- **GREEN**: extend the parser additively; preserve every existing parse outcome (the existing `LoadSpec` items remain green).
- **Subject**: `feat(rewrite): extend parseRewriteRulesYaml for 045 entity/blueprint sugars`

### S5..S14 / T005..T014 — per-fixture slices

Each slice has the same shape:

- **RED**: append the fixture's `FixtureEntry` to `fixtureRegistry` with the new `feShape` value, then the new `describe` block fails because the fixture module / files do not exist (compile error on the `Fixtures.RewriteRedesign.S<NN>_…` import).
- **GREEN**: write `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S<NN>_<CamelCaseSlug>.hs` exporting `storyId :: StoryId`, `tx :: ConwayTx`, and `shape :: ExpectedShape` matching the 044 narrative; drop `rules.yaml` and `expected.txt` (canon-stripped) into the sibling kebab data-file directory `test/fixtures/rewrite-redesign/<NN>-<kebab-slug>/`; add the cabal `other-modules` entry; the structural Hspec item now PASSES, two pending items PENDING.
- **`./gate.sh`** must be green at HEAD.
- **Subject**: `test(045): fixture <NN-story-id>`
- **Owned files** per slice: the fixture's Haskell module under `Fixtures/RewriteRedesign/`, the fixture's kebab data-file directory (only `rules.yaml` + `expected.txt` in A-side), the cabal entry for that fixture's module, and the registry-list edit in `RewriteRedesignGoldenSpec`. No edits to other fixtures, helpers, or blueprints (those are foundational and already present).
- **Forbidden scope**: `specs/`, `gate.sh`, `Helpers.hs`, `blueprints/`, `src/Cardano/Tx/Rewrite.hs`, any other fixture's directory or Haskell module, PR/issue metadata.

### S15..S24 / T015..T024 — post-signal `expected.ttl` slices

- **Pre-flight**: read `/tmp/epic-046/tx-45/answers/A-NNN-kmaps-phase-a.md` for the URI map. If absent, log `BLOCKED Q-NNN-kmaps-phase-a-pending` to STATUS.md and poll until it appears.
- **RED**: extend the fixture's structural Hspec item to additionally `BS.readFile` and Turtle-parse `expected.ttl` — fails because the file is absent or uses wrong URIs.
- **GREEN**: hand-author the Turtle file pinned to the published URI set; structural item parses it; Turtle byte-equivalence + text byte-equivalence remain PENDING.
- **`./gate.sh`** green.
- **Subject**: `test(045): pin <NN-story-id> expected.ttl to kmaps#53 Phase A vocab`
- **Owned files**: the fixture directory's `expected.ttl` and (for the first B-side slice only) the optional shared Turtle-parse helper in `RewriteRedesignGoldenSpec`.

### S25 / T025 — docs sync

- **GREEN**: README + CHANGELOG + docs reference the harness and the quickstart. Orchestrator-owned non-behavioural slice; no subagent dispatch needed.
- **Subject**: `docs(045): sync README/CHANGELOG/docs with harness`

### S26 / T026 — drop gate.sh

- **GREEN**: `git rm gate.sh` in a dedicated commit; `gh pr ready 55`.
- **Subject**: `chore: drop gate.sh (ready for review)`

---

## Dependencies

```text
T001  scaffold suite
 │
 ├─► T002  helpers
 │    │
 │    ├─► T005..T009, T012  (fixtures without blueprints / overlap / collateral)
 │    │
 │    └─► T003  blueprints
 │         │
 │         ├─► T013  09-mpfs-facts-request
 │         │
 │         └─► T010  08-contingency-disburse
 │              │
 │              └─► T011  04-mint-spend-script-overlap
 │                   │
 │                   └─► T014  01-amaru-treasury-swap
 │
 └─► T004  YAML parser extension (conditional; first triggered by T005)


T005..T014  ─────────►  (kmaps#53 Phase A signal)  ─────────►  T015..T024


T015..T024  ─►  T025  ─►  T026  ─►  PR ready
```

A-side dispatch order: T001 → T002 → T003 → T005 → (decide T004) → T006 → T007 → T008 → T009 → T012 → T010 → T011 → T013 → T014.

Within each `[P]` cluster, slices can be dispatched sequentially per resolve-ticket's "one subagent at a time" default unless the orchestrator explicitly parallelises and the user authorises it.

---

## Implementation strategy

- **MVP for this harness PR**: T001..T003 + T005 + T014 + (post-signal) T024 + T025 + T026. That ships the suite, the helpers, the blueprints, the simplest fixture, the load-bearing P1 fixture, the load-bearing P1 fixture's `expected.ttl`, the docs, and PR ready. The other eight fixtures are landed as the same shape, replicated.
- **A-side is independent of kmaps#53**: every A-side task ships its commit and `./gate.sh` is green at HEAD. The PR is mergeable as A-side-only if kmaps#53 Phase A does not land in time (B-side reserves the structural slots; pending markers preserve the contract).
- **B-side is mechanical**: the URI map from the kmaps#53 signal turns each `expected.ttl` into a copy-paste job from a single template.
- **No premature parallelism**: dispatch one subagent at a time per resolve-ticket; revisit only if the user explicitly authorises parallel A-side dispatch.

---

## Resolve-ticket invariants

- Every commit closing a behaviour-changing slice carries `Tasks: T###` in its body trailer.
- The corresponding checkbox above is checked in the same amended slice commit (orchestrator amends HEAD after review).
- `./gate.sh` is green at HEAD after every slice.
- Slices already accepted (pushed + checkbox checked) are frozen. Corrections come via forward commits (`fix(rebase): …` or `chore(045): correct …`), not re-edits of accepted slices.
- The orchestrator does not run `speckit-implement`. Each slice is dispatched as a fresh subagent with the brief baked above.

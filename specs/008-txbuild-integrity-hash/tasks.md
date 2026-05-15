---
description: "Tasks for cardano-tx-tools#8 — TxBuild self-validates against ledger Phase-1"
---

# Tasks: TxBuild self-validates against ledger Phase-1

**Input**: Design documents in `/specs/008-txbuild-integrity-hash/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[contracts/txbuild-self-validation.md](./contracts/txbuild-self-validation.md),
[quickstart.md](./quickstart.md)

**Constitutional discipline (Principle VII)**: each behavior
change ships as ONE commit with RED test and GREEN
implementation folded together. No "added tests" follow-up
commits. Every commit on `main` must compile, test green, and
be bisect-safe.

**Organization**: tasks are grouped by user story (US1, US2)
from [spec.md](./spec.md). Each user story is independently
testable per the spec's "Independent Test" criteria.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: parallelizable (different files, no incomplete-task
  dependencies)
- **[Story]**: which user story this task belongs to (US1 / US2)
- Each task names exact file paths

---

## Phase 1: Setup — Resolve any remaining open research items

**Purpose**: ensure every research entry in
[research.md](./research.md) reads RESOLVED or DEFERRED.
At the time of writing all six are closed. This phase exists
as a gate for the per-PR contract; if a research item
re-opens (e.g. user surfaces new info), it gets closed here.

- [ ] T001 Re-read [research.md](./research.md) and confirm
  R-001…R-006 are RESOLVED / DEFERRED with the same
  decisions as the Summary section. If any item has changed
  since the spec moved repos, update it and re-summarize.

**Checkpoint**: no OPEN research items.

---

## Phase 2: Foundational — test fixture infrastructure

**Purpose**: shared scaffolding both user stories need.
Blocks Phase 3. Per constitution VI, all fixtures live on
disk and ship in `test/fixtures/`.

- [ ] T002 Copy `/code/cancel.cbor.hex` to
  `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex`.
  This is the failing tx body
  (`84b2bb78f7f5dd2beb2830e8e6e88fd853a8f70ea73b161f0a0327de8c70146f`)
  carrying the wrong `script_integrity_hash` `03e9d7ed…1941`
  at CBOR key `0b`. Single commit:
  `test(008): swap-cancel reproduction body fixture`.
- [ ] T003 Capture the 3 inputs the failing body references
  (`59e10ca5e03b8d243c699fc45e1e18a2a825e2a09c5efa6954aec820a4d64dfe#0`,
  `…#2`, and reference input
  `f5f1bdfad3eb4d67d2fc36f36f47fc2938cf6f001689184ab320735a28642cf2#0`)
  from mainnet via this repo's own resolvers (LSQ N2C
  against a mainnet socket — **never Blockfrost**, per memory
  `feedback_fix_own_tools`). Write the resolved UTxO map to
  `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/utxo.json`.
  This is a one-off capture; the file is committed and the
  test reads it offline. Single commit:
  `test(008): swap-cancel UTxO fixture`.
- [ ] T004 Verify the committed `test/fixtures/pparams.json`
  is consistent with the failing tx's slot (T011 will
  enforce this empirically). If not, recapture via the same
  LSQ N2C path and replace the file in this commit. Single
  commit (only if recapture is needed):
  `test(008): refresh PParams snapshot for issue #8 slot`.
- [ ] T005 [P] Add helpers `loadPParams`, `loadUtxo`,
  `loadBody`, `loadPlan` to `test/Cardano/Tx/BuildSpec.hs`
  (new file). Single commit:
  `test(008): add fixture loaders for swap-cancel reproduction`.

**Checkpoint**: fixture files committed; loader helpers in
place; no source change yet.

---

## Phase 3: User Story 1 — TxBuild refuses Phase-1-invalid bodies (P1) 🎯 MVP

**Goal**: per [spec.md](./spec.md) US1 — the build call
self-validates and returns an error rather than an invalid
body.

**Independent Test**: per [spec.md](./spec.md) US1 —
fixture-driven; build the swap-cancel plan, assert `Right
body`, `scriptIntegrityHashTxBodyL == SJust 41a7cd57…dcf9`,
`applyTx pp utxo slot body == Right _`.

### Commits for US1 (RED + GREEN per commit)

- [ ] T006 [US1] **Commit: hash-fix** — single commit
  bundling RED (failing golden assertion) + GREEN (signature
  + impl change). Order inside the commit doesn't matter
  for bisect; what matters is that the commit compiles and
  tests pass at HEAD. Concretely:
  - In `src/Cardano/Tx/Scripts.hs`: update
    `computeScriptIntegrity` per
    [data-model.md](./data-model.md) E-4 — accept
    `Set Language` and `TxDats ConwayEra`, fold all
    requested language views; add helper
    `languagesUsedInBody` per E-3.
  - In `src/Cardano/Tx/Build.hs`: update the three call
    sites (lines 1043, 1289, 1775) to feed the body-derived
    language set and witness-set datums.
  - In `test/Cardano/Tx/BuildSpec.hs`: add the swap-cancel
    integrity-hash golden per
    [quickstart.md](./quickstart.md) §2 — assert
    `body ^. scriptIntegrityHashTxBodyL ==
    SJust 41a7cd57…dcf9`.
  - Commit message:
    `fix(008): hash redeemers and language views over Conway body`.
- [ ] T007 [US1] **Commit: LedgerCheck extension + PParamsBound** —
  single commit, foundation for the self-validation hook.
  - In `src/Cardano/Tx/Build.hs`: parameterize `Check` and
    `LedgerCheck` over `era`; add `Phase1Rejected
    (ApplyTxError era)` constructor per
    [data-model.md](./data-model.md) E-2. Existing
    constructors retained.
  - Add `PParamsBound era` newtype per
    [data-model.md](./data-model.md) E-1; thread it through
    `buildWith` and downstream helpers; unwrap only at leaf
    consumers that need raw `PParams` (`estimateMinFeeTx`,
    `computeScriptIntegrity` once that helper accepts the
    wrapper, the future `applyTx` call).
  - No new test in this commit — the type change does not
    yet exercise self-validation; existing tests stay
    green.
  - Commit message:
    `refactor(008): extend LedgerCheck with Phase1Rejected; introduce PParamsBound`.
- [ ] T008 [US1] **Commit: self-validation hook** — single
  commit; the GREEN flip for the negative test.
  - In `src/Cardano/Tx/Build.hs`: at the return point in
    `buildWith` (currently line 1569 `Right balanced`),
    call `Cardano.Ledger.Api.Tx.applyTx` against the body,
    using the combined UTxO (`inputUtxos ∪
    boCollateralUtxos opts ∪ refUtxos`) and the same
    `PParamsBound`. On `Left e`, return
    `Left (LedgerFail (Phase1Rejected e))`; otherwise return
    the body.
  - Add the swap-cancel Phase-1 assertion per
    [quickstart.md](./quickstart.md) §2 ("passes ledger
    Phase-1") and the negative-build test per §3 (forced
    invalid plan ⇒ `Left (LedgerFail (Phase1Rejected _))`)
    to `test/Cardano/Tx/BuildSpec.hs`.
  - Commit message:
    `fix(008): self-validate every built body via ledger Phase-1`.
- [ ] T009 [US1] **Commit: edge-case property test** —
  single commit. Adds a `hspec`-quickcheck property in
  `test/Cardano/Tx/BuildSpec.hs` covering the spec's "Edge
  Cases" list (no Plutus inputs, mixed Plutus versions,
  inline-datum empty witness-set datums, stake/cert-only
  tx). Commit message:
  `test(008): property coverage for self-validation edge cases`.

**Checkpoint**: US1 fully delivered. Build calls return
ledger-valid bodies or `LedgerFail` errors; the swap-cancel
reproduction matches the ledger's expected hash;
`nix flake check` passes.

---

## Phase 4: User Story 2 — close downstream duplicate-gate ticket (P1)

**Goal**: per [spec.md](./spec.md) US2 / FR-008 — the
companion `amaru-treasury-tx` ticket is closed as superseded;
no consumer carries a duplicate Phase-1 gate.

**Independent Test**: per [spec.md](./spec.md) US2 — a grep
across consumers (starting with `amaru-treasury-tx`) finds
zero post-TxBuild Phase-1 gates; the companion ticket is
closed with a backlink.

### Tasks for US2

- [ ] T010 [US2] Locate the companion ticket on
  `lambdasistemi/amaru-treasury-tx` and add its URL to the
  PR description.
- [ ] T011 [US2] Run the verification grep from
  [quickstart.md](./quickstart.md) §4 across
  `amaru-treasury-tx` and any other known
  `Cardano.Tx.Build` consumer. Record findings (a) in the
  PR description (consumer list confirmed clean), and (b) as
  a comment on the companion ticket.
- [ ] T012 [US2] Close the companion ticket as superseded
  with a reference to this PR — only after Phase 3 has
  merged and the consumer grep returned clean. Coordinate
  with user before closing per memory
  `feedback_no_push_upstream`.

**Checkpoint**: US2 fully delivered. The class of bug that
motivated this work cannot recur via a missing consumer
gate, because the consumer gate is gone.

---

## Phase 5: Polish

- [ ] T013 [P] Update Haddock on
  `Cardano.Tx.Scripts.computeScriptIntegrity` and the new
  `languagesUsedInBody` to describe the body-derivation
  rule and the chosen hash function. Single commit:
  `docs(008): Haddock for new Scripts.hs contract`.
- [ ] T014 [P] Update Haddock on `LedgerCheck`,
  `PParamsBound`, and the `Cardano.Tx.Build` build entry
  point to describe the Phase-1 self-validation contract
  and `Phase1Rejected`. Single commit:
  `docs(008): Haddock for new Build.hs contract`.
- [ ] T015 Refresh the PR description with the
  implementation summary (modules touched, tests added,
  fixture paths, link to companion-ticket closure). Memory
  `feedback_update_pr_description`.
- [ ] T016 Run `nix flake check --no-eval-cache` locally
  (memory `feedback_always_local_ci`) and confirm green.
  Push, mark the PR ready for review.
- [ ] T017 Confirm the auto-generated `CLAUDE.md` line for
  this feature is correct (added by
  `.specify/scripts/bash/update-agent-context.sh claude`).

---

## Dependencies

```text
Phase 1 (T001)  ──►  Phase 2 (T002-T005)  ──►  Phase 3 (T006-T009)
                                                          │
                                                          ▼
                                                Phase 4 (T010-T012)
                                                          │
                                                          ▼
                                                Phase 5 (T013-T017)
```

- Phase 2: T002, T003, T004 are sequential (each commits a
  different fixture). T005 [P] starts as soon as T002 lands.
- Phase 3: T006 → T007 → T008 → T009 in order. Each commit
  compiles and passes its own tests. T007 is the *only*
  commit that adds the type parameter without changing
  behavior — its tests are the existing tests; it must not
  regress them.
- Phase 4: starts only after Phase 3 has merged to main
  (consumer-grep makes no sense before the fix lands).
- Phase 5: T013/T014 can interleave; T015/T016 are the
  release gate.

---

## Implementation strategy

- **MVP** = Phase 3 (US1) only. The build self-validates,
  the swap-cancel reproduction is GREEN, and the bug is
  closed at the TxBuild layer. Even without Phase 4 /
  Phase 5, the original issue is resolved.
- **Constitution VII (RED+GREEN per commit)**: every
  behavior-changing commit in Phase 3 carries both the test
  and the implementation. T007 is a type-only refactor
  (extension), so its "tests" are the existing tests
  staying green — that is the bisect-safety guarantee.
- **Vertical commits** (memory
  `feedback_vertical_commits`): one commit per meaningful
  unit. T006/T007/T008/T009 are four such units, each
  reviewable independently.
- **Bisect-safe** (memory
  `feedback_bisect_safe_commits`): every commit compiles
  and `nix flake check` passes at HEAD of each commit.

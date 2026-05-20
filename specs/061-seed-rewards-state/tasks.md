# Tasks: tx-validate reward state seeding

**Input**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/json-output.md](./contracts/json-output.md), [quickstart.md](./quickstart.md)

**Execution model**: visible tmux-hosted Codex workers. One implementation worker run produces exactly one bisect-safe commit. The orchestrator owns `specs/`, `gate.sh`, PR metadata, task checkbox stamping, and final verification.

**TDD discipline**: each behavior-changing task below includes RED and GREEN in the same reviewed commit. The worker must watch the focused test fail before changing production code.

## Phase 1: Implementation Slices

### User Story 1 - Validate a registered withdraw-zero transaction (Priority: P1)

**Goal**: a reward account returned by the provider, including `Coin 0`, exists in the seeded Conway cert state so `WithdrawalsNotInRewardsCERTS` is not a false positive.

**Independent Test**: a withdrawal fixture run with an empty reward map produces `WithdrawalsNotInRewardsCERTS`; the same fixture run with the account mapped to `Coin 0` no longer produces that failure.

- [ ] T001 [US1] Add reward-aware pure validation in `src/Cardano/Tx/Validate.hs` and regression coverage in `test/Cardano/Tx/ValidateSpec.hs`

**Subagent brief for T001**:

- Worker model: slice executor.
- Owned files: `src/Cardano/Tx/Validate.hs`, `test/Cardano/Tx/ValidateSpec.hs`.
- Forbidden scope: `specs/`, `gate.sh`, `app/tx-validate/Main.hs`, `src/Cardano/Tx/Validate/Cli.hs`, PR metadata, unrelated tests.
- Required facts: keep `validatePhase1` source-compatible as a wrapper; add a reward-aware entry point that accepts `Map AccountAddress Coin`; use Conway account APIs from research.md R2; do not use queried reward balances as the `mkConwayAccountState` deposit argument without setting `balanceAccountStateL`.
- RED proof: add a focused test based on the synthetic withdrawal fixture (`Fixtures.RewriteRedesign.S05_WithdrawalScriptStake.tx`) showing empty reward accounts produce `WithdrawalsNotInRewardsCERTS`, and the registered `Coin 0` case fails before production changes.
- GREEN proof: the focused `Cardano.Tx.Validate` test passes after seeding returned accounts; `./gate.sh` passes.
- Commit subject: `fix(validate): seed reward accounts for withdrawals`.
- Commit body: non-empty and includes `Tasks: T001`.

---

### User Stories 1, 2, and 3 - CLI query and provenance (Priority: P1/P2)

**Goal**: `tx-validate` obtains reward accounts from N2C only when withdrawals exist, passes them to the pure validator, preserves true unregistered-account failures, and records JSON provenance.

**Independent Test**: CLI-style tests with a stub provider show registered withdrawal accounts avoid the false CERTS failure, unregistered accounts still fail, no-withdrawal human output remains stable, and JSON contains `reward_accounts_source`.

- [ ] T002 [US1] Wire N2C reward-account lookup, session/verdict provenance, and CLI tests in `app/tx-validate/Main.hs`, `src/Cardano/Tx/Validate/Cli.hs`, and `test/Cardano/Tx/Validate/CliSpec.hs`

**Subagent brief for T002**:

- Worker model: slice executor.
- Owned files: `app/tx-validate/Main.hs`, `src/Cardano/Tx/Validate/Cli.hs`, `test/Cardano/Tx/Validate/CliSpec.hs`.
- Forbidden scope: `specs/`, `gate.sh`, `src/Cardano/Tx/Validate.hs` except imports/types already delivered by T001, PR metadata, unrelated release plumbing.
- Required facts: collect withdrawal accounts from the decoded tx body; skip provider reward lookup if withdrawals are empty; use `Provider.queryRewardAccounts`; pass returned accounts into the reward-aware validator; render JSON field `reward_accounts_source` as `"n2c"` or `"not_required"`; keep human output unchanged.
- RED proof: add focused tests that fail before wiring/provenance changes: registered withdrawal through a stub provider still contains `WithdrawalsNotInRewardsCERTS`, JSON lacks `reward_accounts_source`, and no-withdrawal output remains the current human string.
- GREEN proof: focused `Cardano.Tx.Validate.Cli` tests pass after wiring; `./gate.sh` passes.
- Commit subject: `fix(tx-validate): query reward accounts from n2c`.
- Commit body: non-empty and includes `Tasks: T002`.

---

## Phase 2: Operator Follow-Up And Finalization

- [ ] T003 Record the issue #61 live-mainnet smoke status in PR #62 using the command from `specs/061-seed-rewards-state/quickstart.md`
- [ ] T004 Run final `./gate.sh`, update PR #62 with final verification and artifact links, then remove `gate.sh` in the ready-for-review commit

## Dependencies & Execution Order

### Phase Dependencies

- **T001** has no code dependency beyond the existing repo.
- **T002** depends on T001's reward-aware pure validator API.
- **T003** depends on T002 because the live smoke must run the fixed CLI path.
- **T004** depends on T001-T003.

### Parallel Opportunities

None for implementation. T001 and T002 touch dependent APIs and should run sequentially. T003 is an operator/orchestrator follow-up.

## Implementation Strategy

1. Dispatch T001 to a tmux Codex worker; review the commit, rerun `./gate.sh`, stamp T001 in this file by amending the worker commit.
2. Dispatch T002 to a tmux Codex worker; review the commit, rerun `./gate.sh`, stamp T002 in this file by amending the worker commit.
3. Complete T003 directly as orchestrator metadata work.
4. Complete T004 after all checkboxes are closed.

## Notes

- Do not filter `WithdrawalsNotInRewardsCERTS`.
- Do not make CI depend on a live mainnet socket.
- Do not commit the issue #61 signed transaction unless the operator explicitly approves it.

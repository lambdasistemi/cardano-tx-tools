# Implementation Plan: tx-validate reward state seeding

**Branch**: `061-seed-rewards-state` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/061-seed-rewards-state/spec.md`

## Summary

`tx-validate` currently seeds Conway `applyTx` with pparams and UTxO only, leaving reward/cert state empty. Transactions with withdrawals therefore fail the CERTS rule even when the referenced reward accounts are registered on the queried node. The fix adds a reward-account seeding path: collect withdrawal accounts, query them through the existing N2C `Provider`, seed only returned accounts into the synthetic Conway validation state, and expose reward provenance in JSON. `WithdrawalsNotInRewardsCERTS` remains a real structural failure for accounts absent from the live query.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix`
**Primary Dependencies**: existing `cardano-ledger-*`, `cardano-node-clients`, `microlens`, `containers`, `aeson`
**Storage**: N/A
**Testing**: Hspec through `unit-tests`, full gate via `nix flake check --no-eval-cache`
**Target Platform**: Linux/macOS CLI, Conway-only ledger validation
**Project Type**: Haskell library plus CLI executable
**Performance Goals**: one batched reward-account query per transaction with withdrawals; no reward query for transactions without withdrawals
**Constraints**: default-offline CI; N2C remains explicit opt-in; no Blockfrost work; no masking of ledger failures
**Scale/Scope**: one bug-fix PR touching the validator core, tx-validate session/verdict plumbing, and tests

## Constitution Check

- **One-way dependency on node-clients**: pass. The main library stays node-client-free; N2C querying remains in `app/tx-validate/Main.hs` and tests use provider-shaped stubs.
- **Module namespace discipline**: pass. No new namespace outside `Cardano.Tx.*`.
- **Conway-only era**: pass. All touched ledger types remain `ConwayEra`.
- **Hackage-ready quality**: pass by plan. Any exported function added to `Cardano.Tx.Validate` gets Haddock; `./gate.sh` includes lint/checks.
- **Strict warnings**: pass by plan. Worker gate includes `nix flake check --no-eval-cache`.
- **Default-offline semantics**: pass. Unit tests use mocked provider/reward maps; live mainnet proof is an operator follow-up, not CI.
- **TDD with vertical bisect-safe commits**: pass by plan. Each worker slice includes RED evidence and one bisect-safe commit.

Post-design re-check: no constitution violations introduced by the selected design.

## Project Structure

### Documentation (this feature)

```text
specs/061-seed-rewards-state/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── json-output.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
src/Cardano/Tx/Validate.hs
src/Cardano/Tx/Validate/Cli.hs
app/tx-validate/Main.hs
test/Cardano/Tx/ValidateSpec.hs
test/Cardano/Tx/Validate/CliSpec.hs
test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S05_WithdrawalScriptStake.hs
test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/Helpers.hs
```

**Structure Decision**: extend the existing validator and tx-validate CLI modules in place. Reuse the existing synthetic withdrawal fixture (`S05_WithdrawalScriptStake`) for offline RED/GREEN coverage rather than committing the production Amaru treasury transaction.

## Phase 0 - Research

Resolved in [research.md](./research.md):

1. Pure validator API shape for reward-account state.
2. Conway account-state seeding API and the `mkConwayAccountState` balance/deposit trap.
3. N2C reward-account query source and provenance contract.
4. Live-boundary proof strategy.

## Phase 1 - Design & Contracts

### Data Model

See [data-model.md](./data-model.md). The core entities are:

- `RewardAccounts`: queried `Map AccountAddress Coin`.
- `RewardAccountSource`: `RewardAccountsN2C | RewardAccountsNotRequired`.
- `Session`: gains reward-account state/provenance for one invocation.
- `Verdict`: gains JSON-visible reward provenance.

### JSON Contract

See [contracts/json-output.md](./contracts/json-output.md). The existing JSON envelope gains:

```json
"reward_accounts_source": "n2c" | "not_required"
```

No human-output change is planned.

### Live-Boundary Diagnostic

Question: what system boundary does this exercise that the unit suite cannot?

Answer: the production boundary is the N2C LocalStateQuery reward-account query against a live node. Offline unit tests can prove that returned reward accounts are seeded correctly and absent accounts remain absent; they cannot prove a given mainnet socket returns the expected issue #61 account at a particular tip.

Decision: keep `./gate.sh` offline and require an operator follow-up before ready-for-review when a live mainnet socket and the issue transaction are available. The follow-up command is documented in [quickstart.md](./quickstart.md) and the PR body must record either the transcript or the reason the production artifact could not be run. This avoids making CI depend on `/code/cardano-mainnet/ipc/node.socket`.

## Orchestrator / Worker Split

The orchestrator owns all files under `specs/061-seed-rewards-state/`, `gate.sh`, PR metadata, and final verification. Implementation uses visible tmux-hosted Codex workers, one worker per slice, with STATUS.md/Q-file supervision and one bisect-safe commit per run.

## Vertical Slice Plan

### Slice A - Pure Validator Reward Seeding

Owned files:

- `src/Cardano/Tx/Validate.hs`
- `test/Cardano/Tx/ValidateSpec.hs`

Behavior:

- Add a pure validation entry point that accepts `Map AccountAddress Coin` reward accounts.
- Keep existing `validatePhase1` as a wrapper with no reward accounts so existing callers compile unchanged.
- Seed returned accounts into the Conway cert state before `applyTx`.
- RED proof: a withdrawal fixture with an empty reward map contains `WithdrawalsNotInRewardsCERTS`; the same fixture with the account mapped to `Coin 0` no longer contains that failure.
- GREEN proof: focused unit test plus `./gate.sh`.

### Slice B - tx-validate N2C Query + JSON Provenance

Owned files:

- `src/Cardano/Tx/Validate/Cli.hs`
- `app/tx-validate/Main.hs`
- `test/Cardano/Tx/Validate/CliSpec.hs`

Behavior:

- Collect withdrawal reward accounts from the decoded tx body.
- Skip reward lookup when withdrawals are empty.
- Query `Provider.queryRewardAccounts` for non-empty withdrawals and store returned accounts in `Session`.
- Call the new pure validation entry point with the session reward accounts.
- Add `reward_accounts_source` to JSON output while keeping human output stable.
- RED proof: CLI-style test with a withdrawal fixture and stub provider fails before Main/session plumbing supplies reward accounts; JSON lacks the new field before renderer changes.
- GREEN proof: focused tx-validate CLI unit tests plus `./gate.sh`.

### Slice C - Operator Docs And Final Metadata

Owned files:

- `specs/061-seed-rewards-state/quickstart.md`
- PR body only

Behavior:

- Ensure the operator smoke command and expected artifact are documented.
- Record live-smoke status in the PR body before marking ready.
- This is orchestrator-owned non-code work; no implementation worker needed.

## Risk And Mitigation

- **Deposit-sensitive certificate behavior**: `Provider.queryRewardAccounts` returns reward balances, not registration deposits. The fix targets withdrawal membership/balance checks only and seeds accounts with zero deposit unless a future provider surface supplies deposits. Tests cover withdrawal failures, not deregistration/deposit accounting.
- **JSON compatibility**: adding a top-level JSON field is backward-compatible for consumers that ignore unknown fields; tests lock the new field.
- **Live tip skew**: current CLI already queries pparams, slot, and UTxO through the same provider but not one exported immutable snapshot. This PR does not broaden that architecture; it adds reward accounts through the same provider path.
- **Fixture fidelity**: use the synthetic withdrawal fixture for CI; live mainnet proof remains a named operator follow-up for the exact issue #61 account.

## Complexity Tracking

No constitution violations or extra architectural complexity require justification.

# Feature Specification: tx-validate reward state seeding

**Feature Branch**: `061-seed-rewards-state`  
**Created**: 2026-05-20  
**Status**: Draft  
**Input**: GitHub issue #61 reports that `tx-validate` returns a false `WithdrawalsNotInRewardsCERTS` failure for a signed Amaru treasury disbursement using the canonical withdraw-zero validator trigger against a reward account that is registered on the queried mainnet node.

## Background

`tx-validate` is intended to answer whether a Conway transaction has a real Phase-1 structural problem before an operator signs or submits it. For live N2C validation it already obtains protocol parameters, the tip slot, and the transaction UTxO from the queried node.

Transactions that include withdrawals need one more piece of live ledger state: the reward accounts referenced by the transaction body's withdrawals. The current validator seed leaves the rewards/cert state empty, so Conway CERTS rejects every withdrawal as if the account were absent. That is a false positive for the common withdraw-zero pattern used to run a script reward account's permissions validator.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Validate a registered withdraw-zero transaction (Priority: P1)

An operator validates a signed Conway transaction that includes a zero-coin withdrawal from a registered script reward account. The queried node reports that the account exists, even if the reward balance is zero. `tx-validate` must not fail the transaction only because its internal seeded reward state was empty.

**Why this priority**: this is the bug in issue #61 and it blocks the Amaru treasury signing workflow.

**Independent Test**: run the validation pipeline with a fixture transaction containing a withdrawal and a mocked N2C provider that reports the reward account as registered with balance `Coin 0`. Before the fix, the verdict contains `WithdrawalsNotInRewardsCERTS`; after the fix, that specific failure is absent.

**Acceptance Scenarios**:

1. **Given** a transaction whose withdrawals reference a reward account registered on the queried node with balance `Coin 0`, **When** `tx-validate` runs through the N2C path, **Then** the verdict does not include `WithdrawalsNotInRewardsCERTS` for that account.
2. **Given** the same transaction and reward account, **When** JSON output is requested, **Then** the JSON envelope still reports the existing pparams, slot, and UTxO provenance and also reports that reward account state came from N2C.
3. **Given** the same transaction but with no unrelated structural problems, **When** expected witness-completeness noise is filtered, **Then** the process exits `0`.

---

### User Story 2 - Preserve rejection for genuinely unregistered accounts (Priority: P1)

An operator validates a transaction whose withdrawals reference a reward account that is not registered in the queried ledger state. `tx-validate` must continue to surface the ledger's withdrawal failure instead of masking it.

**Why this priority**: the fix must improve state seeding, not downgrade a real ledger check into advisory output.

**Independent Test**: run the same fixture shape with a mocked provider that returns no reward-account entry for the withdrawal account. The verdict must still contain `WithdrawalsNotInRewardsCERTS`.

**Acceptance Scenarios**:

1. **Given** a transaction whose withdrawals reference an account absent from the queried node's reward account result, **When** `tx-validate` runs, **Then** the structural failure list includes the ledger's withdrawal-not-in-rewards failure.
2. **Given** JSON output is requested for the unregistered-account case, **When** the verdict is rendered, **Then** the structural failure entry still names the CERTS rule and includes the ledger detail.

---

### User Story 3 - Keep no-withdrawal transactions unchanged (Priority: P2)

A signing pipeline validates ordinary transactions with no withdrawals. The fix must not add spurious node queries, change verdict status, or change the existing human output for those transactions.

**Why this priority**: most existing `tx-validate` callers do not need reward state, and their path should stay stable.

**Independent Test**: run the existing issue-#8 tx-validate fixture with no withdrawals and assert the same verdict status and human output as before.

**Acceptance Scenarios**:

1. **Given** a transaction body with an empty withdrawals map, **When** `tx-validate` runs, **Then** validation behavior is unchanged from the current release.
2. **Given** JSON output is requested for a no-withdrawal transaction, **When** the envelope is rendered, **Then** reward-account provenance is reported as not required or is otherwise clearly absent by contract.

### Edge Cases

- A reward account is registered with a zero reward balance: this is registered state and must seed the validator with `Coin 0`.
- A withdrawal amount does not match the live reward balance: the ledger must still report the normal withdrawal/accounting failure.
- The transaction contains multiple withdrawals: all referenced reward accounts are queried and seeded independently.
- The provider cannot query reward accounts: `tx-validate` exits as a resolver/configuration error (`>=2`), not as a structural verdict.
- A transaction includes no withdrawals: reward-account lookup is skipped.
- A transaction includes stake certificates that register an account in the same transaction: the seeding source is the current ledger state before applying the transaction; same-transaction registration does not count as a pre-existing reward account.
- Tests must run offline with mocked provider state; any live mainnet check is an operator smoke, not a required unit-test dependency.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The validator path MUST identify every reward account referenced by the transaction body's withdrawals before applying the transaction.
- **FR-002**: For N2C validation, the CLI MUST query those reward accounts from the same live node source used for protocol parameters, slot, and UTxO resolution.
- **FR-003**: Registered reward accounts returned by the provider MUST be seeded into the Conway reward/cert state used by `validatePhase1`, including accounts whose balance is `Coin 0`.
- **FR-004**: Reward accounts absent from the provider result MUST remain absent from the seeded state so the ledger can still report `WithdrawalsNotInRewardsCERTS`.
- **FR-005**: The fix MUST NOT filter, suppress, or reclassify `WithdrawalsNotInRewardsCERTS`; it MUST make the seeded ledger state match the queried node closely enough that the ledger rule decides correctly.
- **FR-006**: No-withdrawal transactions MUST retain the existing validation behavior and human output.
- **FR-007**: JSON output MUST expose reward-account provenance in a stable top-level field so users can tell whether withdrawal state was sourced from N2C or was not required.
- **FR-008**: Unit tests MUST include a registered zero-balance withdrawal case and an unregistered withdrawal case using mocked provider state, without requiring network access.
- **FR-009**: The branch MUST pass `./gate.sh`, which runs `git diff --check` and `nix flake check --no-eval-cache`.
- **FR-010**: Haddock or nearby CLI documentation MUST explain that `tx-validate` validates withdrawals against queried reward-account state, not an empty synthetic cert state.

### Key Entities

- **Withdrawal reward account**: an `AccountAddress` present in the transaction body's withdrawals map.
- **Reward account lookup result**: the provider's mapping from withdrawal reward accounts to live reward balances.
- **Seeded validation state**: the `NewEpochState` supplied to Conway `applyTx`, populated with pparams, UTxO, and the queried reward accounts.
- **Reward provenance**: a user-visible JSON indicator of whether reward account state was queried from N2C or not needed for this transaction.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A registered zero-balance withdrawal fixture no longer reports `WithdrawalsNotInRewardsCERTS` after expected witness-completeness noise is filtered.
- **SC-002**: An unregistered withdrawal fixture still reports `WithdrawalsNotInRewardsCERTS`.
- **SC-003**: Existing no-withdrawal tx-validate tests continue to pass without changed human output expectations.
- **SC-004**: JSON output for a withdrawal transaction includes reward provenance showing `n2c`.
- **SC-005**: `./gate.sh` exits `0` on the completed branch.

## Assumptions

- `cardano-node-clients`'s `Provider.queryRewardAccounts` is the intended N2C surface for reward account lookup.
- The implementation can remain Conway-only, matching the repository constitution.
- The issue #61 production transaction may not be committed as a fixture if it is operationally sensitive; an equivalent synthetic or existing fixture is acceptable if it exercises the same withdrawal rule.
- Live mainnet smoke can be documented as an optional operator follow-up because local CI must remain offline.

## Out of Scope

- Masking or downgrading `WithdrawalsNotInRewardsCERTS`.
- Blockfrost reward-account lookup; this PR remains N2C-only like the current `tx-validate` surface.
- Phase-2 script execution validation.
- Non-Conway eras.

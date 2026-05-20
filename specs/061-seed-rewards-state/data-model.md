# Data Model: tx-validate reward state seeding

**Feature**: 061-seed-rewards-state
**Date**: 2026-05-20

## RewardAccounts

```haskell
type RewardAccounts = Map AccountAddress Coin
```

Represents reward accounts returned by the provider for the transaction body's withdrawal keys.

Validation rules:

- Keys come from `Withdrawals` in the candidate transaction body.
- Returned accounts are considered registered for the validation seed.
- Missing keys remain unregistered and must not be synthesized.
- `Coin 0` is a valid registered balance.

## RewardAccountSource

```haskell
data RewardAccountSource
    = RewardAccountsN2C
    | RewardAccountsNotRequired
```

Tracks whether reward-account state was queried from N2C or skipped because the transaction had no withdrawals.

JSON rendering:

- `RewardAccountsN2C` -> `"n2c"`
- `RewardAccountsNotRequired` -> `"not_required"`

## Session

Existing role: resolved N2C state for one `tx-validate` invocation.

New fields:

```haskell
sessionRewardAccounts :: RewardAccounts
sessionRewardAccountSource :: RewardAccountSource
```

Rules:

- For no-withdrawal transactions, `sessionRewardAccounts` is empty and source is `RewardAccountsNotRequired`.
- For withdrawal transactions, source is `RewardAccountsN2C`; the map contains only accounts returned by the provider.

## Seeded Validation State

The synthetic Conway `NewEpochState` used by `applyTx`.

Fields seeded by this feature:

- current pparams, unchanged from existing behavior
- UTxO, unchanged from existing behavior
- cert-state accounts for returned reward accounts

Account seeding rule:

- credential = withdrawal account's staking credential
- reward balance = queried `Coin`
- deposit = `Coin 0` unless a future provider API supplies deposit data
- stake-pool and DRep delegations = absent

## Verdict

Existing role: typed result rendered as human text or JSON.

New field:

```haskell
verdictRewardAccountsSource :: RewardAccountSource
```

Rules:

- Human output is unchanged.
- JSON output includes `reward_accounts_source`.

## State Transitions

```text
decoded tx
  -> collect withdrawals
  -> no withdrawals: RewardAccountsNotRequired + empty RewardAccounts
  -> withdrawals: query N2C reward accounts
  -> seed validation state with returned accounts
  -> applyTx
  -> render verdict
```

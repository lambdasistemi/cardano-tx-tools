# Quickstart: reward-account validation smoke

**Feature**: 061-seed-rewards-state
**Date**: 2026-05-20

## Offline Verification

The required CI proof is the branch gate:

```bash
./gate.sh
```

It runs:

```bash
git diff --check
nix flake check --no-eval-cache
```

Focused worker checks may use:

```bash
nix develop --quiet -c just unit "Cardano.Tx.Validate"
nix develop --quiet -c just unit "Cardano.Tx.Validate.Cli"
```

## Live Mainnet Operator Follow-Up

This smoke requires the signed issue #61 transaction file and a synced mainnet node socket. It is not part of `./gate.sh`.

```bash
export CARDANO_NODE_SOCKET_PATH=/code/cardano-mainnet/ipc/node.socket

nix run .#tx-validate -- \
  --input signed-tx.hex \
  --n2c-socket "$CARDANO_NODE_SOCKET_PATH" \
  --network-magic 764824073 \
  --output json | tee tx-validate-issue-61.json
```

Expected result for the registered Amaru permissions reward account:

- `status` is not `structural_failure` solely because of `WithdrawalsNotInRewardsCERTS`.
- `reward_accounts_source` is `"n2c"`.
- Any remaining structural failures are unrelated ledger failures and must be triaged separately.

If the exact transaction file is not available to the PR runner, record that in the PR body before marking ready and include the offline gate evidence instead.

## No-Withdrawal Check

Existing no-withdrawal transactions should behave as before, except JSON includes provenance:

```json
"reward_accounts_source": "not_required"
```

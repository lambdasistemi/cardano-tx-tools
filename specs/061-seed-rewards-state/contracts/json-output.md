# JSON Output Contract: reward account provenance

**Feature**: 061-seed-rewards-state
**Date**: 2026-05-20

## Existing Envelope

`tx-validate --output json` keeps the existing fields:

```json
{
  "status": "structurally_clean",
  "exit_code": 0,
  "structural_failures": [],
  "witness_completeness_count": 1,
  "pparams_source": "n2c",
  "slot_source": "n2c",
  "utxo_sources": {
    "<txId>#<ix>": "n2c"
  }
}
```

## New Field

The envelope gains one top-level field:

```json
{
  "reward_accounts_source": "n2c"
}
```

Allowed values:

| Value | Meaning |
|---|---|
| `"n2c"` | The transaction had withdrawals and `tx-validate` queried reward accounts from the N2C provider. |
| `"not_required"` | The transaction had no withdrawals, so no reward-account query was needed. |

## Registered Withdrawal Example

```json
{
  "status": "structurally_clean",
  "exit_code": 0,
  "structural_failures": [],
  "witness_completeness_count": 1,
  "pparams_source": "n2c",
  "slot_source": "n2c",
  "utxo_sources": {
    "<txId>#0": "n2c"
  },
  "reward_accounts_source": "n2c"
}
```

## Unregistered Withdrawal Example

```json
{
  "status": "structural_failure",
  "exit_code": 1,
  "structural_failures": [
    {
      "rule": "CERTS",
      "constructor": "CertsFailure",
      "detail": "ConwayCertsFailure (WithdrawalsNotInRewardsCERTS ...)"
    }
  ],
  "witness_completeness_count": 1,
  "pparams_source": "n2c",
  "slot_source": "n2c",
  "utxo_sources": {
    "<txId>#0": "n2c"
  },
  "reward_accounts_source": "n2c"
}
```

## Compatibility

Human output does not change. JSON consumers should continue to use the existing `status` and `exit_code` fields as the primary contract; the new field is provenance metadata.

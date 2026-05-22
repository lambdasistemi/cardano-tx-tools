# Data Model: Real Conway amaru disburse fixtures

## Disburse Fixture

Fields:

- slug: one of `15-amaru-disburse-minimal`,
  `16-amaru-disburse-multisig`, `17-amaru-disburse-contingency`
- transaction bytes: signed/submitted Conway transaction sourced from
  `amaru-treasury-tx/transactions/`
- rules file: fixture-local `rules.yaml`
- expected graph: fixture-local `expected.ttl`
- expected entity overlay: fixture-local `expected.entities.ttl`
- expected text output: fixture-local `expected.txt`
- notes: fixture-local `NOTES.md`

Validation rules:

- Slug numbers must be consecutive after the #50 fixtures.
- Each notes file must name tx hash, source commit or PR, and blueprint
  chain.
- Expected output must not contain `BlueprintUnresolvedReference` for a
  valid escaped-reference blueprint.

## Blueprint Reference

Fields:

- raw ref: JSON `$ref`, for example
  `#/definitions/types~1TreasurySpendRedeemer`
- pointer token: the segment after `#/definitions/`
- decoded definition key: token after RFC 6901 replacement of `~1` with
  `/` and `~0` with `~`

Validation rules:

- Decode before definition lookup.
- Only RFC 6901 token escapes are in scope.
- Unknown decoded keys still produce the existing unresolved-reference
  error.

## Treasury Typed Predicate

Fields:

- namespace: fixture default namespace, not `cardano:`
- constructor: blueprint constructor title
- field: blueprint field title

Validation rules:

- Predicate traceability must pass against fixture blueprints.
- No new canonical vocabulary term may be introduced by this ticket.

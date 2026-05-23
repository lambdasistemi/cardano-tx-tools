# Data Model: Amaru disburse DSL fixtures

## Disburse Fixture

Fields:

- slug: `15-amaru-disburse-network-compliance` or
  `17-amaru-disburse-contingency`
- DSL builder: `ConwayTx` value in a per-fixture `S15` or `S17` module
- rules file: fixture-local `rules.yaml`
- expected graph: fixture-local `expected.ttl`
- expected entity overlay: fixture-local `expected.entities.ttl`
- expected text output: fixture-local `expected.txt`
- notes: fixture-local `NOTES.md`

Validation rules:

- Builder modules must follow the established rewrite-redesign fixture
  pattern, especially the `S11_AmaruTreasurySwapReal.hs` style.
- Golden outputs must be regenerated or verified from the current
  emitter, not hand-edited to a desired future walker shape.
- Notes must identify the transaction hash, source path, and blueprint
  source.

## Network-Compliance Shape

Fields:

- source directory:
  `/code/amaru-treasury-tx-issue-237/transactions/2026/network_compliance/affe90d1fa9a93b3e2a48009ef80634e9de8428640f5d673e85b002a86399982/`
- treasury inputs: 5 spends at script
  `32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d`
- wallet inputs: 1 spend
- outputs: treasury return, payee, and 1 change output
- required signers: 2
- spend redeemers: 5 `TreasurySpendRedeemer` values
- reference inputs: 4
- collateral: 1 collateral input
- withdrawals: one zero-lovelace withdrawal against the stake script

Validation rules:

- Five spend redeemers must carry the current typed parent predicate for
  the SchemaMap amount field.
- The amount child remains opaque in this PR.

## Contingency Shape

Fields:

- source directory:
  `/code/amaru-treasury-tx/transactions/2026/contingency/18d57a4f104df4cc776104ce626958e2110122392e4c4c7671edc8861b48452e/`
- on-chain block: `60509ac5`
- slot: `187809147`
- signing shape: 4-of-4 multisig contingency disburse

Validation rules:

- Fixture must be self-contained because source inputs are spent.
- No N2C-only data may be required at test time.

## Sundae Treasury Blueprint

Fields:

- file path:
  `test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json`
- source: `/code/amaru-treasury/treasury-contracts/plutus.json` or a
  documented extraction
- mapped script hash:
  `32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d`

Validation rules:

- The rules files must register this blueprint for the treasury spend
  script.
- The traceability spec must pass without new `cardano:*` terms.

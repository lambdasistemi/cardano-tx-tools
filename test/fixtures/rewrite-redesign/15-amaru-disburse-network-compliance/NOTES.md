# 15-amaru-disburse-network-compliance — design narrative

DSL reconstruction of the on-chain network-compliance disburse
transaction, mirroring the SchemaMap-decoded
`TreasurySpendRedeemer.Disburse` shape on the spend redeemer. The
walker extension that would materialize per-entry `:_0_key` /
`:_0_value` triples for the `OpenArray [OpenObject {"key", "value"}]`
amount map is intentionally deferred (A-001 / spec FR-009): this
fixture pins the current opaque-child output for the amount field.

## Provenance

- Source repository: `/code/amaru-treasury-tx-issue-237`
- Source directory:
  `transactions/2026/network_compliance/affe90d1fa9a93b3e2a48009ef80634e9de8428640f5d673e85b002a86399982/`
- Source artifacts: `tx.cbor.hex`, `signed-tx.hex`, `submitted.json`,
  `intent.json` (action=disburse, beneficiary CAG, 400000 USDM).
- Treasury payment script hash:
  `32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d`.
- Permissions stake script hash:
  `a64d1b9e1aeffe54056034d84977061b45a92691efc282fbee3fc094` (the
  `permissionsRewardAccount` from `intent.json`).
- Required signers from the on-chain tx:
  `8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1` and
  `f3ab64b0f97dcf0f91232754603283df5d75a1201337432c04d23e2e`.

The earlier `antithesis-disburse-draft/` directory the issue #90 brief
originally cited has been flattened away in the source repo; A-002
(epic owner, 2026-05-23) re-anchored the fixture to the `affe90d1...`
hash above.

## Body shape

DSL counts produced by `S15_AmaruDisburseNetworkCompliance.tx`:

- 6 body inputs: 1 wallet input (pubkey, body-index 0) + 5 treasury
  script inputs (body-indexes 1..5). The on-chain tx has the wallet
  input at body-index 1 with script inputs at 0,2,3,4,5; the harness
  only counts inputs, so the per-index permutation does not matter
  for `:TreasurySpendRedeemer_amount` emission.
- 3 outputs: treasury return (`120.299272 ADA + 1_349_523_953 USDM`),
  CAG payee (`1.189560 ADA + 400_000_000_000 USDM`), wallet change
  (`80.733583 ADA`).
- 2 required signers (CAG payee key + network-wallet key — names per
  the on-chain `signers` list).
- 4 reference inputs (treasury validator + permissions + registry +
  scopes reference scripts, all stubbed via `stubTxIn 200..203`).
- 1 collateral input (`stubTxIn 100`, sourced from the wallet).
- 1 zero-lovelace `Withdraw` against the permissions stake script.

## Blueprint registration

`rules.yaml` registers the trimmed single-validator extraction at
`blueprints/sundae-treasury.cip57.json` for the treasury payment
script (`32201dc1...`). The extraction is intentionally narrower than
the upstream `plutus.json`: the full file declares 13 validators and
the typed-emit walker would otherwise pick `oneshot.oneshot.spend`
(the first validator with a redeemer slot, schema = `Data` passthrough)
and emit `:Data_fields` predicates instead of
`:TreasurySpendRedeemer_amount`. The extraction keeps only
`treasury.treasury.spend` plus the `TreasurySpendRedeemer` /
`Pairs<PolicyId, Pairs<AssetName, Int>>` definitions reachable from
its redeemer schema. Source: `/code/amaru-treasury/treasury-contracts/plutus.json`.

## Resolved-UTxO wiring

`Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo` maps each treasury
`TxIn` (`stubTxIn 2..6`) to a `TxOut` at
`Addr Testnet (ScriptHashObj treasuryScriptHash) StakeRefNull`. Without
the resolved entries the spend purpose can't resolve to a payment
script credential and the redeemer would fall through to opaque
`cardano:hasRawBytes` emission.

## Cross-leaf identity

The on-chain treasury address has both payment-script and stake-script
credentials equal to `32201dc1...`. The decoded entity overlay
materializes both as `cardano:PaymentScript` and `cardano:StakeScript`
identifiers, and the treasury-return output's
`cardano:hasPaymentCredential` predicate references the same
identifier the entity declaration mints.

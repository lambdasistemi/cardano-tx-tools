# 17-amaru-disburse-contingency — design narrative

DSL reconstruction of the on-chain 4-of-4 contingency disburse
transaction, mirroring the SchemaMap-decoded
`TreasurySpendRedeemer.Disburse` shape on the spend redeemer. The
walker extension that would materialize per-entry `:_0_key` /
`:_0_value` triples for the `OpenArray [OpenObject {"key", "value"}]`
amount map is intentionally deferred (A-001 / spec FR-009): this
fixture pins the current opaque-child output for the amount field.

## Provenance

- Source repository: `/code/amaru-treasury-tx`
- Source directory:
  `transactions/2026/contingency/18d57a4f104df4cc776104ce626958e2110122392e4c4c7671edc8861b48452e/`
- Source artifacts: `tx.cbor`, `signed-tx.hex`, `submitted.json`,
  `intent.json` (action=disburse, beneficiary network_compliance
  treasury, 205_000 ADA).
- Tx hash: `18d57a4f104df4cc776104ce626958e2110122392e4c4c7671edc8861b48452e`.
- Block: `60509ac5a41a8919d9e00a77578f0309380d08a9002f088e85055ee6c7c883a7`.
- Slot: `187_809_147`.
- Submitted: 2026-05-21 14:57:18 UTC.
- Fee on-chain: 415_814 lovelace (the DSL build keeps fee 0; fee is not
  load-bearing for the emitter byte-diff).
- Contingency treasury payment script hash:
  `e6dbff09245eb89c4f583faaa428387e42c471f1868637a848602a4e`.
- Network-compliance beneficiary script hash:
  `32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d`
  (same hash fixture 15 uses as its source treasury script).
- Contingency permissions stake script hash:
  `2810b46b73cb27292cd8511274b6930188eee61b7d8635af6b1b626a` (the
  `permissionsRewardAccount` from `intent.json`). Distinct from
  fixture 15's network-compliance permissions stake script.
- Required signers from the on-chain tx (4-of-4 multisig):
  `7095faf3d48d582fbae8b3f2e726670d7a35e2400c783d992bbdeffb`
  (scope owner), `f3ab64b0f97dcf0f91232754603283df5d75a1201337432c04d23e2e`,
  `8bd03209d227956aaf9670751e0aa2057b51c1537a43f155b24fb1c1`
  (network-wallet), and
  `97e0f6d6c86dbebf15cc8fdf0981f939b2f2b70928a46511edd49df2`.

## Body shape

DSL counts produced by `S17_AmaruDisburseContingency.tx`:

- 2 body inputs: 1 wallet input (pubkey, `stubTxIn 1`) +
  1 contingency treasury script input (`stubTxIn 2`).
- 3 outputs: contingency treasury return (`3_852_000.000000 ADA`),
  network-compliance beneficiary (`205_000.000000 ADA`), wallet
  change (`92.141887 ADA`). All three are ADA-only — the contingency
  disburse moves no native assets.
- 4 required signers (4-of-4 contingency multisig). The
  `signerExtraTwo` entry shares its key-hash with `walletPubKeyHash`
  (the network-wallet); the emitter dedupes identifier bnodes by
  hash, so the required-signer triple set carries the network-wallet
  identifier instead of a second `cred_paymentkey_…` bnode.
- 4 reference inputs (treasury validator + permissions + registry +
  scopes reference scripts, stubbed via `stubTxIn 200..203`).
- 1 collateral input (`stubTxIn 100`, sourced from the wallet).
- 1 zero-lovelace `Withdraw` against the contingency permissions
  stake script.

## Blueprint registration

`rules.yaml` registers the trimmed single-validator extraction at
`blueprints/amaru-treasury.cip57.json` (the same shared file fixture
15 uses) for the contingency treasury payment script (`e6dbff09…`).
The extraction keeps only `treasury.treasury.spend` plus the
`TreasurySpendRedeemer` / `Pairs<PolicyId, Pairs<AssetName, Int>>`
definitions reachable from its redeemer schema. Source:
`/code/amaru-treasury/treasury-contracts/plutus.json`.

## Resolved-UTxO wiring

`Cardano.Tx.Graph.EmitGoldenSpec.fixtureUtxo` maps the single
contingency treasury `TxIn` (`stubTxIn 2`) to a `TxOut` at
`Addr Testnet (ScriptHashObj treasuryScriptHash) StakeRefNull`
carrying 4_057_000_000_000 lovelace (mirrors the on-chain input
`46c11538f39bce1e6d3bf1f9273f30b75b4eb094bbb5d121b76083eab0113d71#0`).
Without the resolved entry the spend purpose can't resolve to a
payment-script credential and the redeemer would fall through to
opaque `cardano:hasRawBytes` emission.

## Cross-leaf identity

The on-chain contingency treasury address has both payment-script
and stake-script credentials equal to `e6dbff09…`. The decoded
entity overlay materializes both as `cardano:PaymentScript` and
`cardano:StakeScript` identifiers, and the treasury-return output's
`cardano:hasPaymentCredential` predicate references the same
identifier the entity declaration mints. The same shape applies to
the network-compliance beneficiary address (`32201dc1…` on both
halves) — fixture 15 already covers that half via its source
treasury; fixture 17 exercises it as a destination.

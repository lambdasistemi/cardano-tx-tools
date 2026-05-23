# Quickstart: Verifying issue #90

From the worktree root:

```sh
git status --short --branch
./gate.sh
```

Focused checks expected from the implementation pairs:

```sh
nix develop --quiet -c just unit
```

Review checklist:

- Confirm fixtures `15-amaru-disburse-network-compliance` and
  `17-amaru-disburse-contingency` are enumerated by the golden suite.
- Confirm each fixture has `rules.yaml`, `expected.ttl`,
  `expected.entities.ttl`, `expected.txt`, and `NOTES.md`.
- Confirm builder modules exist for S15 and S17 and use DSL
  reconstruction rather than pre-built CBOR.
- Confirm `test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json`
  exists and provenance notes document its source.
- Confirm expected outputs contain `:TreasurySpendRedeemer_amount` and
  preserve the current opaque child bnode for amount entries.
- Confirm fixtures 01 through 14 are unchanged.
- Confirm no `src/Cardano/Tx/Graph/Emit/*`,
  `src/Cardano/Tx/Blueprint.hs`, or new `cardano:*` vocabulary terms are
  introduced.

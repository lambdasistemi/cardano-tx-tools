# Quickstart: Verifying issue #80

From the worktree root:

```sh
git status --short --branch
./gate.sh
```

Focused checks expected from the implementation pair:

```sh
nix develop --quiet -c just unit
```

Review checklist:

- Confirm fixtures `15-amaru-disburse-minimal`,
  `16-amaru-disburse-multisig`, and
  `17-amaru-disburse-contingency` are enumerated by the golden suite.
- Confirm each fixture has `rules.yaml`, `expected.ttl`,
  `expected.entities.ttl`, `expected.txt`, and `NOTES.md`.
- Confirm each `NOTES.md` records tx hash, source commit or PR, and
  blueprint chain.
- Confirm expected outputs contain typed treasury predicates and no
  valid-schema `BlueprintUnresolvedReference` decode error.
- Confirm `CHANGELOG.md` has one Unreleased / Features bullet for the
  fixtures and RFC 6901 normalization.

# Migration plan (historical)

> **Status: complete.** Phase 1 landed in PRs
> [#3](https://github.com/lambdasistemi/cardano-tx-tools/pull/3),
> [#4](https://github.com/lambdasistemi/cardano-tx-tools/pull/4),
> [#5](https://github.com/lambdasistemi/cardano-tx-tools/pull/5).
> The Phase 2 `cardano-tx-generator` move landed in
> [PR #10](https://github.com/lambdasistemi/cardano-tx-tools/pull/10).
> The page is retained for historical context and to document the
> `source-repository-package` staging pin still in `cabal.project`.

The transaction-tooling surface was moved out of
[`lambdasistemi/cardano-node-clients`](https://github.com/lambdasistemi/cardano-node-clients)
under tracking issue
[#152](https://github.com/lambdasistemi/cardano-node-clients/issues/152).

## Locked design

| Decision | Value |
| --- | --- |
| New repo name | `lambdasistemi/cardano-tx-tools` |
| Module namespace | `Cardano.Tx.*` (rename from `Cardano.Node.Client.*`) |
| Dependency direction | one-way `cardano-tx-tools → cardano-node-clients` |
| Migration | `source-repository-package` staging |
| `cardano-tx-generator` move | deferred (Phase 2, when the staging pin is dropped) |

## Phase 1 — staged extraction

Moves to `cardano-tx-tools`:

- `lib-tx-build/` → `Cardano.Tx.{Build, Balance, Inputs, Witnesses,
  Scripts, Credentials, Deposits, Ledger}`
- `lib-plutus-blueprint/` → `Cardano.Tx.Blueprint`
- `lib/.../TxDiff*` → `Cardano.Tx.Diff` and submodules (including
  `Cardano.Tx.Diff.Resolver.N2C` which is the bridge to
  `cardano-node-clients`' `Provider`)
- `lib/.../Evaluate.hs` → `Cardano.Tx.Evaluate`
- `app/tx-diff/` + its AppImage / DEB / RPM / Homebrew release
  pipeline + the `pkgs.cacert` runtime wrapper

In `cardano-node-clients`:

- `cabal.project` adds a `source-repository-package` pin to
  `cardano-tx-tools` with the nix32 SHA256.
- `cardano-node-clients.cabal` drops the moved sublibraries and their
  transitive dependencies (`http-client`, `http-client-tls`, etc.).
- Internal call sites (notably `Cardano.Node.Client.TxGenerator.*`)
  update imports from `Cardano.Node.Client.TxBuild` etc. to
  `Cardano.Tx.Build`.

## Phase 2 — cut the staging

After the staging settles:

- Migrate `Cardano.Node.Client.TxGenerator.*` and
  `app/cardano-tx-generator/` to `cardano-tx-tools`. The daemon is a
  transaction tool that happens to talk N2C, not a node client.
- Drop the `source-repository-package` pin from
  `cardano-node-clients`. Final shape of that repo: pure N2C
  mini-protocol library plus `Provider`, `Submitter`, UTxO indexer.

## Open follow-ups

These are deliberately out of scope for the first migration PR but
worth flagging:

- **Local tx-history indexer.** The current `tx-diff` resolver chain
  falls back to a Blockfrost-style HTTP endpoint for already-spent
  inputs, which leaks transaction identifiers to a third party. A
  ChainSync-driven RocksDB indexer that stores `TxIn → TxOut` (or
  `TxId → CBOR`) would close that gap and slot into the resolver
  chain ahead of the web2 fallback.
- **Transaction invariant prover.** The same open-tree language the
  diff and collapse rules already speak can host a small predicate
  DSL over a transaction (or over a diff), expressing things like
  ADA conservation, recipient whitelists, or datum/redeemer
  matching. Lives well in `cardano-tx-tools`, not anywhere near the
  node-client boundary.

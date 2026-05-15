# Phase 0 — Research

## Locked architectural decisions

### D1. Hosting shape: sublibrary inside `cardano-tx-tools`

**Decision**: Add a public cabal sublibrary `tx-generator-lib` inside
the existing `cardano-tx-tools` package. Source root at
`lib-tx-generator/`. Module namespace `Cardano.Tx.Generator.*`.

**Rationale**:

- One release pipeline. Cabal version, GitHub releases, AppImage /
  DEB / RPM bundlers, Homebrew tap, release planner — all already
  wired in PR #4 against a single `.cabal` file. A second package in
  the same repo would duplicate the release surface.
- Precedent. The `n2c-resolver` sublib already follows this shape:
  the main library stays light, the heavy/bridge code lives in a
  dedicated sublib whose consumers opt in.
- Downstream consumers of `cardano-tx-tools` (the main library) pay
  zero cost: they don't pull in any TxGenerator transitive deps
  (chain-follower, ouroboros-*, rocksdb-*).
- The user explicitly directed this choice: "you can use the same
  repo, but leave the packages separated in the cabal, sublibrary,
  separate tests stanza, separate exe if necessary".

**Alternatives considered**:

| Alternative | Rejected because |
| --- | --- |
| Second cabal package (`./cardano-tx-tools ./cardano-tx-generator`) | Doubles the release-planner surface (`.cabal` versions to sync, two tag sequences); no observable downstream benefit. |
| Separate repo `lambdasistemi/cardano-tx-generator` | Three repos to maintain. The user explicitly said same repo. |
| Drop into the main library (`cardano-tx-tools` proper) | Adds heavy transitive deps (chain-follower, ouroboros-consensus) to every downstream consumer of the diff / blueprint / builder. Defeats the lightness gained in PR D. |

### D2. E2E tests follow the daemon

**Decision**: Move the existing `Cardano.Node.Client.E2E.TxGenerator*Spec`
modules to `cardano-tx-tools/test/Cardano/Tx/Generator/E2E/*Spec.hs`
and add an `e2e-tests` test-suite that build-depends on
`cardano-node-clients:devnet` for `withCardanoNode`.

**Rationale**:

- The daemon is the system under test; the test code should live
  with the code it exercises.
- cardano-node-clients's existing `e2e-tests` test-suite stays
  green after the move because it no longer needs to import
  `Cardano.Node.Client.TxGenerator.*` — those imports are gone with
  the daemon.
- The dependency arrow inside the test-suite stanza
  (`cardano-tx-tools:e2e-tests → cardano-node-clients:devnet`) is the
  same one-way direction the constitution requires.

**Alternatives considered**:

| Alternative | Rejected because |
| --- | --- |
| Keep e2e tests in cardano-node-clients | Introduces a reverse import: cardano-node-clients/tests/* would `import Cardano.Tx.Generator.*` from cardano-tx-tools. cabal accepts it (test-suites can pull from anywhere) but it muddies the boundary documented in the constitution. |
| Drop the e2e tests entirely | The daemon's e2e suite is what catches submit-loop bugs, restart-on-rollback bugs, etc. Dropping them would erase regression coverage for the most operationally important paths. |

### D3. Docker image moves with the binary

**Decision**: Move `nix/docker-image.nix` from cardano-node-clients to
cardano-tx-tools. The image publishes at
`ghcr.io/lambdasistemi/cardano-tx-tools/cardano-tx-generator`
instead of the legacy
`ghcr.io/lambdasistemi/cardano-node-clients/cardano-tx-generator`.

**Rationale**:

- The image is a single-purpose container around the binary; the
  binary moves, the image follows.
- Cross-repo Docker publishing (image in cardano-node-clients
  registry path, source in cardano-tx-tools) is an operational
  smell. The registry namespace should match the source repo.
- Downstream consumers (the
  `cardano-node-antithesis/components/cardano-tx-generator/`
  docker-compose, e.g.) update the image tag in one place.

**Alternatives considered**:

| Alternative | Rejected because |
| --- | --- |
| Keep image URL stable on cardano-node-clients registry; cardano-tx-tools pushes there | Cross-repo write access is fragile and adds GitHub token plumbing for no consumer benefit. |
| Publish at both URLs during a deprecation window | Doubles publish cost; consumers can update their image tag in one PR. |
| Drop the image entirely | The cardano-node-antithesis docker-compose pulls it; dropping breaks their consumers without warning. |

## Daemon import map (informs the dep set)

Modules under `Cardano.Node.Client.TxGenerator.*` (in
cardano-node-clients today) import from these external packages, in
addition to other TxGenerator submodules:

| Import group | Origin (after migration) |
| --- | --- |
| `Cardano.Crypto.{DSIGN, Hash.*, Seed}` | `cardano-crypto-class` |
| `Cardano.Ledger.{Address, Api.*, BaseTypes, Binary, Coin, Conway, Core, Credential, Keys, TxIn, Val}` | `cardano-ledger-{api, core, conway, allegra, byron, mary}` |
| `Cardano.Chain.Slotting (EpochSlots)` | `cardano-ledger-byron` |
| `Cardano.Node.Client.{Provider, Submitter}` | `cardano-node-clients` (via the `source-repository-package` pin) |
| `Cardano.Node.Client.N2C.{ChainSync, Connection, Probe, Provider, Reconnect, Submitter, Trace, Types}` | `cardano-node-clients` |
| `Cardano.Node.Client.UTxOIndexer.{BlockExtract, Indexer, Server, Types}` | `cardano-node-clients:utxo-indexer-lib` + `cardano-node-clients` |
| `Cardano.Node.Client.E2E.Setup` | `cardano-node-clients:devnet` (e2e tests only) |
| `Cardano.Tx.{Build, Balance, Ledger}` | `cardano-tx-tools` (this repo) |
| `ChainFollower` | `chain-follower` |
| `Network.Socket`, `Control.Concurrent.Async`, etc. | base + `async` + `network` + `stm` + `unix` + `retry` + `random` + `time` |

All cardano-node-clients imports stay one-way going IN to
cardano-tx-tools' new sublib; nothing in cardano-node-clients's main
library imports back out. The package-level cycle is broken.

## Risk register

| Risk | Mitigation |
| --- | --- |
| Heavy dep set on the sublib triggers a long first build in CI | Already validated by PR D's CI: ouroboros-consensus / chain-follower / rocksdb closures are in the cachix cache. CI runs land under 5 minutes. |
| Hidden unit-tests-only dependency in the migrated tests fails to resolve in the new `tx-generator-tests` stanza | Mitigation: copy the existing tests verbatim with only namespace renames; if a test imports something not in the new build-depends, add it explicitly. Caught by the local `nix flake check`. |
| Docker image URL change breaks downstream consumers silently | Mitigation: release notes call it out explicitly with the new registry path. Add a one-time announcement on the cardano-node-clients release page. Out of scope of this PR but tracked in the rollout checklist. |
| TxGenerator's e2e tests under `cardano-node-clients:devnet` now have a cross-repo source-repository-package step in their build plan | Already paid: `cardano-tx-tools/cabal.project` pins cardano-node-clients today; the e2e stanza just adds `cardano-node-clients:devnet` to its build-depends. No new pin required. |

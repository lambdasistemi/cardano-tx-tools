# Feature Specification: Tx Generator Migration

**Feature Branch**: `001-tx-generator-migration`
**Created**: 2026-05-15
**Status**: Draft
**Input**: Phase 2 of the migration tracked at
[lambdasistemi/cardano-node-clients#152](https://github.com/lambdasistemi/cardano-node-clients/issues/152).
The `cardano-tx-generator` load-test daemon currently lives in
cardano-node-clients but uses cardano-tx-tools' `TxBuild` / `Balance`
modules. Moving it closes the package-level dependency cycle that
blocks the companion deletion PR in cardano-node-clients.

## User Scenarios & Testing

### User Story 1 - Build cardano-node-clients with no pin to cardano-tx-tools (Priority: P1)

A maintainer wants `cardano-node-clients` to ship as a pure node-client
library (N2C mini-protocols, Provider, Submitter, UTxOIndexer) without
any transitive dependency on the transaction-tooling repository. Today
`Cardano.Node.Client.TxGenerator.*` modules in cardano-node-clients
import `Cardano.Tx.{Build, Balance}` from cardano-tx-tools, which would
require cardano-node-clients to pin cardano-tx-tools via
`source-repository-package`. Combined with the existing pin in the
other direction (for the n2c-resolver sublib of cardano-tx-tools),
cabal's solver reports a package-level cycle and refuses to build.

**Why this priority**: This is the literal blocker for the
cardano-node-clients deletion PR. Without it, the migration cannot
complete and the duplicated tx-diff release pipeline (cardano-node-clients
keeps publishing the binary while cardano-tx-tools also tries to) stays
in place indefinitely.

**Independent Test**: Run `cabal build all` (and `nix flake check`) on
the cardano-node-clients companion-PR branch with no
`source-repository-package` entry for cardano-tx-tools. Build must
succeed without producing a `cardano-tx-generator` binary from
cardano-node-clients.

**Acceptance Scenarios**:

1. **Given** the companion cardano-node-clients PR with the
   `TxGenerator` modules and the `cardano-tx-generator` executable
   deleted, **When** `cabal build all` runs against
   cardano-node-clients's `cabal.project` with no cardano-tx-tools
   pin, **Then** the build succeeds and produces the
   `cardano-node-clients` library, `utxo-indexer-lib` sublib,
   `devnet` sublib, `utxo-indexer` executable, and the test suites
   (unit + e2e) without any cabal dependency on cardano-tx-tools.
2. **Given** cardano-tx-tools' `main` with the migrated `TxGenerator`
   modules, **When** `cabal build cardano-tx-tools` runs, **Then** the
   `tx-generator-lib` sublib and `cardano-tx-generator` executable
   are produced alongside the existing tx-diff / library outputs.
3. **Given** both repositories built standalone, **When** an external
   project depends on `cardano-tx-tools` only, **Then** it can build
   the load-test daemon without pulling cardano-node-clients into the
   build plan beyond the one-way pin in cardano-tx-tools's
   `cabal.project`.

---

### User Story 2 - Separate test-suite for the daemon (Priority: P2)

A contributor wants to iterate on `TxGenerator.{Selection, Fanout,
Population, ...}` without running the diff core tests, the blueprint
decoder tests, or the resolver chain tests. The migrated daemon's tests
get their own cabal stanza so
`cabal test cardano-tx-tools:tx-generator-tests` exercises only the
daemon-specific specs.

**Why this priority**: Keeps the dev loop fast and makes the test
ownership boundary clear: changes to the diff core never re-run
TxGenerator's persistence and fanout specs and vice versa.

**Independent Test**: Run
`cabal test cardano-tx-tools:tx-generator-tests` and observe that the
suite contains only the modules under `Cardano.Tx.Generator.*Spec` and
no Diff/Blueprint/Resolver specs. Symmetrically,
`cabal test cardano-tx-tools:unit-tests` must NOT contain any Generator
specs.

**Acceptance Scenarios**:

1. **Given** the migration is complete, **When** the contributor runs
   `cabal test cardano-tx-tools:tx-generator-tests`, **Then** the suite
   reports the Fanout / Persist / Population / Selection / Server /
   Snapshot specs and nothing else.
2. **Given** the contributor touches a non-Generator module (e.g.
   `Cardano.Tx.Diff.Resolver.Web2`), **When** they run
   `cabal test cardano-tx-tools:tx-generator-tests`, **Then** the
   suite does not have to rebuild the diff core to run.

---

### User Story 3 - Preserve the executable's external contract (Priority: P1)

Existing operators / CI pipelines invoke `cardano-tx-generator` as a
binary. After the move, every command-line flag, environment variable,
exit code, and Unix-socket protocol surface continues to behave
exactly as it did when the binary shipped from cardano-node-clients.

**Why this priority**: Operators must not see a regression. The
migration must not be observable from outside the binary.

**Independent Test**: Run the existing operator-facing smoke checks
(e.g. `cardano-tx-generator --help`, the daemon's `refill` and
`transact` Unix-socket endpoints from cardano-node-clients's e2e
suite) against the binary produced by cardano-tx-tools. Behaviour
must match byte-for-byte on the CLI surface and JSON output.

**Acceptance Scenarios**:

1. **Given** the cardano-tx-tools-built binary, **When** the operator
   invokes any documented CLI flag, **Then** the exit codes and
   stdout/stderr text match the cardano-node-clients-built binary at
   the migration source SHA.
2. **Given** a running cardano-node devnet, **When** the e2e harness
   exercises the daemon's control socket through `refill`, `transact`,
   and `snapshot` requests, **Then** every response matches the
   pre-migration baseline.

---

### Edge Cases

- The `cardano-tx-generator` Docker image (currently built from
  `nix/docker-image.nix` in cardano-node-clients) needs a home after
  the move. The image is a single-purpose container around the
  binary; it follows the binary into cardano-tx-tools.
- TxGenerator's e2e tests in cardano-node-clients (under
  `test/Cardano/Node/Client/E2E/TxGenerator*Spec.hs`) exercise the
  daemon against a real devnet. They depend on the
  `cardano-node-clients:devnet` sublib for `withCardanoNode`. They
  move to cardano-tx-tools alongside the daemon; cardano-tx-tools
  pulls `withCardanoNode` from `cardano-node-clients:devnet` via the
  existing pin.
- Module rename `Cardano.Node.Client.TxGenerator.*` →
  `Cardano.Tx.Generator.*`. Internal call sites and test imports
  update accordingly. Operators see no module-name impact.
- The release / image-publish pipeline for `cardano-tx-generator`
  retargets to a new path under cardano-tx-tools. The existing image
  tag URL stops receiving updates after the cutover; downstream
  consumers are informed via the migration release notes.

## Requirements

### Functional Requirements

- **FR-001**: cardano-tx-tools MUST expose a public cabal sublibrary
  `tx-generator-lib` whose `hs-source-dirs` is a dedicated directory
  (`lib-tx-generator/`) and whose `exposed-modules` are exactly the
  renamed daemon modules: `Cardano.Tx.Generator.Build`, `Daemon`,
  `Fanout`, `Persist`, `Population`, `Selection`, `Server`,
  `Snapshot`, `Types`.
- **FR-002**: cardano-tx-tools MUST expose an executable
  `cardano-tx-generator` whose `main-is` lives at
  `app/cardano-tx-generator/Main.hs`. Its `build-depends` MUST be the
  minimum needed (`base`, `cardano-tx-tools:tx-generator-lib`, plus
  any direct imports `Main.hs` makes).
- **FR-003**: cardano-tx-tools MUST expose a separate test-suite
  `tx-generator-tests`, distinct from the existing `unit-tests`
  test-suite, hosting the unit tests for the migrated daemon modules:
  `Cardano.Tx.Generator.{Fanout, Persist, Population, Selection,
  Server, Snapshot}Spec`.
- **FR-004**: The migration MUST preserve the one-way dependency
  rule: cardano-tx-tools depends on cardano-node-clients (via the
  existing `source-repository-package` pin); cardano-node-clients
  MUST NOT depend on cardano-tx-tools after this migration lands.
- **FR-005**: cardano-node-clients's companion PR MUST remove the
  `Cardano.Node.Client.TxGenerator.*` modules, the
  `app/cardano-tx-generator/` executable, and the corresponding test
  files. cardano-node-clients's `cabal.project` MUST NOT contain a
  `source-repository-package` entry for cardano-tx-tools after this
  migration.
- **FR-006**: `cabal build all` MUST succeed on both repositories
  independently. `nix flake check --no-eval-cache` MUST pass on
  both.
- **FR-007**: The published behavior of the
  `cardano-tx-generator` executable (CLI flags, exit codes, control
  socket protocol, stdout/stderr format) MUST be unchanged. The
  migration is structural; behaviour is preserved.
- **FR-008**: TxGenerator e2e tests MUST keep running against a real
  cardano-node devnet. They pull `withCardanoNode` from
  `cardano-node-clients:devnet` via the source-repository-package
  pin.

### Key Entities

- **TxGenerator sublibrary**: The migrated `Cardano.Tx.Generator.*`
  modules. Provides the daemon's library API: `Daemon`, persistence,
  population shaping, selection, fanout, server endpoints, snapshot
  reporting.
- **cardano-tx-generator executable**: Thin entry point that invokes
  `Cardano.Tx.Generator.Daemon`. Its CLI is the operator surface.
- **TxGenerator test-suite**: `tx-generator-tests`, separate stanza
  from the existing `unit-tests` so the daemon's tests can be run in
  isolation.

## Success Criteria

### Measurable Outcomes

- **SC-001**: After the migration lands, `cabal build all` on
  cardano-node-clients's main branch completes with no
  `source-repository-package` entry for cardano-tx-tools in its
  `cabal.project`.
- **SC-002**: `cabal build cardano-tx-tools:exe:cardano-tx-generator`
  succeeds and produces a binary whose `--help` output is identical
  to the cardano-node-clients-built `cardano-tx-generator --help` at
  the migration source SHA.
- **SC-003**: `cabal test cardano-tx-tools:tx-generator-tests` runs
  the migrated unit tests in isolation; no Diff/Blueprint/Resolver
  specs are included.
- **SC-004**: The package-level cycle reported by cabal
  (`cyclic dependencies; conflict set: cardano-node-clients,
  cardano-tx-tools`) is gone. cabal's solver returns a clean build
  plan for cardano-node-clients's companion PR.
- **SC-005**: The TxGenerator e2e tests pass against the same
  cardano-node version pin used today (cardano-node 10.7.0).

## Assumptions

- The daemon's existing module count and shape (`Build`, `Daemon`,
  `Fanout`, `Persist`, `Population`, `Selection`, `Server`, `Snapshot`,
  `Types`) is the right granularity. No restructuring of the daemon's
  internal modules is in scope; only the namespace and host-repo
  change.
- TxGenerator's heavy dependencies (`chain-follower`,
  `ouroboros-consensus`, `ouroboros-network`, `cardano-diffusion`,
  `cardano-prelude`, `rocksdb-*` via `utxo-indexer-lib`) move with
  the daemon and become transitive deps of
  `cardano-tx-tools:tx-generator-lib` only — they do not enter the
  main `cardano-tx-tools` library.
- The Docker image for `cardano-tx-generator` is rebuilt from
  cardano-tx-tools after the cutover. The cardano-node-clients-side
  publish pipeline for this image stops; downstream consumers are
  informed via the migration release notes.
- The `lib-n2c-resolver` sublib in cardano-tx-tools (and its
  dependency on cardano-node-clients) is unchanged by this PR.

## Out of Scope

- Refactoring TxGenerator's internals (config schema, control socket
  protocol, persistence shape). The migration preserves behavior.
- Adding new features to TxGenerator. New work waits until the
  migration is in.
- Renaming the executable. The binary stays `cardano-tx-generator`
  for operator continuity.
- Phase 1 cleanup work (the tx-diff release pipeline cutover, the
  Homebrew tap formula switch). That happens in separate PRs once
  this migration unblocks the cardano-node-clients deletion.

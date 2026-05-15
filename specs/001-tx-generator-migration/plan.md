# Implementation Plan: Tx Generator Migration

**Branch**: `001-tx-generator-migration` | **Date**: 2026-05-15 | **Spec**:
[spec.md](./spec.md)
**Input**: Feature specification from
`specs/001-tx-generator-migration/spec.md`

## Summary

Move `Cardano.Node.Client.TxGenerator.*`, the `cardano-tx-generator`
executable, and the daemon's unit + e2e tests out of
[`lambdasistemi/cardano-node-clients`](https://github.com/lambdasistemi/cardano-node-clients)
into this repository under `Cardano.Tx.Generator.*`. Host the migrated
code as a public cabal sublibrary `tx-generator-lib`, a separate
test-suite `tx-generator-tests`, and an executable
`cardano-tx-generator` whose binary name is preserved for operator
continuity. Once the migration lands and the companion deletion PR
merges in cardano-node-clients, the package-level cabal cycle
documented in the spec (`cyclic dependencies; conflict set:
cardano-node-clients, cardano-tx-tools`) is gone.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix`
**Primary Dependencies**: `cardano-tx-tools` main library (for
`Cardano.Tx.{Build, Balance, Ledger}`), `cardano-node-clients` and
its `utxo-indexer-lib` sublib (via the existing
`source-repository-package` pin, for `Provider`, `Submitter`,
`N2C.*`, and the UTxO indexer), `chain-follower`,
`ouroboros-consensus`, `ouroboros-network`, `cardano-diffusion`,
`cardano-prelude`, `rocksdb-haskell-jprupp`,
`rocksdb-kv-transactions`, `async`, `retry`, `random`, `network`,
`stm`, `unix`, `time`, `contra-tracer`.
**Storage**: TxGenerator persists daemon state to an HD-wallet seed
file and a per-daemon JSON index. RocksDB usage is transitive
(through the UTxO indexer), not direct.
**Testing**: Hspec + QuickCheck. Unit tests via a new
`tx-generator-tests` test-suite (separate stanza from the existing
`unit-tests`). E2E tests via a new `e2e-tests` test-suite that
depends on `cardano-node-clients:devnet` for `withCardanoNode`.
**Target Platform**: Linux/macOS CLI. The Docker image (currently
published at
`ghcr.io/lambdasistemi/cardano-node-clients/cardano-tx-generator`)
moves to cardano-tx-tools and re-publishes at the new registry path.
**Project Type**: Haskell library (sublib) + executable + tests.
**Performance Goals**: Inherits TxGenerator's existing throughput
targets (the daemon runs at the rate the operator configures); the
migration is behavior-preserving.
**Constraints**: One-way dependency
(`cardano-tx-tools → cardano-node-clients`) must hold. No new
behavior in this PR. Module names under `Cardano.Tx.Generator.*`.
The `cardano-tx-generator` binary's CLI / control-socket surface is
byte-identical to the pre-migration baseline.
**Scale/Scope**: 9 library modules + 1 executable + 6 unit test
modules + ~13 e2e test modules. No new modules introduced.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1
design.*

| Principle | Compliance |
| --- | --- |
| I. One-way dependency on node-clients | ✔ TxGenerator continues to import `Cardano.Node.Client.{Provider, Submitter, N2C.*}` from cardano-node-clients through the existing pin. The new sublib only adds dependencies; nothing in cardano-tx-tools' main library starts importing from cardano-node-clients as a result. After the companion PR drops in cardano-node-clients, the reverse arrow is gone. |
| II. Module namespace discipline | ✔ Every migrated module's declared name moves from `Cardano.Node.Client.TxGenerator.*` to `Cardano.Tx.Generator.*`. Internal cross-imports update accordingly. |
| III. Conway-only era | ✔ TxGenerator already operates on Conway transactions only (it builds Conway-era txs via `TxBuild`). No era change introduced. |
| IV. Hackage-ready quality | ✔ The sublib carries full `extra-doc-files` (inherited from the parent package), Haddock headers preserved from source, complete metadata via the parent `.cabal`. `cabal check` against the new stanzas must pass. |
| V. Strict warnings, no `-Werror` escape hatches | ✔ The sublib inherits the `common warnings` stanza from the parent cabal file. No new `-Wno-*` flags. |
| VI. Default-offline semantics | N/A — TxGenerator is a load-tester daemon by purpose, not a user-facing CLI whose default should be offline. The principle applies to tools like `tx-diff`. |
| VII. TDD with vertical bisect-safe commits | ✔ The implementation slices in `tasks.md` each produce a building, testable commit. Module moves + cabal changes land atomically per slice. |

No constitution violations to track in the Complexity section.

## Project Structure

### Documentation (this feature)

```text
specs/001-tx-generator-migration/
├── plan.md              ← this file
├── research.md          ← Phase 0 — design decisions locked
├── data-model.md        ← Phase 1 — module catalogue + dep arrows
├── quickstart.md        ← Phase 1 — operator-facing impact
├── contracts/
│   └── cabal.md         ← Phase 1 — locked cabal stanza shapes
├── checklists/
│   └── requirements.md  ← already written
└── tasks.md             ← Phase 2 — created by /speckit.tasks
```

### Source Code (repository root, after migration)

```text
cardano-tx-tools/
├── lib-tx-generator/                          ← NEW: sublib root
│   └── Cardano/Tx/Generator/
│       ├── Build.hs
│       ├── Daemon.hs
│       ├── Fanout.hs
│       ├── Persist.hs
│       ├── Population.hs
│       ├── Selection.hs
│       ├── Server.hs
│       ├── Snapshot.hs
│       └── Types.hs
├── app/cardano-tx-generator/Main.hs           ← NEW: thin exe
├── test/Cardano/Tx/Generator/                 ← NEW: unit specs
│   ├── FanoutSpec.hs
│   ├── PersistSpec.hs
│   ├── PopulationSpec.hs
│   ├── SelectionSpec.hs
│   ├── ServerSpec.hs
│   └── SnapshotSpec.hs
├── test/Cardano/Tx/Generator/E2E/             ← NEW: e2e specs
│   ├── EnduranceSpec.hs
│   ├── IndexFreshSpec.hs
│   ├── ReadySpec.hs
│   ├── RefillSpec.hs
│   ├── RestartSpec.hs
│   ├── SnapshotSpec.hs
│   ├── StarvationSpec.hs
│   ├── SubmitIdempotenceSpec.hs
│   └── TransactSpec.hs
├── test/tx-generator-main.hs                  ← NEW: tx-generator-tests entry
├── test/e2e-main.hs                           ← NEW: e2e-tests entry
├── nix/docker-image.nix                       ← NEW: ported image
└── cardano-tx-tools.cabal                     ← MODIFIED: new stanzas
```

**Structure Decision**: TxGenerator lives in this repo as a separate
cabal sublibrary at `lib-tx-generator/`, with its own
`tx-generator-tests` test-suite stanza (distinct from `unit-tests`)
and its own `cardano-tx-generator` executable. This keeps
`cardano-tx-tools` the main library lightweight: anyone depending on
`cardano-tx-tools` (the main library) does NOT pull in TxGenerator's
heavy transitive deps (chain-follower, ouroboros-*, rocksdb-*);
only consumers of `cardano-tx-tools:tx-generator-lib` do. The
boundary mirrors the existing `n2c-resolver` sublib pattern.

## Complexity Tracking

No constitution violations. Section intentionally empty.

## Phase 0 — Research

Three architectural decisions need to be locked before Phase 1. The
full content lives in [`research.md`](./research.md); summary below.

### Decision 1 — Sublib vs second cabal package

**Decision**: Public cabal sublibrary inside the
`cardano-tx-tools` package.
**Rationale**: Keeps a single cabal package per repo, which keeps
release management (Cabal-owned release planner + tag-driven
artifact workflows already wired in PR #4) simple. The `n2c-resolver`
sublib precedent shows the pattern works. Downstream consumers of
the main library still pay zero cost.

### Decision 2 — E2E tests location

**Decision**: Move e2e tests to cardano-tx-tools alongside the
daemon. Add an `e2e-tests` test-suite that build-depends on
`cardano-node-clients:devnet` for `withCardanoNode`.
**Rationale**: The daemon is the system under test; the test suite
should live with the code it exercises. cardano-node-clients no
longer needs to host them once it stops shipping the binary.

### Decision 3 — Docker image host

**Decision**: Move `nix/docker-image.nix` to cardano-tx-tools and
publish the image from there. The image registry path changes from
`ghcr.io/lambdasistemi/cardano-node-clients/cardano-tx-generator`
to `ghcr.io/lambdasistemi/cardano-tx-tools/cardano-tx-generator`.
**Rationale**: The Docker image is a thin container around the
binary; it follows the binary.

## Phase 1 — Design & Contracts

Phase 1 produces three artifacts:

1. **`data-model.md`** — catalogue of the migrated modules, their
   public APIs (`Daemon.runTxGenerator`, server-protocol message
   types, etc.), and the inter-module dependency arrows within the
   new sublib. Also lists the external types the sublib touches
   (`ConwayTx` from `Cardano.Tx.Ledger`, `Provider` from
   `Cardano.Node.Client.Provider`).
2. **`contracts/cabal.md`** — the locked cabal stanza shape:
   - `library tx-generator-lib` visibility = `public`,
     `hs-source-dirs: lib-tx-generator`, `exposed-modules` list of
     the nine `Cardano.Tx.Generator.*` modules.
   - `executable cardano-tx-generator` `main-is: Main.hs`,
     `hs-source-dirs: app/cardano-tx-generator`, minimal
     `build-depends: { base, cardano-tx-tools:tx-generator-lib }`.
   - `test-suite tx-generator-tests`
     `type: exitcode-stdio-1.0`,
     `main-is: tx-generator-main.hs`,
     `hs-source-dirs: test`,
     `other-modules` listing the six `Cardano.Tx.Generator.*Spec`
     modules.
   - `test-suite e2e-tests` `build-depends:
     { cardano-node-clients:devnet, cardano-tx-tools,
       cardano-tx-tools:tx-generator-lib, ... }`.
3. **`quickstart.md`** — operator-facing impact summary:
   - Binary name unchanged.
   - Install path changes (release URL moves to cardano-tx-tools
     GitHub releases).
   - Docker image registry path changes (full path noted).
   - No CLI / control-socket changes.

The constitution's "Hackage-ready quality" principle requires the
sublib to keep complete Haddock headers and module-level
descriptions. The migration MUST preserve these from the source
files; the rename pass only touches `module ... where` declarations
and `import` statements, not Haddock prose.

## Constitution Re-Check (Post-Phase 1)

Same as the pre-check: all seven principles satisfied. The Phase 1
design adds two test-suite stanzas (`tx-generator-tests`,
`e2e-tests`) and one executable on top of the sublib, none of which
introduce new boundary-crossing imports beyond those already
sanctioned by the constitution.

## Status

**Completed**:
- Worktree at `/code/cardano-tx-tools-issue-6` on branch
  `001-tx-generator-migration`.
- Spec written and pushed (PR
  [#7](https://github.com/lambdasistemi/cardano-tx-tools/pull/7)).
- Quality checklist all-green.
- Phase 0 design decisions locked.
- Phase 1 artifact set defined above; concrete files written as part
  of `/speckit.plan`.

**Current**: Phase 1 artifacts being written; next step
`/speckit.tasks` to break the implementation into bisect-safe commit
slices.

**Blockers**: None. The cardano-node-clients companion deletion PR
(`/code/cardano-node-clients-issue-152`) is parked locally with the
deletions already staged; it cannot land until this PR + the
implementation slices merge.

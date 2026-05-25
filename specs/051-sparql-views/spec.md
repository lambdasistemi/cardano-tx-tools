# Feature Specification: SPARQL view library and tx-view executable

**Feature Branch**: `51-sparql-views`  
**Created**: 2026-05-25  
**Status**: Draft  
**Input**: GitHub issue #51 under epic #46: packaged SPARQL views for
the unified transaction graph plus a `tx-view` executable.

## User Scenarios & Testing

### User Story 1 - Render the cli-tree view (Priority: P1)

A transaction reviewer wants to render a graph emitted by `tx-graph` as
the same text tree produced by the rewrite-redesign harness, so the RDF
pipeline can replace `tx-inspect` without changing reviewer-facing text.

**Why this priority**: This is the acceptance anchor for #51 and the
bridge from the graph emitter back to the 044 text surface.

**Independent Test**: For each accepted rewrite-redesign stub fixture,
run `tx-view --graph <expected.ttl> --view cli-tree` and compare output
to a view-side golden under `test/fixtures/views/<slug>/cli-tree.txt`
after whitespace canonicalisation.

**Acceptance Scenarios**:

1. **Given** a fixture graph with the current canonical Turtle layout,
   **When** `tx-view --graph expected.ttl --view cli-tree` runs,
   **Then** the output is byte-equivalent to that fixture's view-side
   `cli-tree.txt` golden modulo whitespace canonicalisation.
2. **Given** a graph with no triples matching the cli-tree view,
   **When** `tx-view` runs,
   **Then** it exits 0 and emits an empty result.

---

### User Story 2 - Summarise asset movement (Priority: P1)

An operator reviewing the Amaru swap graph wants a compact asset-flow
summary with one line per asset class and source/destination entities.

**Independent Test**: Run `asset-flow` against the Amaru swap fixture and
assert the output is non-empty, mentions the moved asset classes and
quantities, and is structurally distinct from `entity-occurrences`.

**Acceptance Scenarios**:

1. **Given** the Amaru swap fixture graph, **When** `tx-view --view
   asset-flow` runs, **Then** each row identifies an asset class,
   quantity, source entity, and destination entity.
2. **Given** a graph without asset movement triples, **When** the view
   runs, **Then** the command exits 0 with an empty result.

---

### User Story 3 - Count entity occurrences (Priority: P1)

A rules author wants to know which declared entities are referenced most
often in a transaction graph, so rule coverage can be inspected quickly.

**Independent Test**: Run `entity-occurrences` against the Amaru swap
fixture and assert the output contains per-entity site counts.

**Acceptance Scenarios**:

1. **Given** a graph with operator-declared entities, **When** the view
   runs, **Then** each row contains an entity label and the count of
   leaf sites that reference that entity.
2. **Given** a graph without entity references, **When** the view runs,
   **Then** it exits 0 with an empty result.

---

### User Story 4 - Project graph JSON-LD for browser consumers (Priority: P1)

A browser integration wants a JSON-LD document from an existing Turtle
graph file, without needing to regenerate the graph from transaction
CBOR.

**Independent Test**: Run `tx-view --view json-ld` against a fixture
Turtle graph, parse the result as JSON, and assert its graph content
covers the same subject/predicate/object set as the Turtle input.

**Acceptance Scenarios**:

1. **Given** a valid canonical Turtle graph, **When** `tx-view --view
   json-ld` runs, **Then** stdout is parseable JSON-LD.
2. **Given** the parsed Turtle and parsed JSON-LD outputs, **When** the
   test compares triples in the supported graph subset, **Then** they
   are equal.

### Edge Cases

- `--view` defaults to `cli-tree`.
- `--out FILE` writes the selected view to a file and leaves stdout
  empty.
- Unknown view names fail with a usage-level error.
- Missing `--graph` file, malformed Turtle, or unwritable `--out` path
  fails non-zero with a clear stderr message.
- Empty result sets are successful results, not failures.
- The runner may rely on the canonical Turtle subset emitted by this
  repository; arbitrary Turtle syntax support is out of scope.

## Requirements

### Functional Requirements

- **FR-001**: The PR MUST add packaged view files
  `views/cli-tree.rq`, `views/asset-flow.rq`,
  `views/entity-occurrences.rq`, and `views/json-ld.rq`.
- **FR-002**: The PR MUST add executable `tx-view` with flags
  `--graph <file>`, `--view <name>` defaulting to `cli-tree`, and
  `--out <file>` defaulting to stdout.
- **FR-003**: `cli-tree` MUST produce graph-derived text for fixtures
  01 through 10 and compare against view-side `cli-tree.txt` goldens
  modulo whitespace canonicalisation.
- **FR-004**: `asset-flow` MUST produce a per-asset movement summary on
  the Amaru swap fixture.
- **FR-005**: `entity-occurrences` MUST produce per-entity occurrence
  counts on the Amaru swap fixture.
- **FR-006**: `json-ld` MUST produce parseable JSON-LD from a Turtle
  graph file without requiring transaction CBOR input.
- **FR-007**: JSON-LD output MUST preserve the supported triple content
  of the input Turtle graph.
- **FR-008**: Empty result sets MUST exit 0.
- **FR-009**: The view runner MUST NOT require a live node, Web2
  resolver, or network access.
- **FR-010**: The PR MUST NOT extend the `cardano:*` vocabulary.
- **FR-011**: The PR MUST NOT add operator-authored `--view-file`
  support.
- **FR-012**: The PR MUST add focused unit/exe-level coverage for each
  packaged view and CLI error path.
- **FR-013**: The PR MUST add one Unreleased / Features bullet in
  `CHANGELOG.md`.
- **FR-014**: The PR MUST document the deferred legacy 044
  `expected.txt` byte-equivalence target as follow-on issue #98 under
  `CHANGELOG.md` Deferred / known limitations.

### Key Entities

- **Packaged view**: A checked-in `.rq` file under `views/` that states
  the vendor-neutral SPARQL contract for a named projection.
- **View runner**: Haskell code that loads canonical Turtle and executes
  one packaged view name through an in-repo projection implementation.
- **Canonical graph**: Turtle emitted by the current `tx-graph` pipeline
  and stored in `test/fixtures/rewrite-redesign/*/expected.ttl`.

## Deliverables

- `views/*.rq` for the four named views.
- `app/tx-view/Main.hs` and cabal/nix app wiring for `tx-view`.
- `src/Cardano/Tx/View/*.hs` support modules if useful.
- `test/Cardano/Tx/ViewSpec.hs` or equivalent focused specs.
- `test/Cardano/Tx/View/CliTreeGoldenSpec.hs` for view-side cli-tree
  fixture goldens.
- Golden outputs under `test/fixtures/views/` if the worker pair chooses
  file-based goldens over inline assertions.
- `CHANGELOG.md` feature bullet.

## Success Criteria

- **SC-001**: `./gate.sh` exits successfully at the accepted
  implementation head.
- **SC-002**: The cli-tree tests cover fixtures 01 through 10 with
  view-side graph-derived goldens accepted in plan.md.
- **SC-003**: Asset-flow and entity-occurrences produce non-empty,
  structurally distinct Amaru swap outputs.
- **SC-004**: JSON-LD output parses and preserves supported triples.
- **SC-005**: An empty-match graph exits 0 for every view.
- **SC-006**: The branch diff does not touch emitter, rules-loader,
  blueprint-loader, or vocabulary definitions.

## Assumptions

- #95 is merged at `df59e55`, so the graph emitter has the current
  Conway semantic triple surface.
- A prior epic decision for the no-stub view rejected adding a SPARQL
  runtime dependency unless a future ticket proves it necessary. This
  ticket starts from the same constraint: packaged `.rq` files are the
  contract, and the Haskell runner is the in-repo execution engine.
- Parent answer A-001 accepted view-side cli-tree goldens for #51 and
  deferred byte-equivalence to the legacy 044 `expected.txt` corpus to
  follow-on issue #98.

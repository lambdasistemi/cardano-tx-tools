# Feature Specification: Amaru disburse DSL fixtures

**Feature Branch**: `90-amaru-disburse-fixtures-dsl`  
**Created**: 2026-05-23  
**Status**: Draft  
**Input**: GitHub issue #90 under epic #46: add two
DSL-reconstructed amaru-treasury disburse fixtures on top of the
SchemaMap support merged by #80 / PR #87.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Network-compliance disburse fixture is pinned (Priority: P1)

A maintainer running the transaction-to-RDF golden suite wants a
production-shaped network-compliance disburse transaction to exercise the
SchemaMap-decoded treasury spend redeemer path, so future emitter or
blueprint changes cannot silently lose the current output shape.

**Why this priority**: This is the first requested fixture and mirrors a
live `antithesis-disburse-draft` transaction with multiple treasury spend
inputs, required signers, reference inputs, and a zero-lovelace
withdrawal.

**Independent Test**: Run the rewrite-redesign golden suite with fixture
`15-amaru-disburse-network-compliance` enumerated and verify its
`expected.ttl`, `expected.entities.ttl`, and `expected.txt` match the
current emitter output byte-for-byte.

**Acceptance Scenarios**:

1. **Given** the network-compliance source transaction and matching
   Sundae treasury blueprint, **When** the golden suite renders fixture
   15, **Then** the fixture output includes typed
   `:TreasurySpendRedeemer_amount` predicates and byte-stable graph
   output.
2. **Given** the current typed-emit walker behavior for
   `OpenArray [OpenObject {"key", "value"}]`, **When** fixture 15 emits
   an amount child bnode, **Then** the fixture pins the truthful current
   opaque-child output rather than inventing per-entry triples.

---

### User Story 2 - Contingency disburse fixture is pinned (Priority: P1)

A maintainer wants a separate contingency disburse fixture from the
on-chain 4-of-4 multisig transaction, so the corpus covers both the
network-compliance disburse shape and the spent contingency shape without
depending on live node resolution.

**Why this priority**: The source transaction is already on-chain and its
inputs are spent; the fixture must be self-contained to preserve this
shape for offline regression testing.

**Independent Test**: Run the rewrite-redesign golden suite with fixture
`17-amaru-disburse-contingency` enumerated and verify its committed
golden files match the current emitter output byte-for-byte.

**Acceptance Scenarios**:

1. **Given** the contingency source transaction at block `60509ac5` and
   slot `187809147`, **When** the golden suite renders fixture 17,
   **Then** the self-contained DSL fixture preserves the 4-of-4 multisig
   disburse shape without live N2C lookup.
2. **Given** fixture 17's provenance notes, **When** a reviewer opens
   `NOTES.md`, **Then** the source transaction hash, source directory,
   and blueprint chain are recorded.

---

### User Story 3 - Existing fixture corpus remains stable (Priority: P1)

Maintainers need confidence that adding the two amaru disburse fixtures
does not perturb the already merged rewrite-redesign corpus.

**Why this priority**: The PR extends regression coverage. It must not
change prior fixture expectations or expand vocabulary scope.

**Independent Test**: Run `./gate.sh` and inspect the diff to confirm
fixtures 01 through 14 are byte-stable and no new `cardano:*` vocabulary
predicate is introduced.

**Acceptance Scenarios**:

1. **Given** the existing fixture corpus at HEAD, **When** the worker
   regenerates or verifies fixture expectations, **Then** fixtures 01
   through 14 remain unchanged.
2. **Given** the new fixture outputs, **When**
   `BlueprintPredicateTraceabilitySpec` runs, **Then** traceability passes
   without new canonical vocabulary terms.

---

### User Story 4 - Fixture provenance is reviewable (Priority: P2)

A reviewer wants each new fixture to explain where the transaction shape
and blueprint came from, so the corpus remains auditable after source
repositories and live ledger state move on.

**Why this priority**: The fixtures are manually reconstructed DSL
mirrors. Their value depends on clear provenance and source traceability.

**Independent Test**: Inspect each new fixture's `NOTES.md` and verify it
names the source transaction hash, source path, and blueprint source.

**Acceptance Scenarios**:

1. **Given** either new fixture directory, **When** a reviewer opens
   `NOTES.md`, **Then** it documents transaction hash, source path, and
   blueprint chain.
2. **Given** the copied blueprint file, **When** a reviewer traces its
   source, **Then** the notes identify whether it is the full
   `plutus.json` copy or a single-validator extraction from
   `/code/amaru-treasury/treasury-contracts/plutus.json`.

### Edge Cases

- If either source transaction cannot be mirrored by the existing
  transaction DSL without loading pre-built CBOR, implementation must
  stop and raise a Q-file before changing approach.
- If either fixture needs a new `cardano:*` vocabulary predicate,
  implementation must stop and raise a Q-file because vocabulary work is
  out of scope.
- If extending fixture 15 or 17 requires any
  `src/Cardano/Tx/Graph/Emit/*` or `src/Cardano/Tx/Blueprint.hs` change,
  implementation must stop and raise a Q-file; A-001 approved
  fixtures-only scope.
- The `OpenArray [OpenObject {"key", "value"}]` walker extension is
  explicitly deferred. The fixtures pin the current opaque-child output
  for that amount shape.
- The contingency source is spent on chain. The fixture must be
  self-contained and must not depend on live N2C resolution.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST add a rewrite-redesign fixture named
  `15-amaru-disburse-network-compliance`.
- **FR-002**: The system MUST add a rewrite-redesign fixture named
  `17-amaru-disburse-contingency`.
- **FR-003**: Each new fixture MUST include `rules.yaml`,
  `expected.ttl`, `expected.entities.ttl`, `expected.txt`, and
  `NOTES.md`.
- **FR-004**: The system MUST add DSL-reconstructed `ConwayTx` builders
  for fixtures 15 and 17 under
  `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/`.
- **FR-005**: The golden fixture enumeration MUST include fixtures 15 and
  17.
- **FR-006**: The system MUST include a Sundae treasury CIP-57 blueprint
  fixture at
  `test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json`,
  sourced from `/code/amaru-treasury/treasury-contracts/plutus.json` or a
  documented single-validator extraction.
- **FR-007**: Fixture 15 MUST mirror the source transaction shape:
  6 treasury script inputs plus 1 wallet input, 4 outputs, 2 required
  signers, 5 spend redeemers, 4 reference inputs, and one zero-lovelace
  withdrawal against the stake script.
- **FR-008**: Fixture 17 MUST mirror the source contingency disburse shape
  from the specified on-chain run directory and remain self-contained.
- **FR-009**: New fixture outputs MUST pin the current SchemaMap typed
  output, including `:TreasurySpendRedeemer_amount` parent predicates and
  the current opaque child bnode for the amount array/object map shape.
- **FR-010**: `BlueprintPredicateTraceabilitySpec` MUST pass on the new
  fixtures.
- **FR-011**: Existing rewrite-redesign fixtures 01 through 14 MUST remain
  byte-stable unless a Q-file answer explicitly authorizes drift.
- **FR-012**: The changelog MUST include one Unreleased / Features bullet
  summarizing the two amaru disburse fixtures.
- **FR-013**: The PR MUST NOT add or modify any
  `src/Cardano/Tx/Graph/Emit/*` file, `src/Cardano/Tx/Blueprint.hs`, new
  `cardano:*` vocabulary predicates, `amaru-treasury-tx`, release
  pipeline files, or non-DSL fixture construction.

### Key Entities *(include if feature involves data)*

- **Disburse fixture**: A checked-in rewrite-redesign case with a DSL
  `ConwayTx` builder, rules, golden text/Turtle/entity outputs, and
  provenance notes.
- **Treasury spend redeemer amount**: A SchemaMap-decoded value that
  currently emits a typed parent predicate and opaque child bnode for the
  `OpenArray [OpenObject {"key", "value"}]` shape.
- **Sundae treasury blueprint**: The CIP-57 blueprint source that maps
  the treasury spend script hash to typed datum/redeemer fields.

## Deliverables

- **Fixture 15**:
  `test/fixtures/rewrite-redesign/15-amaru-disburse-network-compliance/`
  plus
  `Fixtures/RewriteRedesign/S15_AmaruDisburseNetworkCompliance.hs`.
- **Fixture 17**:
  `test/fixtures/rewrite-redesign/17-amaru-disburse-contingency/` plus
  `Fixtures/RewriteRedesign/S17_AmaruDisburseContingency.hs`.
- **Shared blueprint**:
  `test/fixtures/rewrite-redesign/blueprints/sundae-treasury.cip57.json`.
- **Golden enumeration**: one-line fixture entries in
  `test/Cardano/Tx/Graph/EmitGoldenSpec.hs`.
- **Documentation**: fixture `NOTES.md` files and one `CHANGELOG.md`
  bullet.
- **Surfaces intentionally not touched**: `src/`, `.github/`,
  `flake.nix`, `nix/`, `docs/`, and other repositories.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `./gate.sh` exits successfully at the accepted
  implementation head.
- **SC-002**: The golden suite enumerates and verifies fixture slugs
  `15-amaru-disburse-network-compliance` and
  `17-amaru-disburse-contingency`.
- **SC-003**: The branch diff contains no changes to existing fixtures 01
  through 14.
- **SC-004**: The new fixture outputs contain
  `:TreasurySpendRedeemer_amount` and preserve the current opaque child
  output for the amount map shape.
- **SC-005**: `BlueprintPredicateTraceabilitySpec` passes without adding
  any new `cardano:*` vocabulary term.
- **SC-006**: Each new fixture has a `NOTES.md` with transaction hash,
  source path, and blueprint source.

## Assumptions

- PR #87 / child #80 is merged into `origin/main` at `b2ecf6a`, so
  SchemaMap support is available before this branch starts.
- The network-compliance source transaction lives at
  `/code/amaru-treasury-tx-issue-237/transactions/2026/network_compliance/antithesis-disburse-draft/tx.cbor.hex`.
- The contingency source transaction lives under
  `/code/amaru-treasury-tx/transactions/2026/contingency/18d57a4f104df4cc776104ce626958e2110122392e4c4c7671edc8861b48452e/`.
- The implementation workers may inspect source transaction artifacts and
  existing fixture patterns, but this ticket does not modify source
  repositories outside `cardano-tx-tools`.

# Research: Amaru disburse DSL fixtures

## Decision: Ship fixture-only Option 1

**Rationale**: A-001 confirms that the issue body is canonical. The PR
must pin the current truthful SchemaMap output, where
`:TreasurySpendRedeemer_amount` points at an opaque child bnode for the
`OpenArray [OpenObject {"key", "value"}]` amount shape. The typed-emit
walker extension is structurally different emitter work and belongs in a
follow-on issue after this PR merges.

**Alternatives considered**:

- Implement the walker extension first. Rejected by A-001 because it
  widens the PR and blurs the bisect boundary between fixture
  reconstruction and emitter semantics.

## Decision: Use one shared Sundae treasury blueprint fixture

**Rationale**: Both fixture directories use the same treasury spend script
hash and blueprint chain. A shared file under
`test/fixtures/rewrite-redesign/blueprints/` avoids duplicating a large
CIP-57 JSON blob and matches the existing blueprint fixture layout.

**Alternatives considered**:

- Copy the blueprint into each fixture directory. Rejected because it
  creates two copies to review and update while adding no coverage.
- Extract only the single validator. Permitted if the worker documents
  the extraction in `NOTES.md`, but the plan defaults to a full source
  copy from `/code/amaru-treasury/treasury-contracts/plutus.json` unless
  file size or loader constraints require extraction.

## Decision: Split implementation into two fixture slices

**Rationale**: Each fixture is expected to be 150-200 lines of careful DSL
reconstruction plus goldens and notes. Separate driver+navigator slices
keep review focused, while the final changelog slice remains mechanical.

**Alternatives considered**:

- One large implementation slice for both fixtures. Rejected because it
  would combine two substantial reconstruction efforts in one review
  unit.

## Decision: Treat live resolution as verification aid, not fixture input

**Rationale**: Fixture 15's source may be easier to inspect with live or
source-repo tools, but committed fixtures must be self-contained DSL
mirrors. Fixture 17's inputs are spent and cannot depend on N2C
resolution.

**Alternatives considered**:

- Load pre-built CBOR or rely on N2C resolution in the fixture harness.
  Rejected by the harness convention and issue scope.

## Decision: No vocabulary or source-module changes

**Rationale**: The new outputs must use existing default-namespace typed
predicates and existing `cardano:*` vocabulary. A-001 explicitly forbids
`src/Cardano/Tx/Graph/Emit/*` and `src/Cardano/Tx/Blueprint.hs` changes.

**Alternatives considered**:

- Opportunistically add missing vocabulary or walker behavior. Rejected;
  both require separate scope.

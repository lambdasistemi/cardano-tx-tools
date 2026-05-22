# Feature Specification: Real Conway amaru disburse fixtures

**Feature Branch**: `80-amaru-disburse-fixtures`  
**Created**: 2026-05-22  
**Status**: Draft  
**Input**: GitHub issue #80 under epic #46: add three real
`amaru-treasury-tx` disburse fixtures and close the observed CIP-57
JSON-Pointer `$ref` normalization gap.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real disburse datums decode as typed RDF (Priority: P1)

An operator running the transaction-to-RDF graph emitter against real
Conway treasury disburse transactions wants the emitted Turtle to expose
script-domain redeemer and datum fields through blueprint-derived
predicates rather than falling back to opaque CBOR bytes.

**Why this priority**: This is the ticket's main value. The typed emitter
from #50 must be proven against production-shaped treasury transactions,
not only synthetic fixtures.

**Independent Test**: Run the rewrite-redesign golden suite on the three
new amaru disburse fixtures and verify their Turtle outputs contain
typed `:TreasurySpendRedeemer_*` predicates with no
`BlueprintUnresolvedReference` decode errors.

**Acceptance Scenarios**:

1. **Given** a minimal signed disburse transaction with the matching
   CIP-57 blueprint chain, **When** the graph emitter renders the fixture,
   **Then** the datum/redeemer shape contains typed treasury predicates
   and byte-stable golden output.
2. **Given** a full four-owner multisig signed disburse transaction with
   the matching blueprint chain, **When** the graph emitter renders the
   fixture, **Then** typed treasury predicates are emitted while all
   witness-set and body fields stay byte-stable.
3. **Given** a representative contingency disburse transaction if one
   exists in the source corpus, **When** the graph emitter renders the
   fixture, **Then** the contingency shape is preserved in byte-stable
   Turtle and entity output.

---

### User Story 2 - Escaped JSON-Pointer references resolve (Priority: P1)

A blueprint author may legally use RFC 6901 escapes in a `$ref`, such as
`#/definitions/types~1TreasurySpendRedeemer`. The resolver must look up
the decoded definition name `types/TreasurySpendRedeemer` rather than the
literal escaped token.

**Why this priority**: Without this fix, real SundaeSwap-style treasury
blueprints decode-fail even though their schemas are valid.

**Independent Test**: A focused BlueprintSpec invariant uses a `$ref`
containing `~1` and proves it resolves to the expected definition. The
fixture outputs then prove the same behavior end-to-end.

**Acceptance Scenarios**:

1. **Given** a blueprint definition named `types/TreasurySpendRedeemer`,
   **When** a schema references it as
   `#/definitions/types~1TreasurySpendRedeemer`, **Then** schema
   resolution returns the definition instead of
   `BlueprintUnresolvedReference`.
2. **Given** a blueprint definition name containing a literal tilde,
   **When** a schema references it through RFC 6901 `~0`, **Then** the
   resolver decodes the pointer token before lookup.

---

### User Story 3 - Fixture provenance is reviewable (Priority: P2)

A reviewer wants each new fixture to explain where its transaction bytes
and blueprint chain came from, so the corpus remains auditable after the
source repository moves on.

**Why this priority**: Real-shape fixtures are only useful if their
source, transaction hash, and blueprint provenance are documented.

**Independent Test**: Inspect each fixture's `NOTES.md` and verify it
names the transaction hash, the source `amaru-treasury-tx` commit or PR,
and the blueprint chain that produced the datum/redeemer schema.

**Acceptance Scenarios**:

1. **Given** any new fixture directory, **When** a reviewer opens
   `NOTES.md`, **Then** it contains the tx hash, source commit or PR, and
   blueprint chain.
2. **Given** a missing contingency transaction in the source corpus,
   **When** the worker cannot identify a representative tx, **Then** the
   worker escalates by Q-file before substituting a different shape.

---

### User Story 4 - Existing fixtures do not drift (Priority: P1)

Maintainers need confidence that adding real-shape disburse fixtures and
normalizing blueprint references does not perturb the existing
rewrite-redesign corpus.

**Why this priority**: The new corpus is a stress extension. It must not
change the baseline semantics of the already merged emitter.

**Independent Test**: Run the golden suite and compare all pre-existing
fixtures byte-for-byte against their checked-in expectations.

**Acceptance Scenarios**:

1. **Given** the current rewrite-redesign fixture set at HEAD, **When**
   the worker regenerates or verifies expectations, **Then** fixtures
   `01` through `14` remain byte-stable unless a task explicitly
   documents an accepted upstream drift.
2. **Given** any emitted `cardano:*` predicate in the new fixtures,
   **When** traceability checks run, **Then** no new vocabulary predicate
   is required for this PR.

### Edge Cases

- If the `disburse/` corpus lacks a representative contingency
  transaction, implementation must stop and raise a Q-file instead of
  inventing a replacement outside the issue scope.
- If any new fixture needs a new `cardano:*` vocabulary term, the worker
  must stop and raise a Q-file because vocabulary work is out of scope.
- If a transaction CBOR or blueprint chain from `amaru-treasury-tx`
  cannot be decoded even after RFC 6901 normalization, the worker must
  raise a Q-file because that indicates a deeper shape gap.
- `$ref` normalization must only implement RFC 6901 token decoding
  (`~1` to `/`, `~0` to `~`); broader resolver behavior is out of scope.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST add three new rewrite-redesign fixtures
  named `15-amaru-disburse-minimal`, `16-amaru-disburse-multisig`, and
  `17-amaru-disburse-contingency`.
- **FR-002**: Each new fixture MUST include `rules.yaml`,
  `expected.ttl`, `expected.entities.ttl`, `expected.txt`, and
  `NOTES.md`.
- **FR-003**: Each fixture `NOTES.md` MUST document the transaction hash,
  the source `amaru-treasury-tx` commit or PR, and the blueprint chain
  used for datum/redeemer decoding.
- **FR-004**: The golden fixture enumeration MUST include fixtures 15,
  16, and 17.
- **FR-005**: Blueprint `$ref` resolution MUST decode RFC 6901
  JSON-Pointer escapes `~1` and `~0` before definition lookup.
- **FR-006**: A focused blueprint unit invariant MUST prove a `~1`-bearing
  `$ref` resolves to the expected definition.
- **FR-007**: The new fixture outputs MUST show typed treasury predicates
  such as `:TreasurySpendRedeemer_*` and MUST NOT pin
  `BlueprintUnresolvedReference` decode errors for valid escaped refs.
- **FR-008**: The existing rewrite-redesign fixture expectations MUST
  remain byte-stable unless a worker records a Q-file and receives an
  answer authorizing drift.
- **FR-009**: `BlueprintPredicateTraceabilitySpec` MUST pass on the new
  fixtures.
- **FR-010**: The changelog MUST include one Unreleased / Features bullet
  summarizing the real Conway fixtures and RFC 6901 normalization.
- **FR-011**: The PR MUST NOT add `cardano:*` vocabulary predicates,
  change `leafTypeFromFieldName`, modify `amaru-treasury-tx`, or touch
  release-pipeline surfaces.

### Key Entities *(include if feature involves data)*

- **Disburse fixture**: A checked-in rewrite-redesign case sourced from a
  real `amaru-treasury-tx` transaction and paired with golden text,
  Turtle, entity Turtle, rules, and provenance notes.
- **Blueprint reference**: A CIP-57 schema `$ref` whose JSON-Pointer token
  may contain RFC 6901 escapes.
- **Treasury typed predicate**: A default-namespace RDF predicate minted
  from blueprint constructor and field names for decoded treasury datum or
  redeemer values.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `./gate.sh` exits successfully at the accepted
  implementation head.
- **SC-002**: The golden suite enumerates and verifies exactly the three
  new fixture slugs required by FR-001.
- **SC-003**: No pre-existing rewrite-redesign fixture expectation changes
  as a side effect of the RFC 6901 resolver fix.
- **SC-004**: A unit test fails on the pre-fix resolver and passes after
  decoding `~1` and `~0` before definition lookup.
- **SC-005**: The new fixture outputs contain typed treasury predicates
  and contain zero valid-schema `BlueprintUnresolvedReference` errors.
- **SC-006**: Each new fixture has a `NOTES.md` with all three provenance
  fields from FR-003.

## Assumptions

- PR #79 / child #50 is already merged into `origin/main` at `71fac60`.
- The source corpus lives in `lambdasistemi/amaru-treasury-tx` under
  `transactions/` with matching blueprints under `rules/`.
- The implementation worker may inspect the relevant source repository
  and this repository's existing fixture patterns, but this orchestrator
  will not edit worker-owned code or fixture files.
- If the exact contingency representative does not exist, the ticket
  owner needs parent arbitration before changing the fixture set.

# Feature Specification: Typed-emit walker per-entry triples

**Feature Branch**: `95-walker-ext-openarray-openobject`  
**Created**: 2026-05-23  
**Status**: Draft  
**Input**: GitHub issue #95 under epic #46: extend the typed-emit
walker for SchemaMap-decoded `OpenArray [OpenObject {"key",
"value"}, ...]` values.

## User Scenarios & Testing

### User Story 1 - Map-entry triples are materialised (Priority: P1)

A maintainer reviewing typed RDF output for Sundae treasury spend
redeemers wants SchemaMap decoded amounts to expose their map entries,
so the graph no longer has a typed parent predicate pointing at an empty
blank node.

**Why this priority**: This is the core gap left after #80 and #90.
Fixtures 15 and 17 currently show `:TreasurySpendRedeemer_amount
_:redeemerDataN_amount .` with no body on that child.

**Independent Test**: A focused emit-side spec constructs or decodes an
`OpenArray [OpenObject {"key", "value"}, ...]` value, runs the typed
emit helper, and asserts a positional entry bnode with `:key` and
`:value` triples is emitted.

**Acceptance Scenarios**:

1. **Given** a decoded OpenValue shaped as an array of objects with
   exactly the fields `key` and `value`, **When** the typed emit walker
   renders it as the object of a parent predicate, **Then** it emits
   positional entry links from the array bnode and per-entry `:key` /
   `:value` triples.
2. **Given** a non-map array or object that is not exactly the
   two-field map-entry shape, **When** the walker renders it, **Then**
   existing opaque or nested-object behavior is preserved.

---

### User Story 2 - Real disburse goldens expose entry bodies (Priority: P1)

A reviewer wants the two real Conway disburse fixtures introduced by
#90 to carry the new map-entry triples, so those fixtures pin the
SchemaMap follow-on behavior on production-shaped transactions.

**Independent Test**: Regenerate only fixtures 15 and 17 expected Turtle,
then run the rewrite-redesign golden suite.

**Acceptance Scenarios**:

1. **Given** fixture 15, **When** `EmitGoldenSpec` serializes the graph,
   **Then** its `expected.ttl` includes per-entry triples under the
   `:TreasurySpendRedeemer_amount` child bnodes.
2. **Given** fixture 17, **When** `EmitGoldenSpec` serializes the graph,
   **Then** its `expected.ttl` includes the same entry shape.

---

### User Story 3 - Existing corpus remains stable (Priority: P1)

Maintainers need confidence that the walker extension fires only for the
SchemaMap-derived map-entry shape and does not change older fixtures.

**Independent Test**: After regeneration, the branch diff changes
fixtures 15 and 17 only; fixtures 01 through 14 remain byte-stable.

**Acceptance Scenarios**:

1. **Given** fixtures 01 through 14 at branch start, **When** the
   implementation and golden regeneration are complete, **Then** none of
   their `expected.ttl` files differ.
2. **Given** the blueprint predicate traceability sweep, **When** the
   new `:key` and `:value` predicates appear, **Then** the traceability
   rule either recognizes them as reserved walker predicates or remains
   scoped so no unrelated default-namespace predicates pass silently.

### Edge Cases

- Empty map arrays remain a referenced bnode with no entry links.
- An array element that is not an `OpenObject` with exactly `key` and
  `value` fields must not trigger the map-entry case.
- An object with extra fields such as `key`, `value`, and `tag` must not
  trigger the map-entry case.
- Nested map values may produce nested positional entry bnodes by
  reusing the same structural rule; if this requires a broader naming
  convention than the plan pins, the worker pair must stop and Q-file.
- No new `cardano:*` vocabulary term is allowed.

## Requirements

### Functional Requirements

- **FR-001**: The typed emit walker MUST recognize the structural
  `OpenArray [OpenObject {"key", "value"}, ...]` shape.
- **FR-002**: For each map-entry array element, the walker MUST emit a
  positional entry link from the array bnode using `:_<i>`, where `i` is
  zero-based and follows the decoded array order.
- **FR-003**: Each entry bnode MUST emit `:key` and `:value` triples
  whose objects are rendered through the existing `OpenValue` rendering
  path.
- **FR-004**: The walker MUST preserve existing behavior for non-map
  `OpenArray` values and non-matching `OpenObject` values.
- **FR-005**: The implementation MUST keep `OpenValue` stable; it MUST
  NOT add an `OpenMap` constructor.
- **FR-006**: The PR MUST add one emit-side invariant that fails before
  the walker case and pins the shape decision.
- **FR-007**: Fixture 15 `expected.ttl` MUST be regenerated with the new
  per-entry triples.
- **FR-008**: Fixture 17 `expected.ttl` MUST be regenerated with the new
  per-entry triples.
- **FR-009**: Fixtures 01 through 14 MUST remain byte-stable.
- **FR-010**: `BlueprintPredicateTraceabilitySpec` MUST be updated if
  needed so `:key` and `:value` are handled deliberately, not by
  accidental vacuous scoping.
- **FR-011**: `CHANGELOG.md` MUST include one Unreleased / Features
  bullet for issue #95.
- **FR-012**: The PR MUST NOT add fixtures, cabal dependencies, release
  pipeline edits, or new canonical vocabulary predicates.

### Key Entities

- **Map-entry OpenArray**: An `OpenArray` whose every element is an
  `OpenObject` with exactly two keys, `key` and `value`.
- **Array bnode**: The blank node already used as the object of the
  parent typed predicate.
- **Entry bnode**: A new child blank node addressed positionally from
  the array bnode and carrying `:key` / `:value`.

## Deliverables

- Walker extension in `src/Cardano/Tx/Graph/Emit/Project.hs` and/or
  `src/Cardano/Tx/Graph/Emit/Witness.hs`.
- One focused emit-side invariant in `test/Cardano/Tx/Graph/Emit/BlueprintSpec.hs`
  or a dedicated adjacent spec.
- Regenerated `expected.ttl` for fixtures 15 and 17 only.
- Traceability spec adjustment if required.
- One `CHANGELOG.md` bullet under Unreleased / Features.

## Success Criteria

- **SC-001**: `./gate.sh` exits successfully at the accepted
  implementation head.
- **SC-002**: The focused emit-side invariant fails before the walker
  case and passes after it.
- **SC-003**: Fixture 15 and 17 goldens include `:key` and `:value`
  triples under the SchemaMap amount bnodes.
- **SC-004**: No fixture `expected.ttl` outside 15 and 17 changes.
- **SC-005**: No branch diff adds a `cardano:key`, `cardano:value`, or
  other new canonical vocabulary term.

## Assumptions

- #80 / PR #87 is merged at `b2ecf6a`, so SchemaMap decoding already
  materialises maps as `OpenArray [OpenObject {"key", "value"}, ...]`.
- #90 / PR #92 is merged at `5939d79`, so fixtures 15 and 17 exist and
  currently pin the empty-child output.
- Positional `:_<i>` entry links are consistent with existing typed emit
  bnode naming and do not need schema-title context.

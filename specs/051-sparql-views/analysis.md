# Cross-Artifact Analysis: SPARQL view library and tx-view executable

**Feature**: [spec.md](./spec.md)  
**Plan**: [plan.md](./plan.md)  
**Tasks**: [tasks.md](./tasks.md)  
**Date**: 2026-05-25

## Result

No blocking inconsistencies found. The spec, plan, and tasks agree on
scope, slice order, forbidden surfaces, and verification strategy.

## Alignment Checks

### Requirements Coverage

- FR-001 packaged `.rq` files maps to T101, T201, T301, and T401.
- FR-002 `tx-view` CLI maps to T102 and T108.
- FR-003 `cli-tree` byte-equivalence maps to T105 and T106.
- FR-004 `asset-flow` maps to T202 and T203.
- FR-005 `entity-occurrences` maps to T302 and T303.
- FR-006 and FR-007 `json-ld` maps to T402 through T404.
- FR-008 empty results map to T107, T204, T405, and the shared CLI
  behavior in T102.
- FR-009 offline behavior is enforced by plan constraints and the
  absence of resolver/node tasks.
- FR-010 through FR-011 forbidden scope is repeated in plan.md and
  worker acceptance requirements.
- FR-012 tests map to each worker slice's focused test tasks.
- FR-013 changelog maps to T450.

### Slice Consistency

The plan names five implementation slices plus finalization. tasks.md
uses the same order and commit subjects:

1. `cli-tree`
2. `asset-flow`
3. `entity-occurrences`
4. `json-ld`
5. `changelog-polish`
6. final gate drop

The changelog is a separate docs slice to avoid forcing unrelated
documentation into one of the view behavior commits.

### Design Decision Coverage

- The `--no-reason` fallback is pinned as D-001.
- The SPARQL runtime strategy is pinned as D-002, including the Q-file
  escalation rule for dependencies or non-Haskell runtimes.
- Sequential slice cadence is pinned as D-003 and reflected in tasks.
- Fixture corpus ambiguity is pinned as D-004 so the worker pair starts
  from fixtures 01 through 10 and may include 11 if it is already in the
  active text corpus.

### Risk Review

- **SPARQL drift risk**: The `.rq` files are contracts while the Haskell
  runner executes typed projections. Mitigation: every view slice must
  include tests that prove the intended behavior over real fixture
  graphs, and any need for a real SPARQL runtime requires Q-file
  approval.
- **cli-tree size risk**: Rebuilding 044 text from graph triples may be
  the widest slice. Mitigation: make `cli-tree` first and let later
  slices depend on a stable graph reader and CLI skeleton.
- **Fixture corpus ambiguity**: The issue says 10 harness #45 fixtures,
  but the repo now has later fixture directories. Mitigation: D-004
  scopes mandatory coverage to 01 through 10 and allows fixture 11 only
  if already active in the 044-compatible registry.
- **Dependency drift risk**: Cabal/nix edits are permitted only for
  exposing `tx-view` and tests. Runtime/tool additions need Q-file
  approval.

## Open Questions

None for parent arbitration at planning time. If implementation proves
the no-new-SPARQL-runtime strategy cannot satisfy acceptance, the
worker pair must stop and the ticket owner will file a Q-file.

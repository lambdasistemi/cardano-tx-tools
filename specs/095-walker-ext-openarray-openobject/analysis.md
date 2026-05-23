# Specification Analysis Report

## Findings

| ID | Category | Severity | Location(s) | Summary | Recommendation |
|----|----------|----------|-------------|---------|----------------|
| C1 | Consistency | RESOLVED | spec.md FR-002/FR-003, plan.md D-001, tasks.md T102/T103 | The issue asks to pin the triple shape. The artifacts now all select positional `:_<i>` links with per-entry `:key` / `:value`. | Keep the worker brief aligned to D-001 and reject schema-title naming unless a Q-file amends the plan. |
| C2 | Scope | RESOLVED | spec.md FR-005, plan.md D-002, tasks.md T105 | The issue offers `OpenMap` as an alternative, but the brief recommends structural detection to preserve `OpenValue`. | The plan explicitly forbids adding `OpenMap`; the worker owns only the structural walker case. |
| C3 | Coverage | LOW | spec.md FR-010, tasks.md T109 | Traceability may fail because `:key` and `:value` are reserved walker predicates rather than blueprint-declared `:<ctor>_<field>` predicates. | Worker must run the traceability spec and either prove current scoping is deliberate or add a narrow reserved-predicate treatment. |

## Coverage Summary

| Requirement Key | Has Task? | Task IDs | Notes |
|-----------------|-----------|----------|-------|
| FR-001 structural recognition | Yes | T101 | OpenArray-of-exact-key/value objects. |
| FR-002 positional links | Yes | T102 | `:_<i>`, zero-based. |
| FR-003 key/value triples | Yes | T103 | Reuses existing OpenValue object rendering. |
| FR-004 preserve non-match behavior | Yes | T104 | Explicit negative cases. |
| FR-005 keep OpenValue stable | Yes | T105 | No `OpenMap`. |
| FR-006 emit-side invariant | Yes | T100 | RED-first requirement. |
| FR-007 fixture 15 regen | Yes | T106 | `expected.ttl` only. |
| FR-008 fixture 17 regen | Yes | T107 | `expected.ttl` only. |
| FR-009 fixtures 01-14 stable | Yes | T108 | Diff check plus gate. |
| FR-010 traceability deliberate | Yes | T109 | Update only if needed. |
| FR-011 changelog | Yes | T110 | Unreleased / Features bullet. |
| FR-012 forbidden scope | Yes | Worker Slice Contract | Stop/Q-file condition. |
| SC-001 gate green | Yes | T111, T200 | Behavior and finalization gates. |
| SC-002 focused RED/GREEN | Yes | T100, T111 | Worker must record both. |
| SC-003 fixture triples | Yes | T106, T107 | Goldens pin real fixture output. |
| SC-004 no other fixture drift | Yes | T108 | Branch diff check. |
| SC-005 no new vocab term | Yes | T109, contract | No `cardano:*` additions. |

## Constitution Alignment Issues

None. The plan preserves Conway-only scope, default-offline operation,
Hackage-ready verification through `./gate.sh`, and vertical
bisect-safe behavior commits.

## Unmapped Tasks

None. T000-T004 are orchestration lifecycle tasks; T200 is finalization.
All worker tasks map to requirements or success criteria.

## Metrics

- Total functional requirements: 12
- Total buildable success criteria: 5
- Total tasks: 18
- Coverage: 100%
- Ambiguity count: 0 after D-001/D-002
- Duplication count: 0
- Critical issues count: 0

## Next Actions

- Mark T000-T004 done in the planning commit.
- Commit the spec artifacts and gate.
- Open or update the draft PR.
- Dispatch the `openarray-openobject-walker` driver/navigator pair.

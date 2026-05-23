# Specification Analysis Report

## Findings

| ID | Category | Severity | Location(s) | Summary | Recommendation |
|----|----------|----------|-------------|---------|----------------|
| C1 | Coverage | LOW | plan.md Vertical Slices, tasks.md T400 | The handoff asks for the final behavior subject `feat(090): amaru-disburse fixtures (network_compliance + contingency)`, while the plan splits fixture implementation into two worker commits for reviewability. | Coordinate with the epic owner before final history shaping. The task plan records per-slice subjects and the required final subject so this remains explicit. |
| C2 | Consistency | RESOLVED | spec.md FR-007, data-model.md Network-Compliance Shape, tasks.md T201/T206 | A-002 superseded the removed `antithesis-disburse-draft` path and authorizes the available `affe90d1...` source shape. | Spec/plan/tasks now name the canonical `affe90d1...` source and observed 5-treasury-input / 3-output shape. |

## Coverage Summary

| Requirement Key | Has Task? | Task IDs | Notes |
|-----------------|-----------|----------|-------|
| FR-001 fixture 15 | Yes | T200-T208 | Covers RED, builder, rules, goldens, notes, verification. |
| FR-002 fixture 17 | Yes | T300-T307 | Covers RED, builder, rules, goldens, notes, verification. |
| FR-003 fixture file set | Yes | T202, T205, T206, T302, T304, T305 | File sets repeated in worker briefs. |
| FR-004 DSL builders | Yes | T201, T301 | Explicit builder module tasks. |
| FR-005 golden enumeration | Yes | T204, T303 | One enumeration task per fixture. |
| FR-006 shared blueprint | Yes | T203 | Fixture 17 reuses the shared file. |
| FR-007 network-compliance shape | Yes | T201, T205 | Shape is in spec/data model and slice brief. |
| FR-008 contingency shape | Yes | T301, T304, T305 | Includes self-contained source provenance. |
| FR-009 current opaque amount child | Yes | T205, T304 | Workers pin current emitter output; no walker changes. |
| FR-010 traceability | Yes | T207, T306 | Explicit traceability verification. |
| FR-011 existing fixture stability | Yes | T207, T306 | Byte-stability checks per slice. |
| FR-012 changelog | Yes | T400 | Mechanical polish task. |
| FR-013 forbidden scope | Yes | Worker Slice Contracts | Enforced in task contract and Q-file stop conditions. |
| SC-001 gate green | Yes | T208, T307, T401 | Gate before handoff and finalization. |
| SC-002 fixture verification | Yes | T204, T205, T303, T304 | Enumeration plus expected-output verification. |
| SC-003 no pre-existing drift | Yes | T207, T306 | Explicit byte-stability verification. |
| SC-004 amount output pin | Yes | T205, T304 | Pins current `TreasurySpendRedeemer_amount` shape. |
| SC-005 traceability/no vocab | Yes | T207, T306 | No new vocabulary accepted. |
| SC-006 provenance complete | Yes | T206, T305 | Notes acceptance. |

## Constitution Alignment Issues

None. The plan preserves Conway-only scope, default-offline operation,
Hackage-ready verification through `./gate.sh`, and vertical
bisect-safe behavior commits.

## Unmapped Tasks

None. T000-T004 are orchestration lifecycle tasks; T400-T401 are polish
and finalization. All worker tasks map to requirements or success
criteria.

## Metrics

- Total functional requirements: 13
- Total buildable success criteria: 6
- Total tasks: 23
- Coverage: 100%
- Ambiguity count: 1 known history-shaping coordination point
- Duplication count: 0
- Critical issues count: 0

## Next Actions

- Commit the spec artifacts.
- Dispatch the `15-amaru-disburse-network-compliance` driver/navigator
  pair.
- Include C1 in the finalization checklist before dropping `gate.sh`.

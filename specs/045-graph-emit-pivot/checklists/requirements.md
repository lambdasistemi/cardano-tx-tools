# Specification Quality Checklist: Transaction-to-RDF emitter

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-05-19
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs) — Haskell reference is needed for the engine-home decision and is unavoidable for an engine-replacement spec; reasoner choice (EYE) is identified as a clarification because the choice is load-bearing for the operator-facing surface.
- [x] Focused on user value and business needs — the load-bearing payoff is "views for free" and "cross-leaf identity as deduction", both reviewer-facing.
- [x] Written for non-technical stakeholders — User Stories 1–4 + Reference Acceptance are readable without RDF expertise; Key Entities section is necessarily technical (it IS the vocabulary work).
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain — Phase 0 of the plan addresses the remaining ontology-detail questions
- [x] Requirements are testable and unambiguous — every FR has at least one User Story acceptance scenario or a measurable SC
- [x] Success criteria are measurable — SC-001 (10/10 goldens), SC-002 (count of `owl:sameAs` deductions), SC-006 (<2s pipeline)
- [x] Success criteria are technology-agnostic — pipeline time is on "developer laptop"; byte-equality is verifiable without implementation details
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified — 7 edge cases: zero-identifier entity, cross-rule-file deduction, unmatched entity, reasoner failure, view-vs-ontology drift, malformed Turtle, blueprint decode failure
- [x] Scope is clearly bounded — Phase A (this spec) vs Phase B / Phase C (future tickets) explicitly delineated; SHACL extensibility deferred
- [x] Dependencies and assumptions identified — eight assumptions covering ontology coupling, reasoner availability, operator authoring, CIP timing, 044 supersession, harness re-aiming

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria — FR-001..FR-016 each map to specific user stories or SCs
- [x] User scenarios cover primary flows — P1 (basic pipeline + cross-leaf identity); P2 (multi-view + rule composition); Reference Acceptance covers the 10 044 transactions
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification — modulo the necessary engine + reasoner choices

## Relationship to spec 044

- 044's User Stories 1–10 are **preserved structurally** as the Reference Acceptance contract.
- 044's plan slices, data-model, and contracts are **obsoleted** — 045 plan re-issues them against the RDF target.
- 044's branch + PR will be **closed as superseded** once 045's engine + ontology PRs land.
- The harness ticket [#45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45) is re-aimed (same ten tx builders; expected-output format changes from text to Turtle + SPARQL view).

## Cross-references against open tickets

Issue closure carries over from 044's checklist. The mechanism changes (deduction instead of substitution) but the cross-leaf-identity property each ticket needs is delivered:

| Issue | Mechanism in 045 |
|---|---|
| #34 stake | `cardano:StakeKey` / `cardano:StakeScript` leaf types; entity rule's `from-address` extracts both halves |
| #35 pool | `cardano:PoolId` leaf type; entity rule's `pool:` sugar |
| #36 DRep | `cardano:DRepKey` / `cardano:DRepScript` leaf types; CIP-129 prefix dispatch |
| #37 asset-policy | `cardano:Policy` leaf type; same-bytes-as-script handled by allowing one entity to declare multiple identifier types |
| #38 asset-name | `cardano:AssetClass` compound key (`policy <> name`) |
| #39 datum rename | Blueprint decode emits typed triples; reasoner deduces `owl:sameAs` to entity URIs; no special path needed |
| #40 nested collapse + raw:omit | SPARQL view query handles collapse + view modes; engine-side support optional (different views for different operators) |
| #43 collapse-suppresses-rename | Dissolved: there is no separate collapse engine; everything is triples; SPARQL view does the bucketing |

## Notes

- Items marked incomplete require spec updates before `/speckit.clarify` or `/speckit.plan`
- Per project policy (no_specs_means_invented, speckit_stop_at_spec): no `/speckit.plan` and no `/speckit.tasks` until the user approves spec.md.
- Per user direction this session: the RDF + reasoner pivot is the load-bearing design decision; nomenclature criticality drove the choice to extend `cardano-knowledge-maps` rather than greenfield.

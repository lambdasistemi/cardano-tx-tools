# Research: Real Conway amaru disburse fixtures

## Decision: Fold RFC 6901 normalization into the fixture slice

**Rationale**: The unit invariant proves the resolver behavior, but the
real disburse fixtures are the acceptance proof that the typed emitter no
longer degrades on SundaeSwap-style treasury blueprints. Keeping them in
one implementation commit makes the behavior change bisect-safe and gives
reviewers one coherent before/after surface.

**Alternatives considered**:

- Separate resolver pre-slice. Rejected because the issue body explicitly
  ties the gap to the first real fixture, and a resolver-only commit would
  not yet prove the production-shaped failure mode.

## Decision: Treat missing contingency fixture as a Q-file blocker

**Rationale**: The issue asks for a contingency-disburse variant if a
representative transaction exists. Substituting another category would
stretch the PR beyond its scoped disburse corpus.

**Alternatives considered**:

- Use a second multisig disburse if no contingency exists. Rejected because
  it changes the acceptance target without parent arbitration.

## Decision: No vocabulary expansion in this PR

**Rationale**: The typed emitter already emits blueprint-derived predicates
in the fixture default namespace. New `cardano:*` terms are explicitly
reserved for a kmaps phase ticket and would violate the issue boundary.

**Alternatives considered**:

- Add missing `cardano:*` terms opportunistically. Rejected by the parent
  brief and the issue's out-of-scope section.

## Decision: Use the existing full gate from #50 as the PR gate

**Rationale**: The predecessor gate already covers build, unit tests,
formatting, lint, cabal check, and Haddock. This ticket extends the
fixture corpus and one blueprint resolver path; the existing gate is the
right project-level proof.

**Alternatives considered**:

- Add a separate smoke command. Rejected for planning until the worker
  discovers a concrete existing recipe; `./gate.sh` remains the acceptance
  command.

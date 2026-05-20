# Canonical vocab pin — provenance

Vendored snapshot of the canonical `cardano:` vocab from
[lambdasistemi/cardano-knowledge-maps](https://github.com/lambdasistemi/cardano-knowledge-maps),
the source of truth for predicate declarations consumed by the
body emitter.

## Current pin

- **File**: [`transactions.ttl`](./transactions.ttl) (382 lines)
- **Source**: `data/rdf/transactions.ttl`
- **Repo**: `lambdasistemi/cardano-knowledge-maps`
- **SHA**: `8ed218cf6dc905c7e3139b9f5a418d278b0acf9c` (branch
  `phase-a1-tx-semantic-predicates` HEAD on 2026-05-20)
- **Branch state**: draft PR
  [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55),
  not yet merged to `main`. Base
  `8597fbd571188b42999ee0b24a8247bda7e717b9`.
- **Version label** declared in the file: `0.1.0-phaseA` (with
  Phase A.1 additions appended at the tail: `fromTxOutRef`,
  `lovelace`, `quantity`, `mintsAsset`, `withdrawalAccount`,
  `networkId`, `scriptDataHash`, `auxiliaryDataHash`,
  `intervalStart`, `intervalEnd`).
- **History** (previous pins): kmaps@`8597fbd571188b42999ee0b24a8247bda7e717b9`
  (303 lines, vendored at T101 / S0).

## Why pin?

The `VocabTraceabilitySpec` invariant (per spec FR-013, the
strict vocab-traceability extension) asserts that every emitted
CURIE in the body emitter's output traces to a term declared in
the canonical vocab. To keep that check deterministic and
offline-buildable, this directory carries a verbatim copy of the
canonical file rather than reaching out to GitHub at test time.

The pin is refreshed in dedicated `chore(070): refresh
canonical-vocab pin to kmaps@<sha>` commits — never on the same
commit as a behavior-changing slice (per A-002's decoupling
rationale).

## Lifecycle (per A-002 / A-004)

1. **Now (this commit)** — pin at kmaps@8597fbd57, the Phase A
   HEAD that exists today. None of the proposed Phase A.1
   additions live here yet.
2. **Slice T110a (before T103 emits a Phase A.1 predicate)** —
   refresh to the `phase-a1-tx-semantic-predicates` branch tip of
   [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55)
   so the strict CI gate is satisfied as Phase A.1 predicates
   start emitting.
3. **Slice T110b (finalization, before T113 drops `gate.sh`)** —
   refresh to the merged kmaps `main` SHA once kmaps#55 lands.
   Blocks PR #77 finalization.

## Refresh recipe

```bash
# Fetch the latest version from a known SHA:
curl -sL "https://raw.githubusercontent.com/lambdasistemi/cardano-knowledge-maps/<sha>/data/rdf/transactions.ttl" \
  -o test/fixtures/canonical-vocab/transactions.ttl

# Update this file's "Current pin" section with the new SHA + date.
# Commit subject: `chore(070): refresh canonical-vocab pin to kmaps@<sha>`.
```

## Related

- Spec FR-013 — strict vocab-traceability CI check
- Plan D-001..D-006 — predicate-shape decisions consuming the pin
- Companion kmaps PR — [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55)
  (Phase A.1 additions, draft)
- Sub-orchestrator's draft of the additions —
  `/tmp/epic-046/tx-70/transactions-additions.ttl` (out-of-tree)

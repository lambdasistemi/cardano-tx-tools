# Feature Specification: Emitter MVP — deferred pending #48 rules loader

**Feature Branch**: `47-emitter-mvp`
**Created**: 2026-05-19
**Status**: Deferred (scope-down merge)
**Issue**: lambdasistemi/cardano-tx-tools#47
**Epic**: lambdasistemi/cardano-tx-tools#46 (Wave 1 chokepoint, re-sequenced)

## Summary

Issue #47 originally scoped a body-only Conway transaction → Turtle emitter
(`Cardano.Tx.Graph.Emit` + `tx-graph` executable) walking
`conwayDiffProjection` from `Cardano.Tx.Diff`, with `EmitGoldenSpec`
acceptance against the 11 `test/fixtures/rewrite-redesign/*/expected.ttl`
fixtures merged in #45 (PR #55, on `main`).

Planning-phase discovery exposed an epic-level layering ambiguity that
makes the originally-scoped MVP incoherent. The decision is to **merge
this PR as a scope-down** that documents the discovery and the
re-sequencing, then land **#48 (rules loader) first** as a
self-contained PR, and only then file and execute the body-emitter
work as a new ticket where the rules-entity overlay is already on
disk.

## Discovery

The brief and the issue both demand byte-equivalent reproduction of
the existing `expected.ttl` fixtures from a Tx + UTxO input alone.
Inspecting the simplest fixture
(`test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.ttl`,
93 lines) and confirming the same pattern across the other 10 fixtures
shows the goldens are not Tx+UTxO-derivable:

1. **Operator-declared entities** (lines 5–33 of `02-alice-bob-ada`)
   come from `rules.yaml`'s `entities:` list. Triples like

   ```turtle
   :alice a cardano:Entity ;
     rdfs:label "alice" ;
     cardano:hasIdentifier _:aliceIdPayment .
   _:aliceIdPayment a cardano:Identifier ;
     cardano:leafType "PaymentKey" ;
     cardano:bytesHex "601f58e4…" .
   ```

   The entity name `"alice"` is not anywhere in the Tx or UTxO — it
   only exists in `rules.yaml`.

2. **The transaction body** (lines 35–93) references the
   rules-derived blank nodes from section 1:

   ```turtle
   _:aliceCredPayment a cardano:PaymentCredential ;
     cardano:hasIdentifier _:aliceIdPayment .   # ← rules-derived blank node
   ```

   So even an "emit only the body" interpretation cannot reproduce
   the body section as-merged — blank-node names depend on the
   rules-derived overlay.

The same shape holds in the more complex fixtures
(`01-amaru-treasury-swap` is 294 lines with operator entities for
`amaru-treasury.network_compliance`, `amaru.swap.v2`,
`amaru.network-wallet`, `usdm`).

## Why body-only doesn't compose cleanly

A pure-body MVP would have to either:

- **Carve new `expected.body.ttl` fixtures** with raw-bytes-derived
  credential blank nodes (e.g. `_:cred_paymentkey_601f58e4…`) and
  byte-diff against those. This requires authoring 11 new
  per-fixture assets up front *and* leaves the existing
  `expected.ttl` as a future contract #48 has to retrofit into
  jointly producing.

- **Slice the existing `expected.ttl`** in `EmitGoldenSpec` after
  a sentinel and rewrite blank-node names on the fly. This adds
  brittle test-side substitution logic and still effectively
  measures against a different golden than the merged one.

- **Skip the byte-equivalence acceptance entirely** and ship the
  MVP against synthetic mini-fixtures. This delivers the floor
  ticket of the epic without the goldens evidence the epic
  acceptance (SC-005, byte-identical reproducibility) is supposed
  to anchor on.

None of these gives the epic a clean Wave 1 chokepoint:

- The first option locks #48 into a retrofit shape rather than
  letting it compose naturally on top of an existing body emitter.
- The second buries the layering question in test code instead of
  resolving it in the artifact set.
- The third defers the very evidence that justifies the chokepoint.

## Decision — re-sequence the epic

Land #48 (rules loader: `rules.yaml` → operator-entity Turtle) **first**
as a self-contained PR — it depends only on the kmaps#53 vocab (already
merged) and the on-disk `rules.yaml` fixtures, not on the emitter.
Once #48 ships, the operator-entity overlay exists on disk for every
fixture.

Then file a new ticket for the body emitter (originally scoped as
#47). With #48 already merged, the body emitter:

- has the entity overlay available as a peer input;
- can reference rules-derived blank-node names directly, in one pass;
- needs no `expected.body.ttl` carve-outs;
- has a clean per-PR contract (`emitter(Tx, UTxO, EntityOverlay) →
  ConcatTurtle === expected.ttl`).

The originally-planned `Cardano.Tx.Graph.Emit` module + `tx-graph`
executable + `EmitGoldenSpec` move to that new ticket unchanged in
intent, simpler in execution.

This PR merges as a scope-down: the discovery + the deferral decision
itself. No emitter code, no executable, no test wiring lands here.

## Out of scope (for this PR)

- The `Cardano.Tx.Graph.Emit` module.
- The `tx-graph` executable and `--utxo/--out/--format` flags.
- Walking `conwayDiffProjection` to produce triples.
- Deterministic blank-node identifier scheme.
- `EmitGoldenSpec` test wiring.
- Any change to `cardano-tx-tools.cabal` (no new module exposure, no
  new exe stanza, no new dep).
- Any change to `test/fixtures/rewrite-redesign/*` (the existing
  `expected.ttl` set remains the joint-graph contract a future PR
  will satisfy).

## Acceptance

- [x] This `spec.md` documents the discovery, the layering reason a
      body-only MVP does not compose, and the re-sequencing decision.
- [ ] PR #56 transitions from draft to ready with `gate.sh` removed
      in the dedicated `chore` commit.
- [ ] PR #56 description and the closing comment make the deferral
      explicit so reviewers do not expect emitter code.

## Followup (orchestrator-owned, not this PR)

- **#48** (rules loader) — bootstrap and land next; self-contained on
  kmaps#53.
- **New ticket** (post-#48) — body emitter work originally scoped as
  #47. Inherits the discovery from this spec; references this PR.
- **Epic #46** — update the Wave 1 sequencing in the parent epic so
  downstream waves (#49 reasoner, #50 blueprint, #51 views) consume
  the new sequencing.

## References

- Issue: lambdasistemi/cardano-tx-tools#47
- Epic: lambdasistemi/cardano-tx-tools#46
- Vocab: lambdasistemi/cardano-knowledge-maps#53 (merged 2026-05-19)
- Harness: lambdasistemi/cardano-tx-tools#45 / PR #55 (merged 2026-05-19) —
  the 11 `expected.ttl` fixtures whose layering surfaced this
  decision.
- Discovery record: `/tmp/epic-046/tx-47/questions/Q-001-byte-equivalence-vs-no-rules-loader.md`
  and answer `/tmp/epic-046/tx-47/answers/A-001-byte-equivalence-vs-no-rules-loader.md`
  (ephemeral; rationale captured in this spec).

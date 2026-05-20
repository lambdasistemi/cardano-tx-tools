# Implementation Plan: Body emitter — Conway semantic completeness (WriterT/State seam)

**Feature**: `Cardano.Tx.Graph.Emit` (semantic completeness)
**Branch**: `070-body-emit-conway-semantic`
**Spec**: [spec.md](./spec.md)
**Tasks**: [tasks.md](./tasks.md)
**Analyzer report** (after dispatch): [analysis.md](./analysis.md)
**Predecessor plan**: [`specs/058-body-emitter/plan.md`](../058-body-emitter/plan.md)

## Constitution gate

- **One-Way Dependency** (Principle I): the refactor stays inside the
  `Cardano.Tx.Graph.Emit.*` subtree. Per A-001, `Cardano.Tx.Diff` is
  read-only — no new edge from `Emit` to `Diff` beyond what #58 already
  imports. The optional new `Cardano.Tx.Graph.Emit.Monad` module sits
  under the same subtree.
- **Module Namespace** (Principle II): the new `Emit.Monad` module (if
  factored) is a sibling of `Emit.Project`, `Emit.Triple`, `Emit.Vocab`,
  `Emit.Lookup`, `Emit.Serialize.*`. No fresh namespace.
- **Conway-Only** (Principle III): the walker consumes `ConwayTx` /
  Conway-era projections; no era generalization.
- **Hackage-Ready** (Principle IV): Haddock on every exported function;
  module headers in `{- | … -}` form; `cabal check` + `cabal haddock
  lib:cardano-tx-tools` clean. Inherits #58's PvP-upper-bounds +
  `werror` cabal flag baseline.
- **Strict Warnings** (Principle V): inherits the `warnings` common
  stanza; incomplete-pattern warnings still surface unhandled
  `ConwayDiffValue` constructors. The new `Object` constructors
  (`OHexLit`, etc.) propagate via `-Wincomplete-patterns` into both
  serializers.
- **Default-Offline** (Principle VI): the vendored vocab pin removes
  the only network temptation in the test path (`transactions.ttl`
  parsed from disk).
- **TDD With Vertical Bisect-Safe Commits** (Principle VII): every
  implementation slice S0..S_n+1 is one bisect-safe commit with
  RED+GREEN folded; the per-slice TDD shape is captured in tasks.md.

## Pin from A-001 — monadic seam location

The `Emit = WriterT [Triple] (State (Set Subject))` monad lives **inside
`Cardano.Tx.Graph.Emit.*`**, factored as a new private submodule
`Cardano.Tx.Graph.Emit.Monad` exposing:

```haskell
-- | The body-emitter monad: a writer over triples plus a seen-set on
--   subjects (for the deduplicating `introduce` helper).
newtype Emit a = Emit (WriterT [Triple] (State (Set Subject)) a)
  deriving newtype (Functor, Applicative, Monad)

tellTriple :: Triple -> Emit ()

-- | Run `body` only the first time `subject` is introduced; on later
--   visits, return `()` without re-emitting the predicate block.
introduce :: Subject -> Emit () -> Emit ()

-- | Project the accumulated triples + the final seen-set out of an
--   `Emit` computation.
runEmit :: Emit a -> ([Triple], Set Subject)
```

The seen-set is keyed on `Subject` (a stable IR type from
`Cardano.Tx.Graph.Emit.Triple`) rather than the unwrapped `BnodeName`,
so `introduce` works for both bnode and IRI subjects. `Cardano.Tx.Diff`
is **read-only** — no edits.

The Turtle serializer is unchanged in shape; the new pipeline is:

```text
projectBody → (runEmit) → [Triple] → groupBySubject → [SubjectBlock]
                                                   → assemble [BodySection]
                                                   → renderTurtle
```

`groupBySubject` is a new internal helper in `Emit.Project` (or
`Emit.Monad`). It preserves first-occurrence order so reproducibility
stays GREEN against the regenerated `expected.ttl`.

## Pin from A-002 — vocab decisions

### D-001 (validity interval shape) — object form

```turtle
_:tx cardano:hasValidityInterval _:interval1 .
_:interval1 cardano:intervalStart 1000000 ;
            cardano:intervalEnd   1500000 .
```

Canonical `hasValidityInterval` is already declared (the singular
interval-object predicate); `intervalStart` / `intervalEnd` are
proposed kmaps additions (see
`/tmp/epic-046/tx-70/transactions-additions.ttl`).

### D-002 (datum subject shape) — unified Datum subject

```turtle
# inline datum (output carries cbor bytes)
_:output1 cardano:hasDatum _:datum1 .
_:datum1 cardano:hasHash      "<32-byte hex>" ;
         cardano:hasRawBytes  "<cbor hex>" .

# datum-hash-only (output carries hash, body bytes off-chain)
_:output1 cardano:hasDatum _:datum1 .
_:datum1 cardano:hasHash "<32-byte hex>" .
```

Presence of `hasRawBytes` distinguishes inline from hash-only.

### D-003 (input subject shape)

```turtle
# spending input — has resolvedTo when UTxO map supplies it
_:input1 a cardano:Input ;
  cardano:fromTxOutRef "<txid>#<ix>" ;
  cardano:resolvedTo _:resolved1 .

# reference input (bound under hasReferenceInput on _:tx)
_:input2 a cardano:Input ;
  cardano:fromTxOutRef "<txid>#<ix>" .

# collateral input (bound under hasCollateralInput on _:tx)
_:input3 a cardano:Input ;
  cardano:fromTxOutRef "<txid>#<ix>" .
```

The class is `cardano:Input` for all three; the binding predicate on
`_:tx` distinguishes them.

### D-004 (mint subject shape)

```turtle
_:mint1 a cardano:Mint ;
  cardano:mintsAsset _:asset1 ;
  cardano:quantity -5 .

# asset1 keeps its existing shape (#58)
_:asset1 a cardano:Asset ;
  cardano:hasIdentifier _:usdm_assetClass .
```

Negative quantity for burns is rendered as a plain integer literal —
Turtle's `xsd:integer` lexical space permits the minus sign.

### D-005 (withdrawal subject shape)

```turtle
_:withdrawal1 a cardano:Withdrawal ;
  cardano:withdrawalAccount _:rewardAcct1 ;
  cardano:lovelace 1000000 .
```

The `#58`-inherited `cardano:onCredential` + `cardano:withAmount` are
**replaced** by canonical-aligned `withdrawalAccount` + `lovelace`. This
is the one inherited-drift cleanup that lands inline rather than in the
deferred follow-up (justified per A-002 — touching the withdrawal
emitter anyway).

### D-006 (TreasuryWithdrawals proposal subject shape)

The current `_:proposal1 a cardano:Datum ; cardano:decodedAs
"TreasuryWithdrawals" ; cardano:hasIdentifier _:r ; cardano:hasIdentifier
_:t1 ; …` stub-shape is **replaced** by:

```turtle
_:proposal1 a cardano:Proposal ;
  cardano:decodedAs "TreasuryWithdrawals" ;
  cardano:proposerReturnAddr _:rewardAcct_return ;
  cardano:withdrawalTarget _:rewardAcct_t1 ;
  cardano:withdrawalTarget _:rewardAcct_t2 .
```

`cardano:Proposal`, `cardano:proposerReturnAddr`, and
`cardano:withdrawalTarget` are NOT in canonical vocab today. Per
A-002 these are out of the load-bearing kmaps PR scope — D-006
pins the proposal as a **P2 deferral**: ship the inline-datum shape
with `cardano:hasDatum` + `cardano:hasRawBytes` for now (matching
D-002) and keep the existing `cardano:decodedAs "TreasuryWithdrawals"`
literal as a hint for #50's typed decoding. The
proposer-returnAddr + withdrawalTarget triples land in a follow-on
ticket once the canonical proposal-class hierarchy lands.

This is a divergence from the original #70 *Scope* "governance:
proposals … emitted as typed triples with full attributes" promise —
**flagged inline in this plan as a scope clarification** rather than a
late surprise. Vertical-deliverables rule satisfied: the fail-loudly
behavior for non-`TreasuryWithdrawals` proposal variants is preserved.

### Predicate registry sync

`Cardano.Tx.Graph.Emit.Vocab.VocabTerm` extends with one constructor per
new term. The full delta:

| New constructor | CURIE | Source |
|---|---|---|
| `TermFromTxOutRef` | `cardano:fromTxOutRef` | kmaps PR |
| `TermLovelace` | `cardano:lovelace` | kmaps PR |
| `TermQuantity` | `cardano:quantity` | kmaps PR |
| `TermMintsAsset` | `cardano:mintsAsset` | kmaps PR |
| `TermWithdrawalAccount` | `cardano:withdrawalAccount` | kmaps PR |
| `TermNetworkId` | `cardano:networkId` | kmaps PR |
| `TermScriptDataHash` | `cardano:scriptDataHash` | kmaps PR |
| `TermAuxiliaryDataHash` | `cardano:auxiliaryDataHash` | kmaps PR |
| `TermIntervalStart` | `cardano:intervalStart` | kmaps PR (D-001) |
| `TermIntervalEnd` | `cardano:intervalEnd` | kmaps PR (D-001) |
| `TermHasValidityInterval` | `cardano:hasValidityInterval` | canonical (already declared) |
| `TermHasDatum` | `cardano:hasDatum` | canonical (already declared) |
| `TermHasReferenceScript` | `cardano:hasReferenceScript` | canonical (already declared) |
| `TermHasReferenceInput` | `cardano:hasReferenceInput` | canonical (already declared) |
| `TermHasHash` | `cardano:hasHash` | canonical (already declared) |
| `TermHasRawBytes` | `cardano:hasRawBytes` | canonical (already declared) |

`TermOnCredential` + `TermWithAmount` are removed in S5 (the
withdrawal slice); `TermDatum` is removed in S4 (the datum slice — the
`cardano:Datum` *class* stays; the predicate-shaped reuse goes away
when proposals no longer mock it).

## Owned-file set (final, per A-001 / A-002)

- `src/Cardano/Tx/Graph/Emit/Monad.hs` — NEW (S1)
- `src/Cardano/Tx/Graph/Emit/Project.hs` — heavy refactor (S1+) + per-leaf slices (S2..S9)
- `src/Cardano/Tx/Graph/Emit/Triple.hs` — new `Object` constructors as needed (e.g. `OHexLit`)
- `src/Cardano/Tx/Graph/Emit/Vocab.hs` — registry extension per the table above (S1)
- `src/Cardano/Tx/Graph/Emit/Lookup.hs` — bnode-naming additions for resolved-input bnodes, asset-class bnodes (S3, S4)
- `src/Cardano/Tx/Graph/Emit/Serialize/Turtle.hs` — render new `Object` constructors only (S2+); structure stays as-is
- `src/Cardano/Tx/Graph/Emit/Serialize/JsonLd.hs` — symmetrize with Turtle (JSON-LD ≡ Turtle SC-008)
- `cardano-tx-tools.cabal` — add `mtl` direct dep if not already transitive (verify in S1 RED)
- `test/fixtures/rewrite-redesign/*/expected.ttl` — regenerated per slice
- `test/fixtures/rewrite-redesign/*/NOTES.md` — touch only where behavior narrative shifts
- `test/Cardano/Tx/Graph/Emit*Spec.hs` — per-slice invariants + extended
  vocab-traceability spec
- `test/fixtures/canonical-vocab/transactions.ttl` — NEW vendored pin (S0)
- `test/fixtures/canonical-vocab/PINNED.md` — NEW pin header (S0)
- `views/no-stub-triples.rq` — NEW (S_n-2)
- `gate.sh` — extend at S_n-2 to invoke the no-stub view; dropped at S_n+1
- `docs/assets/asciinema/tx-graph.cast` — re-recorded at S_n
- `docs/assets/asciinema/scripts/tx-graph.sh` — script may need fixture switch at S_n
- `docs/tx-graph.md` — `--help` excerpt refresh at S_n if surface changes
- `README.md` — example refresh at S_n if surface changes
- `CHANGELOG.md` — entry at S_n+1

**Read-only** (per A-001 / brief): `src/Cardano/Tx/Diff.hs`, the
operator-entity overlay shape from #48, all builders under
`test/fixtures/rewrite-redesign/*/build-fixture.hs`, all release / CI /
Nix wiring (`.github/workflows/*.yml`, `nix/*.nix`, `flake.nix`).

## Vertical slices

Slice order is bisect-safe: every slice ends with `./gate.sh`
GREEN and a regenerated `expected.ttl` byte-diff GREEN against
the predecessor's expectation (which is rolled forward in the same
commit).

| Slice | Subject | Conventional Commit prefix | Tasks |
|---|---|---|---|
| S0 | Vendor canonical-vocab pin (verbatim kmaps@8597fbd57 — kmaps PR base) + PINNED.md citing [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55) | `chore(070):` | T101 |
| S1 | Introduce `Emit` monad + `tellTriple` + `introduce` + `runEmit`; rewire `projectBody`; **no behavior change** (all fixtures byte-equal to S0) | `refactor(070):` | T102 |
| S2 | Input: `cardano:fromTxOutRef "<txid>#<ix>"` on every input (spending + collateral); reference-input support (FR-011) | `feat(070):` | T103 |
| S3 | Output: `cardano:lovelace` + multi-asset RDF list | `feat(070):` | T104 |
| S4 | Output: `cardano:hasDatum` (inline vs hash) + `cardano:hasReferenceScript`; remove proposal stub overload of `cardano:Datum` | `feat(070):` | T105 |
| S5 | Withdrawal: rename to `withdrawalAccount` + `lovelace` (D-005 cleanup-in-passing); mint: add `mintsAsset` + signed `quantity` | `feat(070):` | T106 |
| S6 | Body-root: `hasValidityInterval` (object-shape per D-001) + `networkId` + `scriptDataHash` + `auxiliaryDataHash` | `feat(070):` | T107 |
| S7 | Proposal: D-006 fallback shape — inline-datum sub-block under `hasDatum` + preserve `decodedAs "TreasuryWithdrawals"` | `feat(070):` | T108 |
| S8 | `views/no-stub-triples.rq` + extend `gate.sh` to invoke it; tighten harness `NoStubViewSpec` | `feat(070):` | T109 |
| S9a | Refresh canonical-vocab pin to [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55) branch tip (`phase-a1-tx-semantic-predicates` HEAD) so FR-013 strict CI passes against the proposed additions while the kmaps PR is still in draft | `chore(070):` | T110a |
| S9b | Refresh canonical-vocab pin to merged kmaps `main` SHA once kmaps#55 lands — finalization-blocking; pin must match a merged SHA before PR #77 flips to ready | `chore(070):` | T110b |
| S10 | Re-record asciinema cast against fixture 11; refresh `docs/tx-graph.md` / `README.md` examples if `--help` surface changed | `docs(070):` | T111 |
| S11 | `CHANGELOG.md` entry | `docs(070):` | T112 |
| S12 | Drop `gate.sh` (ready for review) | `chore(070):` | T113 |

The slice count is 13 (S0..S12). Slices S0/S1 are no-behavior-change
"plumbing" slices; S2..S7 are the per-Conway-field coverage slices;
S8..S12 are deliverables wire-up.

## Test strategy

### RED/GREEN per slice (TDD with vertical bisect-safe commits)

Each behavior-changing slice (S1..S8) ships its own RED first:

| Slice | RED proof (failing test added in the SAME commit, with the GREEN fix) |
|---|---|
| S1 | New `Cardano.Tx.Graph.EmitMonadSpec` asserts `runEmit (emitTx fixture02)` produces the SAME `[Triple]` set the pre-refactor walker would, AND that `tellTriple` is callable. Initially red because `Emit.Monad` doesn't exist; green when the module lands. Fixture 02's `expected.ttl` is unchanged — proving no behavior drift. |
| S2 | New invariant in `EmitGoldenSpec` asserts `cardano:fromTxOutRef` appears on every `_:inputK` block in the regenerated `expected.ttl`; AND fixture 11's emitter run returns `Right _` without `PUnsupportedLeafType "ConwayReferenceInputValue"`. Regen of all 11 `expected.ttl` files goes in the same commit. |
| S3 | New `OutputLovelaceSpec` asserts every `_:outputK` carries `cardano:lovelace <integer>`; new `MultiAssetListSpec` asserts the RDF list shape when a multi-asset value is present (fixture 03 or 04). |
| S4 | New `OutputDatumSpec` asserts the unified Datum sub-block shape on outputs carrying inline-vs-hash datums; new `OutputScriptRefSpec` for outputs carrying ref-scripts. The proposal cluster's class-reuse of `cardano:Datum` gets removed in this slice. |
| S5 | New `WithdrawalCanonicalSpec` asserts `withdrawalAccount` + `lovelace` predicate names (the cleanup-in-passing); `MintQuantitySpec` asserts the signed-integer literal for burns. |
| S6 | New `BodyRootSpec` asserts `hasValidityInterval` sub-block + `networkId` / `scriptDataHash` / `auxiliaryDataHash` when present (synthetic fixture path — extend builders if no current fixture exercises them). |
| S7 | `ProposalSpec` updated for the D-006 fallback shape (inline-datum sub-block); existing `decodedAs "TreasuryWithdrawals"` assertion preserved. |
| S8 | `NoStubViewSpec` runs `views/no-stub-triples.rq` against every fixture and asserts zero rows. RED on the first introduction because the view doesn't exist yet; GREEN after the view + gate wiring land. |

For each slice the RED runs FIRST locally (developer observes the
failure), then the GREEN fix is added, then `./gate.sh` is invoked,
then the commit is created. Tasks.md captures this rhythm.

### Live-boundary diagnostic per slice

Per resolve-ticket's "live-boundary smoke" addition, every slice that
touches operator-observable behavior gets a diagnostic question at
review-time: "what is the boundary this slice would fail at, and how
do we know the test exercises it?"

For #70:

| Slice | Boundary | How exercised |
|---|---|---|
| S0 | none (data load only) | n/a — pure file vendoring |
| S1 | Haskell module boundary (Emit monad vs walker) | `EmitMonadSpec` invariant: triples set equal pre- and post-refactor on fixture 02 |
| S2..S7 | emitter ↔ ledger types (`Cardano.Ledger.*` accessors) | Per-leaf SPARQL-shaped invariant on the regenerated `expected.ttl` byte-diff; fixture 11 reference-input gate is the live-CBOR boundary smoke (it loads on-chain bytes) |
| S8 | emitter ↔ SPARQL gate | `NoStubViewSpec` parses the emitter's Turtle output AND runs the SPARQL view |
| S9 | none (data refresh only) | n/a |
| S10 | emitter ↔ asciinema viewer | manual reviewer check at the preview URL — the boundary is the docs deploy + the player JS |
| S11 / S12 | none (docs / cleanup) | n/a |

The fixture-11 reference-input gate (S2) is the strongest
live-boundary signal in the slice plan — it loads real on-chain CBOR
bytes and exercises the new walker path end-to-end without mocking
any ledger type.

### Existing invariant carry-over (#58 SC-001..SC-008)

All eight #58 success criteria are explicitly carried forward by
re-running the existing `EmitGoldenSpec`, `JsonLdEquivalenceSpec`,
`ReproducibilitySpec`, `VocabTraceabilitySpec`, etc. against the
regenerated `expected.ttl` files. A regression on any of these is a
GATE-FAIL on the slice that introduced it; the offending slice
is reworked, not bypassed.

## Risks

| Risk | Mitigation |
|---|---|
| Kmaps PR opens late, blocks #70 final ready-for-review | A-002's decoupling: the vendored pin lets implementation slices land ahead; only the S9 pin-refresh slice depends on the kmaps merge. Worst case the S9 slice is a single-line SHA bump committed when the kmaps PR lands. |
| Canonical maintainer pushes back on a proposed predicate name | Parent surfaces via Q-file to this worker; the affected predicate's slice gets a `chore(070): rename <old> → <new>` follow-up commit. |
| A new fixture or builder change is needed to exercise a body-root predicate (S6 risk) | Extend an existing builder (e.g. add a TTL to fixture 02's stub builder) rather than ship a new fixture. Scoped narrowly to the slice. |
| Output multi-asset value RDF-list shape is too verbose on `amaru-treasury-swap-real` (33 inputs × multi-asset values) | The list shape iterates `Map.toAscList`; verbose Turtle is acceptable so long as byte-diff GREEN reproduces. JSON-LD equivalence (#58 SC-002) catches structural inconsistency. |
| `groupBySubject` ordering changes the byte-diff for fixtures that survive untouched | `groupBySubject` preserves first-occurrence order in the flat triple stream. S1's invariant pins this — fixture 02's byte-diff stays GREEN at the S1 commit. |
| Cast preview URL fails to render rich output (S10 risk) | The `MKDOCS_SITE_URL` env-override pattern is already wired; check the preview URL immediately after the S10 commit lands and CI deploys. If the player JS fails, the cast falls back to text — a stub-shape cast falls back to stub text, which the diagnostic catches. |

## Pre-implementation prereqs

- [x] spec.md committed (ac63380) + amended (8647a5e)
- [x] A-001 + A-002 + A-003 received and folded
- [x] kmaps additions Turtle patch drafted at `/tmp/epic-046/tx-70/transactions-additions.ttl`
- [ ] tasks.md generated (next: speckit-tasks)
- [ ] analysis.md generated (analyzer subagent dispatch after tasks.md lands)
- [ ] First implementation slice S0 lands (vendor canonical-vocab pin)

## Sequencing tie-in to epic #46

- This PR is child 5 (`#70`) of [epic #46](https://github.com/lambdasistemi/cardano-tx-tools/issues/46).
- Lands the per-field minimum coverage gap left by #58. The epic
  stays open until both #70 and #51 (SPARQL views) merge — the
  no-stub SPARQL gate + the now-rich graph make the views work
  unlock.
- Parallel parent action (DONE — kmaps#55 opened, draft):
  [lambdasistemi/cardano-knowledge-maps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55)
  on branch `phase-a1-tx-semantic-predicates`, base
  kmaps@8597fbd57, body matches
  `/tmp/epic-046/tx-70/transactions-additions.ttl` verbatim (+79
  lines, 10 properties). S9a refreshes the vendored pin to that PR's
  branch tip so FR-013 stays strict throughout implementation; S9b
  refreshes again to the merged main SHA at finalization (per
  A-004 Option A).
- Follow-on tickets to file at #70 finalization (per A-001 / A-002):
  - "Expose monadic `traverseConwayDiff` from `Cardano.Tx.Diff` if/when
    #51 / #52 want a shared walker" (A-001).
  - "Phase B vocab refresh: certificate class subtypes,
    governance-procedure classes, #58-inherited drift cleanup"
    against `lambdasistemi/cardano-knowledge-maps`.
  - "Proposal subject typing — `cardano:Proposal` class +
    `proposerReturnAddr` + `withdrawalTarget` predicates" against
    cardano-tx-tools and kmaps (D-006 deferral closure).

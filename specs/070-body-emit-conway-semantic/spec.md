# Feature Specification: Body emitter — Conway semantic completeness (WriterT/State seam)

**Feature Branch**: `070-body-emit-conway-semantic`
**Created**: 2026-05-20
**Status**: Draft (specs phase stop — awaiting parent review)
**Input**: `Cardano.Tx.Graph.Emit.Project` — extend the body-emitter walker
to surface the full Conway semantic content at every leaf
`Cardano.Tx.Diff.conwayDiffProjection` already visits. Pivot the walker
from pure `foldr` / `traverse` over `BodySection`-shaped returns to a
monadic traversal in `Emit = WriterT [Triple] (State (Set Node))`, with
`tellTriple` called at every leaf and `introduce` gating per-subject
blocks for de-duplication. Successor to #58, child of epic #46.

## Background — what shipped under #58 and what this PR closes

PR #60 / #58 (merged 2026-05-20, HEAD `46f963b`) shipped a body emitter
whose acceptance contract (SC-001..SC-008) gated byte-equivalence,
JSON-LD ≡ Turtle, and reproducibility. All eight criteria closed GREEN:
11/11 fixtures byte-diff against the regenerated `expected.ttl`, 33/33
vocab-traceability invariants, 298 unit examples.

That contract did **not** gate operator-visible semantic content. The
shipped emitter surfaces inputs as

```turtle
_:input1 a cardano:Input .
```

— no `cardano:fromTxOutRef`, no lovelace, no datum, no scriptRef — and
outputs as

```turtle
_:output1 a cardano:Output ;
  cardano:atAddress _:cred_paymentkey_0000000000000000Addr .
```

with no lovelace value, no multi-asset payload, no datum, no scriptRef.
The fixtures' `expected.ttl` matched byte-for-byte **because the
fixtures themselves are structurally stubbed by design** (see
`test/fixtures/rewrite-redesign/01-amaru-treasury-swap/NOTES.md` and
the merged epic-#46 "Completeness — non-negotiable" section).

This PR closes the per-Conway-field semantic gap. The epic stays open
until the no-stub SPARQL view returns zero rows on every fixture and
the published `tx-graph` asciinema cast demonstrates rich body output
(per the epic's "Cast gate — demonstrable rich output" section).

## Clarifications

### Session 2026-05-20

- Q: Where does the WriterT/State seam live — extend
  `Cardano.Tx.Diff.conwayDiffProjection` to expose a monadic walker, or
  keep the projection pure and lift the walker into `Emit` entirely
  inside `Cardano.Tx.Graph.Emit.Project`?
  → **A: [NEEDS CLARIFICATION — Q-001-monadic-walker-seam to parent]**
  Recommendation: keep the walker monadic inside `Project.hs`. Today's
  `projectBody` walks the ledger types directly (microlens accessors on
  `bodyTxL`, `inputsTxBodyL`, etc.) rather than calling
  `Cardano.Tx.Diff.conwayDiffProjection`. Lifting that direct walk into
  `Emit` requires no surface change to `Cardano.Tx.Diff`. Confirming
  with the parent before locking the owned-file set.
- Q: A material subset of the predicates the per-field minimum coverage
  list names are **not declared** in the canonical
  `cardano-knowledge-maps/data/rdf/transactions.ttl`. Discovered during
  the spec-phase vocab audit (fetched at HEAD on 2026-05-20):

  Missing classes / properties (selection, not exhaustive):
  - `cardano:fromTxOutRef` (input-position predicate);
  - `cardano:lovelace` (output / withdrawal ADA value);
  - `cardano:quantity` (mint signed quantity);
  - `cardano:mintsAsset` (mint → asset binding);
  - `cardano:withdrawalAccount` (withdrawal → reward-account binding);
  - `cardano:hasTtl`, `cardano:hasValidityRangeStart`, `cardano:networkId`,
    `cardano:scriptDataHash`, `cardano:auxiliaryDataHash` (body-root
    fields);
  - certificate subclasses beyond `Phase A` Phase-A header
    (`cardano:CertificateStakeRegistration`,
    `cardano:CertificatePoolRegistration`, etc.);
  - governance-procedure classes (`cardano:Proposal`, `cardano:Vote`,
    `cardano:DRepRegistration`, etc.) and per-variety subclasses.

  Naming-mismatch cases (vocab already declares an analogue under a
  different name):
  - issue body says `cardano:datum` / `cardano:datumHash`; vocab
    declares `cardano:hasDatum` (plus `cardano:hasHash` and
    `cardano:hasRawBytes` reusable for the inline-vs-hash split);
  - issue body says `cardano:scriptRef`; vocab declares
    `cardano:hasReferenceScript`.

  Pre-existing emitter terms not declared in
  `transactions.ttl` (drift inherited from #58, not new in this PR):
  `cardano:Mint`, `cardano:Policy`, `cardano:Withdrawal`,
  `cardano:StakeDelegation`, `cardano:VoteDelegation`, `cardano:Pool`,
  `cardano:DRep`, `cardano:onCredential`, `cardano:withAmount`,
  `cardano:toPool`, `cardano:toDRep`. (The local `vocabTraceability`
  invariant in #58 only cross-checks emitted IRIs against the internal
  `Cardano.Tx.Graph.Emit.Vocab.allVocabTerms` registry, **not** against
  the canonical file in `cardano-knowledge-maps`.)

  → **A: [NEEDS CLARIFICATION — Q-002-vocab-coordination to parent]**
  Three options under consideration:
  1. File a kmaps-side ticket (extends `transactions.ttl` Phase A with
     the missing terms) and block #70 implementation until that lands.
     Tightest semantics; longest sequencing.
  2. Implement #70 against the **expanded** internal `VocabTerm`
     registry plus a strict "every emitted predicate appears in
     `transactions.ttl`" CI check that **fails** until the kmaps ticket
     merges. Surfaces drift; blocks own merge.
  3. Implement #70 with the expanded internal registry and a **lint
     check** (warn-only) for `transactions.ttl` drift; reconcile in a
     follow-up. Fastest forward motion; risks shipping divergent vocab
     once again.

  Worker recommends option 1 — the epic's vocab-traceability gate is
  load-bearing and the drift list is already non-trivial, so a clean
  vocab refresh is the right unit of work. Awaiting parent decision.
- Q: What is the source of truth for the byte-diff anchor after this
  PR — the existing per-fixture `expected.ttl` (#58 stub-shape) or a
  **regenerated** file carrying the rich triples this PR emits?
  → **A: Regenerated.** Same pattern as #58 (Clarifications
  Session 2026-05-20 in `specs/058-body-emitter/spec.md`): #58's
  Q-001/A-001 established the joint-`expected.ttl` regen pattern; this
  PR re-emits the file with semantic content rather than the stub
  shape. The artisan/stubbed reference becomes a `git show HEAD~N:…`
  artifact. NOTES.md per-fixture stays as the operator-readable
  narrative.
- Q: Does this PR change the address-decomposition section format
  (`# Address decompositions — payment + stake credential per leaf.`)
  or the operator-entity overlay layout (#48's territory)?
  → **A: No.** Both layouts are stable. The change is restricted to
  the body sections (Transaction body / Input N / Output N / Mint N /
  Withdrawal N / Certificate N / Collateral N / Proposal N). The
  Address decomposition section retains its current shape; the overlay
  flows through `Cardano.Tx.Graph.Rules.Load` unchanged.
- Q: Conway transaction features the per-field minimum coverage list
  names but the post-#45 fixture set does **not** exercise — e.g.
  reference inputs (#70 acceptance row 3 names this gap explicitly),
  required signers, total-collateral, non-`TreasuryWithdrawals`
  proposal varieties, non-delegation cert varieties, native-script
  reference scripts, multi-asset values. Does this PR ship new
  fixtures to exercise them, or extend an existing fixture, or defer
  to a follow-on?
  → **A: Extend existing fixtures** rather than ship new ones; reuse
  the harness #45 ships. Concretely: fixture 11
  (`amaru-treasury-swap-real`) already carries reference inputs on the
  real on-chain bytes — currently failing with
  `UnsupportedLeafType: ConwayReferenceInputValue` per #70 acceptance
  row 3. Extending #70 to handle reference inputs flips that to
  green. Multi-asset values, datum/scriptRef, mint-with-quantity,
  withdrawal-with-amount are already present on existing fixtures
  (04, 05, 11, etc.) and just need the emitter to surface them rather
  than emit stub shapes. Cert/proposal variants beyond the
  `StakeDelegation` + `VoteDelegation` + `TreasuryWithdrawals` trio are
  **out of scope** for #70 (deferred to a future ticket — see Out of
  Scope below) unless the parent expands the scope.
- Q: Does this PR re-record the asciinema cast?
  → **A: Yes, in scope.** Per the epic's "Cast gate — demonstrable
  rich output" section the published cast must show real fee +
  lovelace + addresses + (where applicable) datum / scriptRef /
  certificate / mint / withdrawal triples. The cast is regenerated by
  `docs/assets/asciinema/scripts/tx-graph.sh` and verified via the
  preview URL the `MKDOCS_SITE_URL` env override pattern (already
  adopted by `.github/workflows/deploy-docs.yml`) wires up for PR
  previews. The cast is a first-class deliverable, not a follow-up.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator inspects a Conway tx and sees the full semantic graph (Priority: P1)

An operator running `tx-graph --tx <conway.cbor> --utxo <resolved.json>
--rules <rules.yaml>` on any real Conway transaction (e.g. fixture 11,
the on-chain `amaru-treasury-swap-real`) sees a Turtle output where
every input names its `<txid>#<ix>` reference, every output names its
lovelace value and (when present) datum / scriptRef / multi-asset
value, every certificate is typed under its specific subclass with all
its attributes, every withdrawal binds its reward-account + amount,
every mint binds its policy + asset + signed quantity, every
governance proposal / vote surfaces its full attributes, and the
transaction root carries fee + TTL + validity range + network id +
script-data hash + auxiliary data hash (when present).

The operator does not see anonymous `_:inputK a cardano:Input .` /
`_:outputK a cardano:Output ; cardano:atAddress ...` stub shapes
anywhere in the output. A SPARQL query

```sparql
SELECT ?subj WHERE {
  ?subj a ?type .
  FILTER (?type IN (cardano:Input, cardano:Output))
  FILTER NOT EXISTS {
    ?subj ?p ?o .
    FILTER (?p != rdf:type)
  }
}
```

run against the emitted graph returns **zero rows**.

**Why this priority**: This is the gap the epic's "Completeness —
non-negotiable" section names. Until the operator-observable semantic
content lands, every downstream consumer (#49 reasoner, #51 SPARQL
views, #52 diff-as-view) is projecting from stubs and surfaces
shape-without-content. P1 because closing this gap is what unblocks
the rest of the epic.

**Independent test**: regenerate every fixture's `expected.ttl` from
the new emitter; byte-diff GREEN on every fixture; run
`views/no-stub-triples.rq` against every emitted graph and confirm
zero rows on each.

**Acceptance scenarios**:

1. **Input with real `fromTxOutRef`**: Given a Conway tx with at least
   one input whose `TxIn` references `<txid>#<ix>`, When the emitter
   runs, Then the input's subject block carries
   `cardano:fromTxOutRef "<txid>#<ix>"^^xsd:string` (or an equivalent
   typed literal — final form pinned in plan.md D-001).
2. **Input distinguishability**: Given a Conway tx with reference
   inputs AND collateral inputs AND spending inputs, When the emitter
   runs, Then each input's subject block is distinguishable from the
   other two kinds by the binding predicate on `_:tx`
   (`cardano:hasInput` / `cardano:hasReferenceInput` /
   `cardano:hasCollateralInput`); reference inputs additionally do not
   appear under `cardano:hasInput`.
3. **Output with lovelace value**: Given a Conway tx output carrying
   N lovelace, When the emitter runs, Then the output's subject block
   carries `cardano:lovelace N` (or whatever the canonical predicate
   resolves to under Q-002).
4. **Output with multi-asset value**: Given a Conway tx output
   carrying a multi-asset value (one or more `(policy, asset, qty)`
   tuples beyond ADA), When the emitter runs, Then the output's
   subject block emits one RDF-list of asset-quantity nodes (one node
   per `(policy, asset, qty)` triple — see Q-002 for the exact term
   names).
5. **Output with inline datum**: Given a Conway tx output carrying an
   inline `Datum` payload, When the emitter runs, Then the output's
   subject block carries the datum predicate (per Q-002) and elides
   the datum-hash predicate.
6. **Output with datum hash**: Given a Conway tx output carrying a
   datum hash (not inline), When the emitter runs, Then the output's
   subject block carries the datum-hash predicate (per Q-002) and
   elides the inline-datum predicate.
7. **Output with scriptRef**: Given a Conway tx output carrying a
   reference script, When the emitter runs, Then the output's subject
   block carries the scriptRef predicate (per Q-002) pointing at a
   subject block for the reference script (hash + body bytes).
8. **Certificate full attributes**: Given a Conway tx with at least
   one `StakeDelegation` certificate, When the emitter runs, Then the
   certificate's subject block is typed `cardano:StakeDelegation` and
   carries the stake credential identifier + the target pool
   identifier (both pinned to the operator's entity overlay when
   covered, raw-bytes-named otherwise). Repeat for `VoteDelegation` →
   DRep target.
9. **Withdrawal full attributes**: Given a Conway tx with a
   withdrawal, When the emitter runs, Then the withdrawal's subject
   block carries the reward-account identifier predicate **and** the
   amount predicate.
10. **Mint full attributes**: Given a Conway tx with a mint entry
    `(policy, asset, qty)` where `qty < 0` (a burn), When the emitter
    runs, Then the mint's subject block carries the policy + asset +
    **signed** quantity (negative integer literal).
11. **Governance proposal**: Given a Conway tx with a
    `TreasuryWithdrawals` proposal, When the emitter runs, Then the
    proposal's subject block is typed under the variety-specific class
    (per Q-002) and carries the proposer's returnAddr + each withdrawal
    target as distinct typed predicates rather than a list of
    same-named `hasIdentifier` pointers.
12. **Body root fields**: Given a Conway tx whose body carries any of
    `fee` / `ttl` / `validityIntervalStart` / `networkId` /
    `scriptDataHash` / `auxiliaryDataHash`, When the emitter runs,
    Then the `_:tx` subject block carries each as a distinct predicate
    (elided when the field is `SNothing`).
13. **Reference input decoding** (#70 acceptance row 3): Given fixture
    11 (`amaru-treasury-swap-real`) re-loaded with its real on-chain
    `referenceInputs` set, When the emitter runs, Then the emit
    completes without raising
    `PUnsupportedLeafType "ConwayReferenceInputValue"`.

### User Story 2 — Subject-block de-duplication via `introduce` (Priority: P1)

Given a Conway tx whose body refers to the same `Address` /
`PaymentCredential` / `StakeCredential` / `PolicyID` / `AssetClass` /
`PoolId` / `DRepKey` from multiple positions (e.g. five outputs at
the same address, three inputs at the same script payment
credential), When the emitter runs, Then the emitted graph carries
**exactly one** subject block per shared subject identity; each
referring position references the shared subject by name. The
`State (Set Node)` layer of `Emit` enforces this; `introduce`
short-circuits on the seen-set.

**Independent test**: an additional unit-level invariant
(`SubjectDeDupSpec`) parses the emitted Turtle, groups triples by
subject, and asserts no two distinct subject blocks share the same
subject node.

**Acceptance**: fixture 01 emits one address-decomposition block per
unique address (count drops from 36 input-named placeholders to the
unique-address count plus the one shared payment-credential bnode);
fixture 03 emits one asset-class block per unique `(policy, asset)`
even when the same asset appears on multiple outputs.

### User Story 3 — Asciinema cast demonstrates rich emission (Priority: P1)

Given the docs preview at
`${MKDOCS_SITE_URL}/tx-graph/` (where `MKDOCS_SITE_URL` is the
PR-preview URL injected by `.github/workflows/deploy-docs.yml`), When
a reviewer opens the page and scrolls the embedded `tx-graph.cast`
player, Then the viewer sees real fee + lovelace + addresses + (where
applicable) datum / scriptRef / certificate / mint / withdrawal
triples — never the `_:inputK a cardano:Input .` stub shape. The cast
is re-recorded by `docs/assets/asciinema/scripts/tx-graph.sh` against
a fixture that exercises ≥4 of the per-field minimum coverage rows
(candidate: fixture 11 `amaru-treasury-swap-real` — already script-
locked, multi-asset, datum-carrying, reference-input-carrying).

**Why this priority**: per the epic's "Cast gate — demonstrable rich
output" rule the cast is a deliverables gate, not a documentation
nice-to-have. A stub-shape cast that ships alongside the
semantically-complete emitter is a deliverables failure.

**Independent test**: the cast file's size changes from the current
4.5 K baseline; manual reviewer verifies the preview URL renders the
rich output (no automated SPARQL check on the cast itself is
feasible — the cast is opaque to RDF tooling).

### User Story 4 — Existing #58 invariants stay GREEN (Priority: P1)

Given the merged #58 invariant suite (SC-001..SC-008 — byte-
equivalence, JSON-LD ≡ Turtle, reproducibility, vocab-traceability,
no-Byron-fail, address-decomp byte-diff, JSON-LD frame check,
HSpec-suite scaffold), When this PR's regenerated emitter ships,
Then every #58 invariant stays GREEN against the regenerated
`expected.ttl` (which now carries the rich triples).

**Why this priority**: regressions on #58's contract during a #70
refactor are unacceptable — #58 already validated reproducibility
and JSON-LD equivalence. P1 because losing those invariants would
constitute scope drift.

### Edge Cases

- **Empty multi-asset value**: a Conway output carrying only ADA
  (no native asset) emits the lovelace predicate and **no**
  multi-asset RDF list (not an empty list — elide entirely).
- **Datum vs datum-hash mutual exclusion**: the ledger guarantees an
  output carries inline datum XOR datum hash XOR neither. Plan-time
  decision (D-002 in plan.md): both predicates elided when neither
  present; assertion at emit time when both present (invariant
  violation → `PUnsupportedLeafType` or similar fail-loudly).
- **Negative `quantity` on mint = burn**: the mint subject block emits
  the negative literal verbatim (per #70 *Scope*: "signed because
  burns are negative"). Turtle int literal allows negative values via
  the standard `xsd:integer` lexical space; the serializer renders
  `-5` literally.
- **Multiple `hasIdentifier` pointers from a single proposal**: today's
  fixture 10 emits the proposer's returnAddr stake credential + one
  pointer per `TreasuryWithdrawals` target reward-account, all under
  `cardano:hasIdentifier`. Per Q-002 the variety-specific class on the
  proposal should carry distinct predicates (e.g.
  `cardano:proposerReturnAddr`, `cardano:withdrawalTarget`) rather
  than reusing `hasIdentifier`. Final shape pinned in plan.md.
- **Network ID on Conway**: the body field is optional (`SMaybe`); when
  `SNothing`, elide the predicate (do not emit `cardano:networkId
  null` or similar).
- **TTL absent / validity-start absent**: Conway permits txs with no
  validity bounds; elide both predicates when both absent.
- **Reference input ↔ spending input collision**: the ledger forbids a
  `TxIn` from appearing in both the spending-inputs set and the
  reference-inputs set; but the emitter MUST handle the case where a
  reference input's resolved output is in the UTxO map AND that same
  output is a spending input. (Fixture 11 exercises this — see #70
  Acceptance row 3 + Q-005 in plan.md.)
- **Multi-asset RDF-list ordering**: an output's multi-asset value
  iterates the ledger's `Map PolicyID (Map AssetName Quantity)`; the
  RDF list emits in `Map.toAscList` order (lexicographic by raw
  bytes) — the same order #58 already pins for the mint cluster
  (`Cardano.Tx.Graph.Emit.Project` line ≈ 220).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001 (monadic seam)**: `Cardano.Tx.Graph.Emit.Project` exposes an
  internal type `Emit = WriterT [Triple] (State (Set Node))` (or a
  newtype wrapper around it) and a `tellTriple :: Triple -> Emit ()` +
  `introduce :: Node -> Emit a -> Emit a` API. The public surface
  (`projectBody`) preserves its current signature `[EntityDecl] ->
  LookupTable -> ConwayTx -> Map TxIn (TxOut ConwayEra) -> Either
  ProjectError [BodySection]`; the new monadic plumbing is internal.
- **FR-002 (per-leaf tellTriple)**: every Conway-field leaf the walker
  visits emits its triple(s) via `tellTriple` rather than building a
  partial structure to be assembled later. Subject blocks are grouped
  from the flat `[Triple]` stream via a `groupBySubject`-style helper
  the serializer (or the emitter's tail end) applies before handing
  off to the Turtle writer.
- **FR-003 (subject de-dup)**: every subject block (Address /
  PaymentCredential / StakeCredential / PolicyID / AssetClass / PoolId
  / DRepKey / per-tx input/output bnode) emits **exactly once** for
  the lifetime of a single emit pass. `introduce` enforces this; a
  `Set Node` lives in `State`.
- **FR-004 (input semantic content)**: each input's subject block
  carries (a) the binding `cardano:fromTxOutRef "<txid>#<ix>"` (or the
  pinned predicate name); (b) when the input's `TxIn` resolves under
  the UTxO map, a `cardano:resolvedTo` link to a resolved-output
  subject block carrying the full output payload (address + lovelace
  + multi-asset + datum + scriptRef).
- **FR-005 (output semantic content)**: each output's subject block
  carries `atAddress` + `lovelace` + (optional) multi-asset RDF list
  + (optional) datum / datum-hash + (optional) scriptRef. The exact
  predicate names are pinned in plan.md once Q-002 lands.
- **FR-006 (cert semantic content)**: each certificate's subject block
  is typed under the variety-specific subclass and carries the
  variety's attributes. Scope for this PR (per Out of Scope below):
  StakeDelegation, VoteDelegation. Other variants raise
  `PUnsupportedLeafType` (fail-loudly inherited from #58).
- **FR-007 (withdrawal semantic content)**: each withdrawal's subject
  block carries the reward-account identifier link + the lovelace
  amount. Pre-existing `cardano:onCredential` + `cardano:withAmount`
  preserved or renamed per Q-002.
- **FR-008 (mint semantic content)**: each mint's subject block carries
  the policy + asset identifier links + the **signed** quantity (as
  an integer literal — negative for burns).
- **FR-009 (governance proposal)**: `TreasuryWithdrawals` proposals
  emit under the variety-specific class with distinct predicates for
  the proposer's returnAddr and each withdrawal target reward-
  account (replacing the current "multiple `hasIdentifier`" stub
  shape). Other proposal varieties continue to raise
  `PUnsupportedLeafType` (out of scope for #70).
- **FR-010 (body-root predicates)**: `_:tx`'s subject block carries
  `hasFee` (preserved from #58) plus, when present on the body, each
  of `hasTtl` / `hasValidityRangeStart` / `networkId` /
  `scriptDataHash` / `auxiliaryDataHash` (names finalized under
  Q-002). Elide when absent; no `null`-valued triples.
- **FR-011 (reference input support)**: the empty-leaf probe
  (`assertEmptyLeavesForT008`) is relaxed to permit non-empty
  `referenceInputs`; each reference input's `TxIn` emits a subject
  block bound to `_:tx` via `cardano:hasReferenceInput`. Required
  signers and total-collateral probes are unchanged — out of scope.
- **FR-012 (no-stub SPARQL view)**: `views/no-stub-triples.rq` ships
  in this PR and is exercised by the harness suite #45 set up. The
  view returns zero rows on every fixture in `test/fixtures/
  rewrite-redesign/*/` for the regenerated `expected.ttl`; a non-zero
  row count fails the build (CI gate).
- **FR-013 (vocab traceability extension)**: the
  `VocabTraceabilitySpec` invariant from #58 (which currently
  cross-checks emitted IRIs against the internal `VocabTerm`
  registry) extends to also cross-check every emitted predicate against
  the canonical `cardano-knowledge-maps/data/rdf/transactions.ttl`.
  Implementation depends on Q-002 — option 1 imports the canonical
  file as a test fixture and parses its declared terms; option 2/3
  permits a soft-fail and a tracking issue.
- **FR-014 (regenerate fixtures)**: each of the 11
  `test/fixtures/rewrite-redesign/<NN>-<slug>/expected.ttl` files is
  regenerated by running the new emitter and overwriting in place.
  Pre-PR `expected.ttl` survives via `git show HEAD~N:...`.
- **FR-015 (cast re-record)**: `docs/assets/asciinema/tx-graph.cast`
  is re-recorded by re-running `docs/assets/asciinema/scripts/
  tx-graph.sh` against a fixture exercising ≥4 per-field coverage
  rows (candidate: fixture 11). The cast's posterframe shows rich
  triples within the first ~3 s, per the existing player config
  (`poster: npt:0:3`).
- **FR-016 (existing invariants GREEN)**: SC-001..SC-008 from #58
  stay GREEN against the regenerated fixtures. Specifically the
  reproducibility check (run-twice → identical bytes) and JSON-LD ≡
  Turtle equivalence check carry forward unchanged.
- **FR-017 (Hackage-ready)**: `cabal check` + `cabal haddock
  lib:cardano-tx-tools` pass; the `gate.sh` for this PR preserves
  both invocations.
- **FR-018 (no scope creep into #50)**: typed datum decoding via
  Plutus blueprint stays out of scope; inline datums surface as
  opaque CBOR hex (or whatever literal shape Q-002 pins). The
  decoded-as-`TreasuryWithdrawals` stub from #58 is the only
  pre-blueprint typed projection this PR preserves; all other
  typed-datum work belongs to #50.

### Key Entities

- **`Emit`**: `WriterT [Triple] (State (Set Node))` — the internal
  monad threading triple accumulation + subject de-dup through the
  walker. Newtype-wrapped for derivability of `Functor` / `Applicative`
  / `Monad` / `MonadWriter` / `MonadState`.
- **`Node`**: synonym (or newtype around `Subject`) for the keys of
  the seen-set. The brief uses `Node`; the implementation may map it
  to `Subject`.
- **Per-Conway-field leaf**: every constructor of `ConwayDiffValue`
  the walker reaches at a leaf position — `ConwayCoinValue`,
  `ConwayAssetValue`, `ConwayTxInValue`, `ConwayDatumValue`,
  `ConwayScriptValue`, `ConwayProposalValue`, etc. (Full list in
  `Cardano.Tx.Diff` ≈ line 2361.)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001 (per-field coverage)**: every row in #70's *Scope* section
  and #46's "Per-field minimum coverage" section is exercised on every
  fixture in `test/fixtures/rewrite-redesign/` (subject to "absent →
  elided"). Verified by inspection of the regenerated `expected.ttl`
  files and the no-stub SPARQL view.
- **SC-002 (no-stub SPARQL gate)**: `views/no-stub-triples.rq` returns
  zero rows on every fixture in CI. Mechanically checked by a new
  `NoStubViewSpec` (or the harness suite #45 extends).
- **SC-003 (reference input decoding)**: fixture 11 emits without
  raising `PUnsupportedLeafType "ConwayReferenceInputValue"`. Verified
  by `EmitGoldenSpec` GREEN on fixture 11 after regen.
- **SC-004 (cast gate)**: `docs/assets/asciinema/tx-graph.cast` is
  re-recorded and the docs preview at the
  `${MKDOCS_SITE_URL}/tx-graph/` URL renders the rich output (manual
  reviewer verification — automated SPARQL check on the cast is not
  feasible).
- **SC-005 (vocab traceability extension)**: every predicate the
  regenerated `expected.ttl` files emit is declared in
  `cardano-knowledge-maps/data/rdf/transactions.ttl`. Exact shape of
  the check pinned by Q-002.
- **SC-006 (existing invariants preserved)**: SC-001..SC-008 from
  #58's spec stay GREEN; the existing 298-unit-examples suite count
  grows (new edge-case tests added) but does not shrink.
- **SC-007 (reproducibility preserved)**: running the new emitter
  twice on the same input yields byte-identical output (carry-over
  from #58 SC-005).
- **SC-008 (JSON-LD ≡ Turtle preserved)**: the JSON-LD serializer
  emits an equivalent graph (carry-over from #58 SC-002).
- **SC-009 (Hackage-ready)**: `cabal check` + `cabal haddock
  lib:cardano-tx-tools` pass on the regenerated codebase (carry-over
  from #58 SC-008).

## Deliverables — surface enumeration

Every release / packaging / docs surface tx-graph already lives on
must be exercised by this PR (resolve-ticket vertical-deliverables
rule). Discovery via `git grep -l 'tx-graph' .github/ flake.nix nix/
docs/ README.md CHANGELOG.md`:

1. **Linux release pipeline** (`.github/workflows/release.yml`):
   builds the tx-graph Linux tarball + artifacts; no per-PR changes
   needed — the release matrix already includes tx-graph (per #66,
   merged 2026-05-20).
2. **Darwin release pipeline** (`.github/workflows/darwin-release.yml`):
   builds the tx-graph aarch64-darwin tarball + Homebrew formula; no
   per-PR changes — the matrix entry is already in place.
3. **Darwin dev-Homebrew workflow**
   (`.github/workflows/darwin-dev-homebrew.yml`): publishes a
   `tx-graph-dev` formula on PR / workflow-dispatch with a usage-grep
   validation string. The validation string (`"operator-entity overlay
   + body emitter"`) should be reviewed against the new `--help`
   output once the emitter ships the rich content; updated in-PR if
   the help text changes.
4. **MkDocs deploy workflow**
   (`.github/workflows/deploy-docs.yml`): builds + deploys the docs;
   exports `MKDOCS_SITE_URL` for the preview / production split.
   Verify the cast embed renders on the preview URL.
5. **Nix executable + check**: `flake.nix` declares the `tx-graph`
   executable; `nix/checks.nix` exports `TX_GRAPH_EXE` for the unit
   suite to spawn the binary. No structural changes expected.
6. **Docs page** (`docs/tx-graph.md`): MkDocs page with embedded
   asciinema player. Update if the `--help` output or the three-mode
   description (`--rules`-only / `--tx`+`--utxo`+`--rules` / `--tx`
   only) changes meaning. Likely a `--help` excerpt refresh only.
7. **Asciinema cast** (`docs/assets/asciinema/tx-graph.cast` +
   `docs/assets/asciinema/scripts/tx-graph.sh`): re-record per FR-015
   / SC-004. The recording script itself may need a fixture switch
   (currently records overlay-only against the 11-amaru fixture; the
   #70 cast should also demonstrate body output).
8. **Homebrew taps** (`lambdasistemi/homebrew-tap`): tx-graph formula
   + tx-graph-dev formula are external — the release / dev-Homebrew
   workflows update them. No per-PR change needed unless the
   formula's `test do` block (Darwin release) needs a refresh once
   the `--help` text changes.
9. **README** (`README.md`): one-line description + two CLI examples
   for tx-graph. Update if the examples no longer produce rich
   output (the body-only example currently shows the stub shape on
   the merged main HEAD).
10. **CHANGELOG** (`CHANGELOG.md`): an entry under the next release
    cut summarizing the semantic-completeness change. Drafted in the
    final PR cycle (per release-please / Conventional Commits — not
    yet wired for this repo, so manual entry).
11. **No-stub SPARQL view** (`views/no-stub-triples.rq` — new file):
    ships with this PR; integrated into `gate.sh` (and the harness
    suite #45 set up) as a CI gate.

## Assumptions

- The post-#58 internal IR (`Cardano.Tx.Graph.Emit.Triple.Object`)
  supports new constructors as needed; `OHexLit` for raw bytes,
  `OByteStringLit` for credential bytes, etc. The brief lists them as
  candidate additions; the exact set is pinned in plan.md once
  Q-002 lands.
- The post-#58 walker reaches every leaf the per-field minimum
  coverage list names — i.e. the walker's *reach* is complete, only
  the *emission* at each leaf is partial. Validated by spec-phase
  inspection of `projectBody` (Project.hs lines 198–350) which already
  iterates inputs / outputs / mint / withdrawals / certs / proposals /
  collateral inputs.
- The harness #45 ships (and the post-#58 `expected.ttl` regen
  pattern) supports re-running `build-fixture.hs` per fixture to
  regenerate `expected.ttl` from the emitter without touching the
  builder code. Validated against the merged #58 lineage.
- The kmaps repo (`cardano-knowledge-maps`) is the authoritative
  source of `transactions.ttl`; vocab additions there are governed by
  a separate ticket lifecycle (parent decides via Q-002 whether to
  block on it).

## Out of Scope

- **Typed datum / redeemer decoding via CIP-57 blueprint** — that's
  #50. Inline datums in this PR surface as opaque CBOR hex (or
  equivalent literal); the `decodedAs` stub for `TreasuryWithdrawals`
  from #58 is preserved but not extended.
- **EYE reasoner integration + `--no-reason` fallback** — that's #49.
- **SPARQL view library** (`cli-tree`, `asset-flow`,
  `entity-occurrences`, `json-ld` views) — that's #51. The lone view
  this PR ships is `views/no-stub-triples.rq`, which is a CI gate, not
  a library view.
- **Diff-as-view** (RDF symmetric-difference mode) — that's #52.
- **Executable consolidation** (deprecating `tx-inspect`, `tx-diff`,
  re-aiming `tx-view`) — that's #53.
- **Migration docs + deprecation timeline** — that's #54.
- **Non-`StakeDelegation` / non-`VoteDelegation` certificate
  varieties** (`RegCert`, `UnRegCert`, `RegDepositTxCert`, pool certs,
  governance / committee / DRep registration certs). These continue
  to raise `PUnsupportedLeafType` from a clean failure surface;
  extending coverage belongs to a future ticket once an operator-
  authored fixture exercises them.
- **Non-`TreasuryWithdrawals` proposal varieties**
  (`ParameterChange`, `HardForkInitiation`, `NoConfidence`,
  `UpdateCommittee`, `NewConstitution`, `InfoAction`). Same rule —
  fail-loudly until a fixture exercises them.
- **Required signers, total-collateral, native-script reference
  scripts**: not exercised by the post-#45 fixture set; the
  empty-leaf probe stays in place for these (relaxed only for
  reference inputs per FR-011).
- **Witness-set / votingProcedures**: the per-field minimum coverage
  list names "proposals, votes, voter credentials" under governance,
  but the post-#45 fixture set only exercises proposals (fixture 10).
  Votes + voting procedures are deferred until a fixture exercises
  them — flagged as a follow-up below.

## Glossary

- **Stub shape**: `_:inputK a cardano:Input .` /
  `_:outputK a cardano:Output ; cardano:atAddress … .` — the post-#58
  emitter output that #70 replaces.
- **Per-Conway-field leaf**: a constructor of `ConwayDiffValue` the
  walker reaches at a terminal position — e.g. `ConwayCoinValue`
  carrying a `Coin`, `ConwayDatumValue` carrying a `Datum`.
- **Semantic completeness**: the property that every per-field
  minimum coverage row in #46's "Completeness — non-negotiable"
  section is exercised on every fixture. Distinct from #58's
  structural acceptance (byte-equivalence + JSON-LD equivalence +
  reproducibility), which gated structure-without-content.
- **Subject de-dup**: the `State (Set Node)` layer's responsibility —
  preventing a shared address / credential / asset class from
  emitting its predicate block twice.
- **No-stub SPARQL view**: `views/no-stub-triples.rq` — the CI gate
  that fails the build if any `cardano:Input` / `cardano:Output`
  subject has only an `rdf:type` triple and nothing else.

## Followup (orchestrator-owned, not this PR)

- **#49** (reasoner): consumes the now-rich graph; can now derive
  `owl:sameAs` triples from the per-field identifier overlay
  without per-PR projection coverage forcing.
- **#50** (blueprint): swaps inline-datum opaque CBOR hex for typed
  triples via CIP-57 schema.
- **#51** (views): SPARQL projections from the now-rich graph;
  unblocked once #70 lands.
- **#52** (diff-as-view): symmetric-difference mode now meaningful
  (was projecting from stubs in #58).
- **Conway feature coverage tickets**: votes + voting procedures,
  non-delegation cert varieties, non-`TreasuryWithdrawals` proposal
  varieties, native-script reference scripts, required signers,
  total-collateral. Each gets its own bisect-safe ticket once an
  operator-authored fixture is in hand.
- **Epic #46**: close the epic once #70 + #51 land — the per-field
  minimum coverage and the no-stub SPARQL gate close the
  "Completeness — non-negotiable" criterion; #51 makes the now-rich
  graph projectable into operator-facing views.

## References

- Issue: [lambdasistemi/cardano-tx-tools#70](https://github.com/lambdasistemi/cardano-tx-tools/issues/70)
- Predecessor: [lambdasistemi/cardano-tx-tools#58](https://github.com/lambdasistemi/cardano-tx-tools/issues/58) (merged 2026-05-20, PR #60)
- Epic: [lambdasistemi/cardano-tx-tools#46](https://github.com/lambdasistemi/cardano-tx-tools/issues/46) — see "Completeness — non-negotiable" + "Implementation pointer" sections.
- #58 spec: [`specs/058-body-emitter/spec.md`](../058-body-emitter/spec.md)
- Harness: [`specs/033-rewrite-redesign-harness/spec.md`](../033-rewrite-redesign-harness/spec.md)
- Rules loader: [`specs/048-rules-loader/spec.md`](../048-rules-loader/spec.md)
- Vocab (canonical): [`cardano-knowledge-maps/data/rdf/transactions.ttl`](https://github.com/lambdasistemi/cardano-knowledge-maps/blob/main/data/rdf/transactions.ttl)
- Walker entry point: `src/Cardano/Tx/Graph/Emit/Project.hs` (1118 LOC; see `projectBody` ≈ line 198)
- Existing IR: `src/Cardano/Tx/Graph/Emit/Triple.hs`
- Vocab registry (internal): `src/Cardano/Tx/Graph/Emit/Vocab.hs`
- Bnode naming: `src/Cardano/Tx/Graph/Emit/Lookup.hs`
- Turtle serializer: `src/Cardano/Tx/Graph/Emit/Serialize/Turtle.hs`
- JSON-LD serializer: `src/Cardano/Tx/Graph/Emit/Serialize/JsonLd.hs`
- Asciinema cast: `docs/assets/asciinema/tx-graph.cast` (+ recording script `docs/assets/asciinema/scripts/tx-graph.sh`)
- Worker brief: this PR's runtime root at `/tmp/epic-046/tx-70/`

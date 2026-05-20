# Tasks — Body emitter Conway semantic completeness (#70)

**Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md) · **Branch**: `070-body-emit-conway-semantic`

One bisect-safe commit per task. Each commit body carries `Tasks: TNNN`
(plus dependent task IDs if the slice composes multiple). The tasks.md
checkbox update rides in the **amended HEAD** of that slice's commit
(not a separate commit). Conventional Commits subject; non-empty body.

Paired-worker brief lives under
`/tmp/epic-046/tx-70/subagents/<slice-slug>/brief.md` for behavior-
changing slices (S1..S8). Pure plumbing / docs / chore slices the sub-
orchestrator may execute itself.

The driver/navigator subagent pair operates per resolve-ticket's
"Tmux-pane Pair Dispatch" — subagent worker ids are
`tx-70/<slice-slug>`; runtime roots live at
`/tmp/epic-046/tx-70/subagents/<slice-slug>/`; STATUS / questions /
answers structure replicates `/tmp/epic-046/tx-70/PROTOCOL.md`.

## Pre-implementation (already done)

- [x] **T001** — `gate.sh` bootstrap commit (e389648). `Tasks: T001`.
- [x] **T002** — `spec.md` initial draft (ac63380). `Tasks: T002`.
- [x] **T002a** — `spec.md` fold A-001 + A-002 (8647a5e). `Tasks: T002a`.
- [x] **T003** — kmaps additions Turtle patch at `/tmp/epic-046/tx-70/transactions-additions.ttl` (parent-side action surfaced via STATUS NOTE).
- [x] **T100a** — `plan.md` (current commit). `Tasks: T100a`.
- [ ] **T100b** — `tasks.md` (this file; lands in same commit as T100a — single planning-phase commit). `Tasks: T100b`.
- [ ] **T100c** — `analysis.md` (analyzer subagent dispatch — separate commit after T100a+T100b push). `Tasks: T100c`.

## Implementation slices (auto-continue, no phase stop)

### T101 — S0: vendor canonical-vocab pin (chore)

- **Subject**: `chore(070): vendor canonical-vocab pin at kmaps@8597fbd57`
- **Tasks trailer**: `Tasks: T101`
- **Files**:
  - `test/fixtures/canonical-vocab/transactions.ttl` (verbatim copy)
  - `test/fixtures/canonical-vocab/PINNED.md` (header with SHA + date + provenance URL)
- **RED**: none (no behavior change; pure data load).
- **GREEN**: `./gate.sh` passes; the new files are committed.
- **Live-boundary**: n/a.
- **Owner**: sub-orchestrator (self-execute; pure data vendoring).

### T102 — S1: introduce `Emit` monad + rewire walker (refactor — no behavior change)

- **Subject**: `refactor(070): hoist body walker into Emit = WriterT [Triple] (State (Set Subject))`
- **Tasks trailer**: `Tasks: T102`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Monad.hs` (NEW — `Emit`, `tellTriple`, `introduce`, `runEmit`, `groupBySubject`)
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (rewire `projectBody` to use the monad)
  - `cardano-tx-tools.cabal` (verify `mtl` dep is exposed — likely transitive already)
  - `test/Cardano/Tx/Graph/EmitMonadSpec.hs` (NEW — invariant: same `[Triple]` set as pre-refactor on fixture 02)
  - `test/Cardano/Tx/Graph/Emit/SubjectDeDupSpec.hs` (NEW — per analyzer M-002: parses emitted Turtle, groups triples by subject, asserts no two distinct subject blocks share the same subject node; covers spec US2)
- **RED**: `EmitMonadSpec` fails because `Emit.Monad` doesn't exist.
- **GREEN**: module lands; spec passes; **every fixture's `expected.ttl` byte-diff stays GREEN** (no semantic change).
- **Live-boundary**: Haskell module boundary — `groupBySubject` order
  preservation is the load-bearing invariant. The fixture-02 byte-diff
  is the smoke; if the diff drifts, the order assumption is wrong.
- **Owner**: paired subagents (driver/navigator). Brief at
  `/tmp/epic-046/tx-70/subagents/T102-emit-monad/brief.md`.

### T103 — S2: input `fromTxOutRef` + reference-input support (feat)

- **Subject**: `feat(070): emit cardano:fromTxOutRef on every input; support reference inputs`
- **Tasks trailer**: `Tasks: T103`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Vocab.hs` (add `TermFromTxOutRef`, `TermHasReferenceInput`)
  - `src/Cardano/Tx/Graph/Emit/Triple.hs` (verify `OStringLit` covers `<txid>#<ix>`; add `OHexLit` if a hex literal is the chosen lexical)
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (relax `assertEmptyLeavesForT008` for `referenceInputs`; emit `cardano:fromTxOutRef` per input)
  - `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` (FR-004 invariant)
  - All 11 fixtures' `expected.ttl` regenerated
- **RED**:
  1. `EmitGoldenSpec` invariant — every `_:inputK` carries `cardano:fromTxOutRef`.
  2. Fixture 11 emit returns `Right _` (no `PUnsupportedLeafType "ConwayReferenceInputValue"`).
  3. **(per analyzer M-001)** Every spending input under the UTxO map carries `cardano:resolvedTo _:resolvedN`, and `_:resolvedN` is bound (the resolved-output payload fills out across T104+T105 — confirmed at coverage rather than re-stubbed here).
- **GREEN**: emitter emits + reference-input probe relaxed; all 11
  `expected.ttl` regenerated.
- **Live-boundary**: fixture 11 — real on-chain CBOR with reference
  inputs. The strongest live-boundary smoke in the plan.
- **Owner**: paired subagents.

### T104 — S3: output `lovelace` + multi-asset RDF list (feat)

- **Subject**: `feat(070): emit cardano:lovelace + multi-asset RDF list on every output`
- **Tasks trailer**: `Tasks: T104`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Vocab.hs` (add `TermLovelace`, `TermMintsAsset`, `TermQuantity`)
  - `src/Cardano/Tx/Graph/Emit/Lookup.hs` (asset-class bnode naming for output-side multi-asset values)
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (extend `buildOutputs` to emit lovelace + multi-asset list)
  - `src/Cardano/Tx/Graph/Emit/Serialize/Turtle.hs` (only if a new RDF-list shape needs rendering)
  - `test/Cardano/Tx/Graph/Emit/OutputLovelaceSpec.hs` (NEW)
  - `test/Cardano/Tx/Graph/Emit/MultiAssetListSpec.hs` (NEW)
  - All 11 fixtures' `expected.ttl` regenerated
- **RED**: `OutputLovelaceSpec` + `MultiAssetListSpec` fail on the
  current emitter.
- **GREEN**: per-output lovelace + multi-asset list emit; regen.
- **Live-boundary**: fixtures 03 (multi-asset transfer), 04 (mint),
  11 (real on-chain multi-asset) — three independent multi-asset
  exercises.
- **Owner**: paired subagents.

### T105 — S4: output `hasDatum` + `hasReferenceScript`; remove proposal `Datum` overload (feat)

- **Subject**: `feat(070): emit unified hasDatum sub-block + hasReferenceScript on outputs`
- **Tasks trailer**: `Tasks: T105`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Vocab.hs` (add `TermHasDatum`, `TermHasReferenceScript`, `TermHasHash`, `TermHasRawBytes`; remove `TermDatum` predicate reuse — class stays)
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (per-output datum/ref-script emission; remove `cardano:Datum`-class overload from the proposal cluster — proposal cluster reshuffled in T108)
  - `src/Cardano/Tx/Graph/Emit/Triple.hs` (`OHexLit` constructor if not added by T103)
  - `test/Cardano/Tx/Graph/Emit/OutputDatumSpec.hs` (NEW)
  - `test/Cardano/Tx/Graph/Emit/OutputScriptRefSpec.hs` (NEW)
  - Fixture 01 (datum + scriptRef carrier), fixture 11 regenerated
- **RED**: `OutputDatumSpec` + `OutputScriptRefSpec` fail.
- **GREEN**: per-D-002 shape; presence of `hasRawBytes` distinguishes
  inline-vs-hash; ref-script shape per spec.
- **Owner**: paired subagents.

### T106 — S5: withdrawal canonical names + mint `mintsAsset` + signed `quantity` (feat)

- **Subject**: `feat(070): canonical withdrawalAccount + lovelace; signed mint quantity`
- **Tasks trailer**: `Tasks: T106`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Vocab.hs` (add `TermWithdrawalAccount`; remove `TermOnCredential` + `TermWithAmount`)
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (per-D-005 + D-004 shape)
  - `test/Cardano/Tx/Graph/Emit/WithdrawalCanonicalSpec.hs` (NEW)
  - `test/Cardano/Tx/Graph/Emit/MintQuantitySpec.hs` (NEW)
  - Fixtures 04, 05, 08 regenerated
- **RED**: both new specs fail.
- **GREEN**: canonical-aligned predicates + signed integer literal for
  burns.
- **Owner**: paired subagents.

### T107 — S6: body-root `hasValidityInterval` + `networkId` + `scriptDataHash` + `auxiliaryDataHash` (feat)

- **Subject**: `feat(070): emit body-root predicates (validity interval, networkId, *DataHash)`
- **Tasks trailer**: `Tasks: T107`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Vocab.hs` (add `TermHasValidityInterval`, `TermIntervalStart`, `TermIntervalEnd`, `TermNetworkId`, `TermScriptDataHash`, `TermAuxiliaryDataHash`)
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (emit interval sub-block + body-root extras when present; elide when `SNothing`)
  - `test/Cardano/Tx/Graph/Emit/BodyRootSpec.hs` (NEW)
  - Fixture builder extension if no current fixture exercises a body-root field (likely fixture 02 — add a TTL); else regen affected fixtures only
- **RED**: `BodyRootSpec` fails — body-root predicates absent.
- **GREEN**: object-shape interval per D-001; elision invariants.
- **Owner**: paired subagents.

### T108 — S7: proposal fallback shape (TreasuryWithdrawals inline-datum) (feat)

- **Subject**: `feat(070): proposal fallback shape — inline-datum sub-block per D-006 deferral`
- **Tasks trailer**: `Tasks: T108`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (replace `hasIdentifier`-spam with `hasDatum` sub-block + preserved `decodedAs`)
  - `test/Cardano/Tx/Graph/Emit/ProposalSpec.hs` (update to the new shape)
  - Fixture 10 regenerated
- **RED**: `ProposalSpec` updated assertions fail on the current emitter.
- **GREEN**: inline-datum shape with `decodedAs "TreasuryWithdrawals"`.
- **Owner**: paired subagents.

### T109 — S8: `views/no-stub-triples.rq` + gate-script integration (feat)

- **Subject**: `feat(070): no-stub SPARQL view + gate.sh integration`
- **Tasks trailer**: `Tasks: T109`
- **Files**:
  - `views/no-stub-triples.rq` (NEW)
  - `gate.sh` (extend to invoke the view against every fixture's regenerated `expected.ttl` — likely via a `just no-stub` recipe added in the same commit)
  - `test/Cardano/Tx/Graph/Emit/NoStubViewSpec.hs` (NEW)
  - `cardano-tx-tools.cabal` (verify `hspec` discovery picks up the new spec)
- **RED**: `NoStubViewSpec` fails because the view file doesn't exist
  AND the spec doesn't exist. Both land together; pre-spec the gate
  invocation fails fast.
- **GREEN**: view runs against every fixture; zero rows; spec GREEN.
- **Live-boundary**: emitter ↔ SPARQL gate. This is the load-bearing
  CI gate of the entire ticket.
- **Owner**: paired subagents.

### T110a — S9a: refresh canonical-vocab pin to kmaps#55 branch tip (chore)

- **Subject**: `chore(070): refresh canonical-vocab pin to kmaps#55 branch tip`
- **Tasks trailer**: `Tasks: T110a`
- **Files**:
  - `test/fixtures/canonical-vocab/transactions.ttl` (refresh — verbatim copy of `data/rdf/transactions.ttl` at `phase-a1-tx-semantic-predicates` HEAD of [kmaps#55](https://github.com/lambdasistemi/cardano-knowledge-maps/pull/55))
  - `test/fixtures/canonical-vocab/PINNED.md` (cite kmaps#55 + branch SHA + date; note "draft PR, not yet merged")
- **RED**: vocab-traceability spec fails on slices S2..S7 if the pin
  is still at kmaps@8597fbd57 (proposed predicates absent).
- **GREEN**: pin includes the 10 Phase A.1 additions; FR-013 strict
  check passes against the pin while the kmaps PR is still in draft.
- **Live-boundary**: data refresh — verify by re-running the
  vocab-traceability spec.
- **Sequencing**: lands **before** the first slice that emits a
  Phase A.1 predicate (T103 — `fromTxOutRef`). Recommended position
  in commit order: S0 → S1 → S9a → S2 → S3 … so the strict CI gate
  is happy on every behavior-changing slice.
- **Owner**: sub-orchestrator (self-execute; the kmaps PR is open
  at draft, branch tip stable).

### T110b — S9b: refresh canonical-vocab pin to merged kmaps `main` SHA (chore — finalization-blocking)

- **Subject**: `chore(070): refresh canonical-vocab pin to kmaps@<merged-main-sha>`
- **Tasks trailer**: `Tasks: T110b`
- **Files**:
  - `test/fixtures/canonical-vocab/transactions.ttl` (refresh to merged main)
  - `test/fixtures/canonical-vocab/PINNED.md` (update SHA + date + drop "draft" note)
- **RED**: none (pin refresh; vocab content unchanged from S9a).
- **GREEN**: pin SHA matches a merged kmaps `main` commit.
- **Sequencing**: blocks PR #77 finalization (T113). If kmaps#55
  hasn't merged by the time S0..S12 are otherwise ready, file a
  Q-file rather than flip the PR to ready.
- **Owner**: sub-orchestrator (parent will surface the merged SHA on
  STATUS.md / via NOTE-line; T110b lands as a single-line commit).

### T111 — S10: re-record asciinema cast + docs refresh (docs)

- **Subject**: `docs(070): re-record tx-graph cast against rich body emission; refresh docs`
- **Tasks trailer**: `Tasks: T111`
- **Files**:
  - `docs/assets/asciinema/tx-graph.cast` (re-record via
    `docs/assets/asciinema/scripts/tx-graph.sh`)
  - `docs/assets/asciinema/scripts/tx-graph.sh` (fixture switch if
    needed — record against fixture 11 to demonstrate ≥4 per-field
    coverage rows)
  - `docs/tx-graph.md` (refresh `--help` excerpt if surface changed;
    update the three-mode example if needed)
  - `README.md` (update the body-only example if it still showed the
    stub shape)
- **RED**: manual reviewer check at the preview URL
  `${MKDOCS_SITE_URL}/tx-graph/` after CI deploys. Cast that shows
  only `_:inputK a cardano:Input .` is a deliverables failure.
- **GREEN**: preview-URL viewer sees real fee + lovelace + addresses +
  datum / scriptRef / certificate / mint / withdrawal triples.
- **Live-boundary**: emitter → recorded session → docs deploy →
  player JS. The cast is opaque to RDF tooling so the diagnostic is
  manual.
- **Owner**: sub-orchestrator (self-execute; pure docs / cast work).

### T112 — S11: CHANGELOG entry (docs)

- **Subject**: `docs(070): CHANGELOG entry for body-emitter semantic completeness`
- **Tasks trailer**: `Tasks: T112`
- **Files**:
  - `CHANGELOG.md` (one entry under the next release cut)
- **RED**: none (pure docs).
- **GREEN**: `./gate.sh` passes.
- **Owner**: sub-orchestrator.

### T113 — S12: drop gate.sh (ready for review) (chore)

- **Subject**: `chore(070): drop gate.sh (ready for review)`
- **Tasks trailer**: `Tasks: T113`
- **Files**:
  - `gate.sh` (delete)
- **RED**: n/a — finalization step.
- **GREEN**: `git status` clean; PR's TODO checklist all-checked; flip
  draft → ready via `gh pr ready 77`. **Mark this commit's commit
  body with the explicit `Finalization: yes` token so the
  `finalization_audit` bash function (per `gate-script` skill) picks
  it up.**
- **Owner**: sub-orchestrator.

## Cross-slice invariants

These specs run on every behavior-changing slice (S1..S8) — never
deleted, only extended:

- `EmitGoldenSpec` — byte-diff per fixture vs `expected.ttl`.
- `ReproducibilitySpec` (#58 SC-005) — run-twice → identical bytes.
- `JsonLdEquivalenceSpec` (#58 SC-002) — JSON-LD ≡ Turtle.
- `VocabTraceabilitySpec` (#58 SC-006, extended FR-013) — every
  emitted CURIE traces to a term declared in the internal `VocabTerm`
  registry AND in the vendored canonical-vocab pin.
- `NoStubViewSpec` (T109+) — SPARQL view returns zero rows on every
  fixture.
- `SubjectDeDupSpec` (T102+) — no two distinct subject blocks share
  the same subject node.
- Constitution sweep — `cabal check`, `cabal haddock`, `fourmolu`,
  `hlint`, `cabal-fmt` — inherited from `gate.sh`.

## Parent-side parallel work (not a task this worker executes)

- **K1** — Parent opens kmaps PR using
  `/tmp/epic-046/tx-70/transactions-additions.ttl` as the body.
  **DONE — A-004:** kmaps#55 opened on branch
  `phase-a1-tx-semantic-predicates`, base kmaps@8597fbd57, body
  matches the patch verbatim (+79 lines, 10 properties), state =
  draft. Worker's T110a pin-refresh now targets the PR's branch tip.
- **K2** — On merge, parent surfaces the merged kmaps `main` SHA
  via STATUS / answer-file so worker's T110b commit message can
  cite it precisely.

## Follow-on tickets (filed at #70 finalization, NOT during this PR)

- **F1** — "Expose monadic `traverseConwayDiff` from `Cardano.Tx.Diff`
  if/when #51 / #52 want a shared walker" (per A-001).
- **F2** — "Phase B vocab refresh: certificate class subtypes,
  governance-procedure classes, #58-inherited drift cleanup" against
  `lambdasistemi/cardano-knowledge-maps` (per A-002).
- **F3** — "Proposal subject typing — `cardano:Proposal` class +
  `proposerReturnAddr` + `withdrawalTarget` predicates" against
  cardano-tx-tools + kmaps (D-006 deferral closure).
- **F4** — Non-`StakeDelegation`/`VoteDelegation` cert variants and
  non-`TreasuryWithdrawals` proposal variants — one ticket per
  variant family once an operator-authored fixture exercises it.

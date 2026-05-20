# Tasks — Body emitter (#58)

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Research**: [research.md](./research.md)

Each implementation task is one bisect-safe commit produced by a single
subagent run. RED and GREEN fold into that one commit. The orchestrator
amends each subagent's HEAD commit to add the `Tasks: T###` trailer and
tick the matching checkbox here; no separate task-stamping commit.

Non-code tasks (regen authoring, docs, chore) are marked
`type=docs`/`type=chore` so the analyzer can distinguish them from
behaviour-changing slices.

Legend: `[ ]` = pending, `[X] T###` = closed in the commit whose body
carries `Tasks: T###`.

## Phase 0 — orchestrator gate

- [ ] **T000** *(orchestrator-owned; not a subagent slice)* — Analyzer
  dispatch via `speckit-analyze` against spec.md, plan.md, research.md,
  tasks.md. Address findings (or fail-fast back through speckit-plan/tasks)
  before T001 starts. Open Q-files for the design questions in plan.md
  "Pre-implementation prereqs" (PRE-2 loader API extension, PRE-3
  raw-bytes-bnode prefix length N, PRE-4 CLI mode dispatch) so the
  orchestrator can confirm before any code lands.

---

## Phase 1 — loader API extension (chore-shaped against #48's surface)

- [X] **T001** *(type=refactor, subagent slice; FR-010 / plan D7 / research R5)*
  — Extend `Cardano.Tx.Graph.Rules.Load.RulesLoadResult` with a new
  field `rulesEntities :: [EntityDecl]` carrying the in-memory entity
  list. The data is already computed by the loader internally; this
  slice surfaces it on the public API. The existing
  `RulesLoadGoldenSpec` byte-diff (#48 SC-001) MUST stay GREEN.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (add field to the
    `RulesLoadResult` record + thread it through `loadWithResolver`'s
    return).
  - `test/Cardano/Tx/Graph/Rules/LoadEntitiesSpec.hs` (new file —
    asserts that for one fixture, `rulesEntities` contains the same
    entity slugs as the overlay's prefix declarations imply).

  **Forbidden scope**: anything outside the loader module + the new
  test module. No `gate.sh` edits. No new exe flags.

  **RED proof**: before this slice, attempting to read
  `rulesEntities` from `RulesLoadResult` is a compile error
  (`No field of name 'rulesEntities'`). The new test file expects
  this compile error to clear.

  **GREEN proof**: `nix develop --quiet -c just unit
  "LoadEntitiesSpec"` passes; the existing `RulesLoadGoldenSpec`
  passes (11/11 byte-diff still GREEN). `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): expose rulesEntities on RulesLoadResult`

- [X] **T001a** *(type=docs, orchestrator-owned or subagent slice;
  Q-003 → A-003 / research R4 Q-003 discovery)* — Migrate artisan
  narrative comments from each fixture's current `expected.ttl` to a
  new per-fixture `NOTES.md` markdown file. Pure documentation slice;
  no behaviour change; no `expected.ttl` regen yet (that begins in
  T005+). The migration is mechanical: extract every `#`-prefixed
  line, group adjacent runs into markdown sections, drop redundant
  section-header comments (`# Input N`, `# Operator-declared entities`)
  which the regen re-emits uniformly, preserve narrative content
  (story arcs, invariant explanations, ticket cross-references) as
  markdown. Editorial cleanup is fine where it improves readability
  (`#` headers → `##` headers, `*` lists → `-` lists); no new content
  added.

  **Owned files**:
  - `test/fixtures/rewrite-redesign/<NN>-*/NOTES.md` — 11 new files,
    one per fixture (02, 03, 04, 05, 06, 07, 08, 09, 10 plus 01, 11).

  **Forbidden scope**: anything else. No edits to `expected.ttl`,
  `expected.txt`, `expected.entities.ttl`, `rules.yaml`, builder
  modules, library code, gate.sh.

  **GREEN proof**: 11 new files committed; `./gate.sh` exits 0 (no
  behaviour change so build + unit + lint + cabal-fmt + cabal check +
  haddock all stay GREEN as before). Spot-check via `wc -l` shows
  reasonable content density per fixture (fixture 04's `NOTES.md`
  should be the heaviest given its 111-line narrative; fixture 02's
  should be minimal).

  **Strategy hint** (one bulk commit recommended): A-003 approved one
  bulk commit for mechanical extraction. If a single fixture's
  narrative needs non-trivial editorial cleanup (e.g., a tangled
  cross-reference to a closed ticket), escalate via a Q-file and ship
  that fixture's `NOTES.md` in a follow-up commit.

  **Commit subject**: `docs(058): migrate artisan narrative to NOTES.md per fixture`

---

## Phase 2 — body emitter scaffold + CLI extension

- [X] **T002** *(type=feat, subagent slice; plan slice 2 / FR-001 +
  FR-003)* — Scaffold `Cardano.Tx.Graph.Emit` module: public types
  (`EmitError`, `EmittedGraph`, `EmitFormat`), top-level `emit`
  function stub that accepts a `ConwayTx` + `ResolvedUTxO` +
  `[EntityDecl]` and returns an empty graph on any input (no
  projection walk yet). The smoke test asserts the stub compiles
  and returns `Right (EmittedGraph mempty mempty mempty)` for a
  hand-built minimal `ConwayTx`. No serializer yet (S5 lands the
  Turtle one).

  **Owned files**:
  - `src/Cardano/Tx/Graph/Emit.hs`
  - `cardano-tx-tools.cabal` (add `Cardano.Tx.Graph.Emit` to
    `exposed-modules`)
  - `test/Cardano/Tx/Graph/EmitSmokeSpec.hs` (new file)

  **Forbidden scope**: `Project.hs`, `Lookup.hs`, `Serialize.*` (those
  land in T004 + T005); `gate.sh`; rules-loader module; fixtures.

  **RED proof**: before this slice, `import Cardano.Tx.Graph.Emit` is
  a compile error.

  **GREEN proof**: `nix develop --quiet -c just unit "EmitSmokeSpec"`
  passes. `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): scaffold Cardano.Tx.Graph.Emit module`

- [X] **T003** *(type=feat, subagent slice; plan slice 3 / FR-008 +
  FR-012)* — Extend `tx-graph` executable with `--tx`, `--utxo`,
  `--out`, `--format` flags + flag-presence dispatcher (plan D8 /
  research R6) + structured error rendering for missing files /
  decode failures. The dispatcher routes to:
  - overlay-only path (existing #48 behaviour, no change),
  - body-only path (calls `emit` with empty `[EntityDecl]`),
  - joint-graph path (calls `emit` with the loaded entity list).
  In this slice the emitter still returns an empty graph (T002 stub)
  and the Turtle serializer doesn't exist yet (lands in T005). The
  executable handles the pre-T005 gap as follows (analyzer M2):
  - **overlay-only mode** keeps #48's existing path verbatim (no change).
  - **body-only and joint-graph modes** exit with `EmitError
    NoSerializerYet` (a new variant added to T002's `EmitError` in
    this slice's owned-file scope on `Emit.hs`); the exe-level smoke
    test asserts that variant + non-zero exit. The dispatcher
    machinery is fully wired; only the serializer call is gated. T005
    removes the `NoSerializerYet` variant and wires the real
    serializer.

  **Owned files**:
  - `app/tx-graph/Main.hs`
  - `src/Cardano/Tx/Graph/Emit.hs` (add `NoSerializerYet` variant to
    `EmitError`; remove in T005)
  - `test/Cardano/Tx/Graph/TxGraphExeSpec.hs` (new file — uses the
    `TX_GRAPH_EXE` env-var pattern from #48 920a496)
  - `cabal.project` if a new test-suite dependency is needed (likely
    not — `process` is already in the dep closure).

  **Forbidden scope**: emitter projection walker (T005 owns it);
  Turtle/JSON-LD serializers (T005 + T011); `gate.sh`; fixtures.

  **RED proof**: before this slice, `tx-graph --tx foo --utxo bar`
  exits with an `optparse-applicative` unknown-flag error.

  **GREEN proof**: overlay-only mode produces the same overlay output
  as #48's `tx-graph --rules` invocation (back-compat preserved).
  Body-only and joint modes exit non-zero with
  `EmitError NoSerializerYet` on stderr. Structured errors for
  missing files / CBOR decode failures / UTxO JSON decode failures
  exit non-zero with stderr text containing the variant tag.
  `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): tx-graph --tx/--utxo/--out/--format flags`

---

## Phase 3 — credential lookup + raw-bytes naming

- [X] **T004** *(type=feat, subagent slice; plan slice 4 / FR-004 +
  FR-005 + plan D3 + D4 + research R3)* — Credential lookup table
  (`Map (LeafType, ByteString) BnodeName`) + raw-bytes-named bnode
  scheme (`_:cred_<rolePrefix>_<bytes-prefix>` with `N = 16`). Unit
  tests cover: (a) entity-named lookup hit, (b) raw-bytes-named
  lookup miss, (c) shared-identity case (first-entity wins, second
  references same bnode), (d) injectivity proof — across every
  credential in all 11 fixtures, the `(rolePrefix, bytes-prefix)`
  projection is injective at `N = 16`. Pin `N = 16` as a top-level
  constant `rawBytesPrefixLength` in `Lookup.hs` with a comment
  citing research R3.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Emit/Lookup.hs` (new file)
  - `src/Cardano/Tx/Graph/Emit.hs` (re-export the lookup-table type
    if needed by the smoke test surface).
  - `test/Cardano/Tx/Graph/Emit/LookupSpec.hs` (new file)

  **Forbidden scope**: `Project.hs`, `Serialize.*`, executable,
  fixtures.

  **RED proof**: the new spec defines test cases that fail because
  `Lookup` doesn't exist or returns wrong bnodes.

  **GREEN proof**: `nix develop --quiet -c just unit "LookupSpec"`
  passes. The injectivity property test (which enumerates every
  fixture's credentials) passes. `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): credential lookup + raw-bytes bnode naming`

---

## Phase 4 — projection walker + first fixture GREEN

- [X] **T005** *(type=feat, subagent slice; plan slice 5 / FR-002 +
  FR-003 + research R2 + R4)* — Body-section projection walker
  covering the leaves needed for fixture 02 (`Tx`, `Input`, `Output`,
  `Address`, `Credential PaymentKey`, `Credential StakeKey`, fee).
  Canonical Turtle serializer for `EmittedGraph` (plan D5). Regenerate
  `test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.ttl` from
  the emitter output. Add `EmitGoldenSpec` test module that registers
  the 11-fixture iterator but with only fixture 02 enabled in this
  slice (the others are listed as `pendingWith` until later slices
  cover their leaves).

  **Owned files**:
  - `src/Cardano/Tx/Graph/Emit.hs` (wire projection walk + serializer
    call into `emit`; remove the `NoSerializerYet` variant T003
    introduced).
  - `src/Cardano/Tx/Graph/Emit/Project.hs` (new — projection walker
    for fixture-02-class leaves only).
  - `src/Cardano/Tx/Graph/Emit/Serialize/Turtle.hs` (new — canonical
    Turtle serializer per plan D5).
  - `src/Cardano/Tx/Graph/Emit/Vocab.hs` (new — single-source-of-truth
    registry of every `cardano:` Phase A IRI the emitter uses;
    analyzer M3 closer for FR-009).
  - `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` (new — registers all
    11 fixtures; only fixture 02 enabled now).
  - `test/Cardano/Tx/Graph/Emit/VocabTraceabilitySpec.hs` (new —
    analyzer H1 closer for SC-005 + FR-009; per-emit assertion that
    (a) every `@prefix` declaration is in `{cardano, rdfs,
    fixture-local ":"}`, (b) no IRI in the emitted output uses any
    other namespace, (c) no `_internal:` substring leaks. Runs on
    fixture 02's output in this slice; T006-T010 keep the spec
    enabled — every regen passes the same check).
  - `test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.ttl`
    (regenerated; the artisan file is overwritten — git history
    retains the prior version).

  **Forbidden scope**: other fixtures' `expected.ttl` files (later
  slices), JSON-LD serializer, executable surface (T003 owns it).

  **RED proof**: a freshly-regenerated `02-alice-bob-ada/expected.ttl`
  candidate must byte-diff against the emitter's output (fail) until
  the projection walker is implemented correctly. The orchestrator
  inspects the candidate against the artisan reference (`git show
  HEAD:test/fixtures/.../expected.ttl` before the regen lands) before
  accepting. Additionally `VocabTraceabilitySpec` fails RED until the
  serializer routes every IRI through `Vocab.hs`.

  **GREEN proof**: `nix develop --quiet -c just unit
  "EmitGoldenSpec"` passes (fixture 02 GREEN; others `pendingWith`).
  `nix develop --quiet -c just unit "VocabTraceabilitySpec"` passes
  (closes SC-005 + FR-009). The executable smoke test from T003 now
  produces the correct joint graph for fixture 02 (parseable Turtle).
  `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): body emitter + fixture 02 byte-diff + vocab traceability`

---

## Phase 5 — extend leaf coverage, regenerate fixtures

Each slice in this phase ships one or more new projection cases plus
the regenerated `expected.ttl` files for the fixtures the new cases
unblock. Per-slice scope is fixture-driven so each commit is a
self-contained "this projection case + this fixture's regen".

- [ ] **T006** *(type=feat, subagent slice; plan slice 6 / research R2)*
  — Mint section + `Policy` + `AssetClass` leaves. Regenerate fixture
  **03** (multi-asset transfer). Fixture 10 moves to T010 (analyzer
  H2 fix) because its `Vote` + `TreasuryWithdrawal` leaves are
  fixture-10-only governance-action shapes — they fit the "every
  residual leaf type" framing T010 already owns better than they fit
  T006's mint scope.

  **Owned files**: `Project.hs` (new mint-related cases),
  `test/fixtures/rewrite-redesign/03-multi-asset-transfer/expected.ttl`.

  **GREEN proof**: `EmitGoldenSpec` GREEN for fixtures 02 + 03
  (others remain `pendingWith`). `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): mint + policy + assetClass leaves; fixture 03`

- [ ] **T007** *(type=feat, subagent slice; plan slice 7 / research R2)*
  — Script-witness leaves: `Credential PaymentScript`,
  `Credential StakeScript`, `Redeemer`, inline-datum / datum-hash /
  script-ref triples. Regenerate fixtures **04** (mint-spend script
  overlap), **05** (withdrawal-script-stake), **08** (contingency
  disburse).

  **Owned files**: `Project.hs` (script-witness cases),
  `test/fixtures/rewrite-redesign/0{4,5,8}-*/expected.ttl` (three
  regenerated files).

  **GREEN proof**: `EmitGoldenSpec` GREEN for fixtures 02, 03, 04, 05,
  08. `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): script-witness leaves; fixtures 04, 05, 08`

- [ ] **T008** *(type=feat, subagent slice; plan slice 8 / research R2)*
  — Cert leaves (`StakeRegistration`, `StakeDelegation`,
  `VoteDelegation`) + `PoolId` + `DRep` target leaves. Regenerate
  fixtures **06** (stake-pool delegation) and **07** (vote-delegation).

  **Owned files**: `Project.hs` (cert + pool + drep cases),
  `test/fixtures/rewrite-redesign/0{6,7}-*/expected.ttl` (two
  regenerated files).

  **GREEN proof**: `EmitGoldenSpec` GREEN for fixtures 02-08.
  `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): cert + pool + drep leaves; fixtures 06, 07`

- [ ] **T009** *(type=feat, subagent slice; plan slice 9 / research R2)*
  — MPFS-facts + ad-hoc complex leaves needed by fixture 09. Regenerate
  fixture **09** (mpfs-facts-request).

  **Owned files**: `Project.hs` (residual leaves),
  `test/fixtures/rewrite-redesign/09-mpfs-facts-request/expected.ttl`.

  **GREEN proof**: `EmitGoldenSpec` GREEN for fixtures 02-09 (8
  fixtures). `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): mpfs-facts leaves; fixture 09`

- [ ] **T010** *(type=feat, subagent slice; plan slice 10 / research R2)*
  — Largest + residual-leaf fixtures **01** (amaru-treasury-swap
  hypothetical), **10** (governance treasury withdrawal — moved from
  T006 per analyzer H2), and **11** (amaru-treasury-swap-real). By
  this slice the emitter must handle every leaf type used by any
  fixture, including the `Vote` + `TreasuryWithdrawal` governance-action
  leaves unique to fixture 10. This is the final byte-diff slice;
  SC-001 closes here.

  **Owned files**: `Project.hs` (governance-action leaves
  + any residual leaves for 01 + 11),
  `test/fixtures/rewrite-redesign/01-amaru-treasury-swap/expected.ttl`,
  `test/fixtures/rewrite-redesign/10-governance-treasury-withdrawal/expected.ttl`,
  `test/fixtures/rewrite-redesign/11-amaru-treasury-swap-real/expected.ttl`
  (three regenerated files).

  **GREEN proof**: `EmitGoldenSpec` GREEN for all 11 fixtures (no
  `pendingWith` remaining). SC-001 closed. `VocabTraceabilitySpec`
  stays GREEN across all 11. `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): governance-action leaves; fixtures 01, 10, 11`

---

## Phase 6 — JSON-LD serializer + reproducibility

- [ ] **T011** *(type=feat, subagent slice; plan slice 11 / FR-007 +
  SC-003 + research R1)* — JSON-LD serializer in
  `Cardano.Tx.Graph.Emit.Serialize.JsonLd`. `JsonLdEquivalenceSpec`
  parses both Turtle + JSON-LD outputs per fixture and asserts
  set-equal triple sets. The JSON-LD parser used by the spec is
  in-house (small subset matching what the serializer emits).

  **Owned files**:
  - `src/Cardano/Tx/Graph/Emit/Serialize/JsonLd.hs` (new)
  - `test/Cardano/Tx/Graph/Emit/JsonLdEquivalenceSpec.hs` (new)

  **GREEN proof**: 11/11 fixtures have set-equal Turtle/JSON-LD
  triple sets. SC-003 closed. `./gate.sh` exits 0.

  **Commit subject**: `feat(graph): JSON-LD serializer + equivalence spec`

- [ ] **T012** *(type=test, subagent slice; plan slice 12 / FR-006 +
  SC-004)* — `ReproducibilitySpec` runs `emit` twice on each fixture
  and asserts byte-equality of the two outputs. Catches Set/Map
  iteration-order leaks and other non-determinism sources.

  **Owned files**:
  - `test/Cardano/Tx/Graph/Emit/ReproducibilitySpec.hs` (new)

  **GREEN proof**: 11/11 fixtures byte-identical on back-to-back
  runs. SC-004 closed. `./gate.sh` exits 0.

  **Commit subject**: `test(graph): reproducibility spec for emitter`

---

## Phase 7 — docs + ready-for-review

- [ ] **T013** *(type=docs, orchestrator-owned or subagent slice;
  plan slice 13)* — README + CHANGELOG + docs/ entries for the new
  `tx-graph` flags + the regenerated `expected.ttl` workflow. Update
  `docs/` (if any pages need it). Add a CHANGELOG entry under the
  next-release header describing the body emitter, the FR-010 loader
  API extension, and the regeneration of `expected.ttl` for all 11
  fixtures (noting the artisan files' obsoletion).

  **Owned files**:
  - `README.md`
  - `CHANGELOG.md`
  - `docs/` (if any pages reference the executable surface)

  **GREEN proof**: README's `tx-graph` section documents all three
  modes (overlay-only, body-only, joint) with one example invocation
  each; CHANGELOG entry under the next-release header mentions
  FR-010 (RulesLoadResult.rulesEntities), the body emitter,
  the regeneration of `expected.ttl` for all 11 fixtures (artisan
  obsoletion + NOTES.md migration), and the `tx-graph --tx/--utxo/--out/--format`
  flag additions; `docs/` (if applicable) updated for the new flags.
  Docs render cleanly via `nix develop --quiet -c just mkdocs` (if
  used). `./gate.sh` exits 0.

  **Commit subject**: `docs(058): README + CHANGELOG for body emitter`

- [ ] **T014** *(type=chore, orchestrator-owned; gate-script skill)*
  — Drop `gate.sh` in a dedicated commit, mark PR #60 ready for
  review.

  **Owned files**:
  - `gate.sh` (removed)

  **GREEN proof**: `git rm gate.sh` lands; `gh pr ready 60` returns
  the PR to ready state. The finalization audit (`gate-script` skill)
  re-runs the per-commit `commit_gate` over every commit on the
  branch and reports clean.

  **Commit subject**: `chore(058): drop gate.sh (ready for review)`

---

## Summary

- **Behaviour-changing slices**: T001 + T002 + T003 + T004 + T005 + T006
  + T007 + T008 + T009 + T010 + T011 + T012 = 12.
- **Docs/chore slices**: T001a + T013 + T014 = 3.
- **Total slices**: 15 (12 behaviour-changing + 3 docs/chore).
- **Acceptance pivots**: T001a (narrative migration; pre-regen gate) →
  T005 (first fixture GREEN) → T010 (all 11 GREEN) → T014
  (ready-for-review).

## Cross-PR contract

- `EmitGoldenSpec` byte-diffs the emitter's Turtle output against the
  regenerated `expected.ttl` for all 11 fixtures. Closed by T010.
- The artisan `expected.ttl` files merged in #45 are obsoleted by the
  regen; they survive in git history (`git show HEAD~N:.../expected.ttl`)
  as authoring references.
- The #48 `RulesLoadGoldenSpec` byte-diff for `expected.entities.ttl`
  stays GREEN throughout. T001 (loader API extension) is additive;
  T005-T010 do not touch `expected.entities.ttl` files.

## Q-file log

- **Q-001** → A-001 (2026-05-20): cross-PR contract = Option A
  (regenerate `expected.ttl` for 11/11 in-PR). Encoded in spec.md
  Clarifications + this tasks.md.
- **Q-002** → A-002 (2026-05-20): 6 design choices approved
  (loader API extension, library/exe boundary, raw-bytes-bnode scheme,
  CLI dispatch, per-fixture regen, uniform Turtle byte-shape); analyzer
  dispatch authorized after the Q-003 fold-in.
- **Q-003** → A-003 (2026-05-20): artisan narrative comments migrate to
  per-fixture `NOTES.md` markdown files (Option B over A/C/D). Encoded
  in spec.md Clarifications + Key Entities + Glossary, plan.md D5,
  research.md R4, and tasks.md T001a.
- **Analyzer run** (2026-05-20): `speckit-analyze` sub-worker returned
  LOOP-BACK-TO-tasks with 2 HIGH + 4 MEDIUM findings; no critical or
  constitution conflicts. Findings: `specs/058-body-emitter/analysis.md`.
  Remediation folded inline:
  - **H1** (SC-005 / FR-009 traceability): T005 now adds
    `Cardano.Tx.Graph.Emit.Vocab` module + `VocabTraceabilitySpec`
    asserting prefixes ⊆ {cardano, rdfs, fixture-local} and no
    `_internal:` leak.
  - **H2** (T006/fixture-10 leaf scope): fixture 10 moved from T006
    to T010; T010 owns the governance-action leaves (Vote +
    TreasuryWithdrawal); T006 keeps just fixture 03.
  - **M2** (T003 pre-T005 serializer gap): T003 now ships an
    `EmitError NoSerializerYet` variant that body-only / joint exe
    modes return until T005 wires the real serializer.
  - **M3** (vocab module pinning): named in T005's owned files as
    `Cardano.Tx.Graph.Emit.Vocab`.
  - **M4** (kmaps Phase A vocab gap risk): added as plan R-8.
  - **L3** (T013 GREEN-proof tightening): T013's GREEN proof now
    enumerates README/CHANGELOG/docs content requirements.
  - M1 (Cardano.Ledger.* boundary enforcement) + L1 + L2 left as
    code-review invariants / harmless redundancy / optional cross-ref
    per analyzer notes.

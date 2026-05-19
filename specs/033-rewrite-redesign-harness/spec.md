# Feature Specification: Test-fixture harness — ten reproducible Conway transactions + Turtle/text golden infrastructure

**Feature Branch**: `45-harness-conway-fixtures-045`
**Created**: 2026-05-19
**Status**: Draft
**Input**: Build the test-fixture harness the rewrite-rules redesign depends on. Ten Haskell builders, each producing a `Tx ConwayEra` value. For each: per-story `rules.yaml`, per-story `expected.ttl` (Turtle golden the future emitter must produce), per-story `expected.txt` (the 044 text shape, recovered by the future `cli-tree` SPARQL view from `expected.ttl`). Two CIP-57 blueprint files (`swap-v2-datum`, `mpfs-fact`). One golden test suite (`RewriteRedesignGoldenSpec`) exercising all ten fixtures. Re-aimed under epic #46 (`specs/045-graph-emit-pivot`): expected-output format moved from text-only to Turtle + SPARQL-view-derived text. Wave 0 in the epic; runs in parallel with `cardano-knowledge-maps#53` (vocab); does NOT block on #47 (emitter MVP) or #51 (views).

## Background — what the harness exists for

The 044 rewrite-rules redesign (preserved as design context, superseded for shipment by 045) names a single acceptance contract: ten Conway transactions, each accompanied by a rules YAML and an expected rendering, that together cover every identifier role class, the blueprint-decoded-datum path, the nested-collapse path, the collapse-suppresses-rename bug, and the cross-leaf entity-identity property. The 045 pivot keeps the ten transactions verbatim and re-targets the expected output: `expected.ttl` is the Turtle graph the future emitter (#47) must produce; `expected.txt` is the byte-for-byte 044 text shape, recovered from `expected.ttl` by the future `cli-tree` SPARQL view (#51).

This harness ships **only the fixture set and the goldens scaffolding** — no emitter, no SPARQL runtime. The goldens are the contract; the engine and the views catch up in their own tickets. Once shipped, the harness anchors the epic: every downstream wave (#47, #48, #49, #50, #51, #52) has a runnable target to compare against, and the eight 044 follow-up tickets (#34..#40, #43) are reviewable against this evidence.

## Clarifications

### Session 2026-05-19

- Q: What's the relationship between this harness and the 044 spec's ten user stories?
  → A: The ten 044 user stories are the **fixture catalogue**. Each carries over verbatim: same Conway transaction shape, same operator rules YAML, same expected text output. The 045 pivot adds Turtle as the canonical expected output and demotes the 044 text to a derived projection. The harness ships both forms.
- Q: How does the harness behave on a CI run when neither #47 nor #51 has landed?
  → A: The golden test suite is **wired and pending**. Each per-story behaviour (Turtle byte-equivalence, text byte-equivalence) is registered as a `pending "awaits #NN"` Hspec item until the corresponding upstream lands. Structural checks (the builder produces a `Tx ConwayEra` of the expected shape; the rules.yaml parses; the expected.ttl is well-formed Turtle) run actively and gate the PR. `./gate.sh` therefore stays green on every commit of this PR.
- Q: Where do the URIs in `expected.ttl` come from while `cardano-knowledge-maps#53` is still landing in parallel?
  → A: Authoring of `expected.ttl` files is gated on a coordinated **kmaps#53 Phase A** release signal (prefix bindings + class URI declarations + property URI declarations; no axioms). The harness authors expected.ttl pinned to those exact URIs; no drift, no ten-fixture rework downstream. All non-Turtle work in this harness (builders, rules.yaml, blueprints, suite scaffolding) is vocab-independent and lands ahead of the signal.
- Q: What about `expected.txt` then?
  → A: `expected.txt` is a **verbatim copy of 044's expected text output** with a small whitespace canonicalisation (trailing whitespace stripped per line; one trailing newline). It is vocab-independent and lands alongside the builders. When #51 ships, applying the `cli-tree` view to the corresponding `expected.ttl` must produce text byte-equal to `expected.txt`.
- Q: Are the Tx values ledger-valid?
  → A: **No, they are illustrative.** The harness's job is structural fidelity (correct era, correct body field positions, correct witness-set layout, blueprint-decodable datum shape where required). Protocol-parameter validation, min-UTxO checks, and balance closure are out of scope. The downstream engine cares about field surface, not chain admission.

## User Scenarios & Testing *(mandatory)*

The harness is consumed by three kinds of reader, each with a different "win" condition:

1. The **engine implementer** for #47 (emitter MVP) and downstream waves. They take the harness as a static contract: implement the emitter, flip the pending Turtle goldens to active, watch them pass.
2. The **views implementer** for #51 (cli-tree SPARQL view). They take `expected.ttl` as input and `expected.txt` as the byte-for-byte target.
3. The **design reviewer** of any engine PR. They read each fixture's `Tx.hs` + `rules.yaml` + `expected.ttl` + `expected.txt` side by side to understand the property being tested without running anything.

The harness's user stories are therefore the **ten fixtures themselves**, plus one platform story for the suite scaffolding that makes them runnable. Each fixture is independently testable: the builder compiles, the rules parse, the Turtle parses, the text is byte-equal to its 044 source. The 044 priorities (P1 for Amaru swap; P2 for the seven follow-ups; P3 for the governance proposal) carry over.

---

### User Story 1 — Goldens suite scaffolding (Priority: P1)

`Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec` is registered in the `unit-tests` test-suite, runs from `nix develop --quiet -c just unit`, and is wired into `./gate.sh`. The suite iterates over a discoverable fixture registry (one entry per 044 story id), and for each fixture produces three Hspec items: a structural shape check (active), a Turtle byte-equivalence check (pending on #47), and a text byte-equivalence check (pending on #51).

**Why this priority**: P1 because every downstream item depends on this scaffolding being in place. Without it, the ten fixtures are inert files; with it, every commit on the engine and views side has an automatic verification path.

**Independent Test**: Run `nix develop --quiet -c just unit`. The new spec module is listed in the test run; structural-shape items pass; Turtle and text items are reported as `pending` with a recognisable `"awaits #47 emitter"` / `"awaits #51 cli-tree view"` message. `./gate.sh` runs green at HEAD.

**Acceptance Scenarios**:

1. **Given** the harness PR is checked out and the empty fixture registry, **When** `./gate.sh` runs, **Then** the `unit-tests` test-suite imports and runs `RewriteRedesignGoldenSpec` and `gate.sh` exits 0.
2. **Given** a fixture registered for one 044 story, **When** the unit suite runs, **Then** Hspec reports three items for that story: one active structural-shape check that passes, and two `pending` items naming the upstream tickets they await.
3. **Given** the goldens suite is wired, **When** a future commit replaces a `pending` marker with an active `it` block, **Then** the wiring requires only one import + one expression change — no fixture file rework, no test-suite re-registration.

---

### User Story 2 — Amaru treasury swap settled (Priority: P1) — corresponds to 044 Story 1

**Fixture id**: `01-amaru-treasury-swap`.

The fixture builds a Conway transaction that spends 33 Amaru-treasury `SwapOrder` UTxOs via the `amaru.swap.v2` script. Each input's datum carries a `recipient: Credential` field whose value is the `amaru-treasury.network_compliance` script hash. Settlement produces 95 USDM returned to the treasury per the recipient plus a small ADA change output to `amaru.network-wallet`. Collateral is taken from the same network wallet. A blueprint for `amaru.swap.v2` (the harness ships `blueprints/swap-v2-datum.cip57.json`) decodes the datum into a typed AST exposing the `recipient` field by name.

**Why this priority**: P1 because this is the load-bearing fixture — it exercises entity cross-leaf identity (treasury name at the output address AND inside every input's blueprint-decoded datum recipient), blueprint decode (`SwapOrder.recipient`), asset entity rendering (`usdm: 95`), nested collapse with `view: omit` (one bucket, no 33 redundant trees), and the #43 fix (`resolved.address` pinned in `required:` and the rename still fires).

**Independent Test**: The fixture's `Tx.hs` compiles, builds a `Tx ConwayEra` with the expected body shape (33 inputs, 2 outputs, blueprint script witness, 1 collateral input, the right witness set). `rules.yaml` round-trips through `parseRewriteRulesYaml`. `expected.ttl` (post-signal) parses as well-formed Turtle. `expected.txt` is byte-equal to the 044 Story 1 expected output under the documented whitespace canon.

**Acceptance Scenarios**:

1. **Given** `test/fixtures/rewrite-redesign/01-amaru-treasury-swap/Tx.hs`, **When** the goldens-suite structural check runs, **Then** the built `Tx ConwayEra` has era `ConwayEra`, 33 inputs, 2 outputs, 1 collateral input, a Plutus script witness for `amaru.swap.v2`, and each input's datum decodes (post-signal) against `blueprints/swap-v2-datum.cip57.json`.
2. **Given** `rules.yaml` declares the five entities (`amaru-treasury.network_compliance`, `amaru.swap-order`, `amaru.swap.v2`, `amaru.network-wallet`, `usdm`), the swap-v2 blueprint reference, and the `SwapOrderInput` nested-collapse rule with `view: omit`, **When** the file is parsed, **Then** parsing succeeds and the produced rule set matches the 044 Story 1 YAML byte-for-byte.
3. **Given** `expected.ttl` is authored post-kmaps#53-Phase-A signal, **When** the goldens-suite parses it, **Then** Turtle parsing succeeds, every URI resolves under the kmaps `cardano:` namespace, and the graph contains both the operator's entity triples and the per-input blueprint-decoded `recipient` triples.
4. **Given** `expected.txt` is the 044 Story 1 expected output, **When** the goldens-suite (post-#51) projects `expected.ttl` through `views/cli-tree.rq`, **Then** the projection equals `expected.txt` byte-for-byte under the documented whitespace canon.

---

### User Story 3 — Plain ADA transfer Alice → Bob (Priority: P2) — corresponds to 044 Story 2

**Fixture id**: `02-alice-bob-ada`.

One input from Alice; one output paying 10 ADA to Bob; one change output back to Alice; no scripts, no datums, no certificates, no withdrawals. `rules.yaml` declares Alice and Bob as `from-address` entities. The expected output is the baseline two-name rendering.

**Why this priority**: P2 baseline. Proves entity-centric rename for the simplest case (`PaymentKey` role); no blueprint, no collapse, no compound identifiers. If this fixture fails the whole engine is broken.

**Independent Test**: Build, parse, well-formed Turtle, byte-equal text. No blueprint required.

**Acceptance Scenarios**:

1. **Given** the Tx, **When** the structural check runs, **Then** the tx has 1 input, 2 outputs, no certs, no withdrawals, no scripts, era `ConwayEra`.
2. **Given** the rules.yaml + future emitter, **When** the Turtle golden runs, **Then** every address leaf appears as its entity name in the projection; no leaf renders verbatim in `expected.txt`.

---

### User Story 4 — Multi-asset transfer with two declared assets (Priority: P2) — corresponds to 044 Story 3

**Fixture id**: `03-multi-asset-transfer`.

One input from Alice; one output to Bob carrying `(50 ADA, 100 USDM, 1 000 000 MEME)`; one change output back to Alice. Two asset entities declared: USDM and MEME under different policies.

**Why this priority**: P2. Demonstrates the `AssetClass` role class — one entity per `(policy, name)` compound key. Closes 044 follow-ups #37, #38 once the engine catches up.

**Independent Test**: Build, parse, Turtle well-formed, text byte-equal.

**Acceptance Scenarios**:

1. **Given** the tx and the two asset entities, **When** the goldens project, **Then** every `(policy, name)` multi-asset key in the projection appears as the entity name (`usdm`, `meme`); the policy and name leaves do not render verbatim anywhere.

---

### User Story 5 — Plutus mint where the policy hash is also a payment-script witness (Priority: P2) — corresponds to 044 Story 4

**Fixture id**: `04-mint-spend-script-overlap`.

A treasury tx that mints 1000 USDM (under the USDM policy) AND spends a UTxO locked by the same script hash being used as a spending validator. The same 28-byte hash appears as `Policy` role in the mint field and `PaymentScript` role in the input's address and witness set's `scripts` field. The `usdm-control` entity declares `keys: [PaymentScript, Policy]` with one bytes value.

**Why this priority**: P2. Demonstrates one entity carrying two role classes for the same bytes; both leaves hit the same entity via different role-class indices. Closes the script-vs-asset-policy overlap concern in 044 follow-up #37.

**Independent Test**: Build, parse, Turtle well-formed, text byte-equal.

**Acceptance Scenarios**:

1. **Given** the mint+spend tx, **When** the goldens project, **Then** the mint field renders as `usdm-control: { usdm: +1000 }` and the witness set's script entry renders as `usdm-control`. Both leaves hit the same entity via different role classes.

---

### User Story 6 — Stake reward withdrawal from a script-controlled stake account (Priority: P2) — corresponds to 044 Story 5

**Fixture id**: `05-withdrawal-script-stake`.

Alice pays the fee; the withdrawal field claims 50 ADA from a stake account whose stake credential is the `amaru-treasury` stake script. The entity loader extracts the stake credential from the treasury's `from-address` (`StakeScript` half).

**Why this priority**: P2. Closes 044 follow-up #34. Demonstrates that `from-address` sugar extracts both payment and stake halves, and that the stake credential reaches the `withdrawals` map key via the right role-class index.

**Acceptance Scenarios**:

1. **Given** the withdrawal tx + entity declarations, **When** the goldens project, **Then** the withdrawals map key appears as `amaru-treasury.network_compliance`, not a `stake1...` bech32 string.

---

### User Story 7 — Stake pool delegation (Priority: P2) — corresponds to 044 Story 6

**Fixture id**: `06-stake-pool-delegation`.

Alice delegates her stake to a known pool. The body carries a `StakeDelegation` certificate referencing the pool's key hash.

**Why this priority**: P2. Closes 044 follow-up #35. Demonstrates `PoolId` role class via `pool: <bech32>` loader sugar AND cross-leaf identity between an address-derived stake credential and a cert's `stake-cred` field.

**Acceptance Scenarios**:

1. **Given** the delegation cert tx, **When** the goldens project, **Then** the pool leaf appears as `iog-pool-1` and the stake-cred leaf appears as `alice`.

---

### User Story 8 — Vote delegation to a DRep (Priority: P2) — corresponds to 044 Story 7

**Fixture id**: `07-vote-delegation`.

Alice delegates her voting power to a DRep operated by the Cardano Foundation; body carries a `VoteDelegation` certificate referencing the DRep credential. A sibling micro-fixture delegates to `AlwaysAbstain` for the verbatim-variant case.

**Why this priority**: P2. Closes 044 follow-up #36. Demonstrates `DRepKey` / `DRepScript` role discrimination by CIP-129 prefix AND that the variant constructors (`AlwaysAbstain`, `AlwaysNoConfidence`) render verbatim — no rename attempted.

**Acceptance Scenarios**:

1. **Given** the vote-delegation tx, **When** the goldens project, **Then** the drep leaf appears as `cardano-foundation-drep`.
2. **Given** the sibling tx delegating to `AlwaysAbstain`, **When** the goldens project, **Then** the drep leaf appears verbatim as `AlwaysAbstain`.

---

### User Story 9 — Contingency disburse (the #43 reproducer) (Priority: P2) — corresponds to 044 Story 8

**Fixture id**: `08-contingency-disburse`.

Two inputs from the contingency self-script carry the disbursement funds; one collateral input from a user wallet; one output disburses 100 ADA to a recipient. The collapse bucket pins `resolved.address` in `required:` — the #43 reproducer trigger under the old design. The 045 pipeline must render the address as the entity name despite the pin.

**Why this priority**: P2. Closes 044 follow-up #43 directly. Demonstrates that collapse and rename are orthogonal in the redesign: the typed-leaf walker descends into the matched subtree and the rename fires even when the path is pinned in `required:`.

**Acceptance Scenarios**:

1. **Given** the contingency-disburse tx with the YAML above, **When** the goldens project, **Then** the collapse bucket's `resolved.address` slot shows `amaru-treasury.contingency.account` and no `{"bytes":"…"}` form appears anywhere in the output.
2. **Given** a sibling fixture variant where `resolved.address` is removed from `required:`, **When** the goldens project, **Then** the output is structurally similar but the address rendering is identical. Cross-validates orthogonality.

---

### User Story 10 — MPFS facts-request with chunked outputs (Priority: P2) — corresponds to 044 Story 9

**Fixture id**: `09-mpfs-facts-request`.

An MPFS facts-request tx places 10 copies of the same fact-datum into outputs to the MPFS oracle script address. Each output carries an inline datum of the same shape with per-output variable slots. One change output returns to the operator wallet. A blueprint for the MPFS oracle script (the harness ships `blueprints/mpfs-fact.cip57.json`) decodes the datum into a typed AST with a named `requester` field.

**Why this priority**: P2. Closes 044 follow-up #40 (the `view: omit` mode) and cross-validates blueprint-decoded datum rename in a second context independent of Story 1.

**Acceptance Scenarios**:

1. **Given** the MPFS facts-request tx and the rules YAML, **When** the goldens project, **Then** the outputs section shows exactly one `FactOutput × 10` bucket and no per-output subtree appears below it.

---

### User Story 11 — Governance treasury withdrawal proposal (Priority: P3) — corresponds to 044 Story 10

**Fixture id**: `10-governance-treasury-withdrawal`.

An operator submits a Conway governance `ProposalProcedure` of variety `TreasuryWithdrawals` requesting that the chain treasury pay 50 000 ADA to a Cardano Foundation operations stake address. The tx carries the proposal in `body.proposalProcedures` and the proposal deposit input + change.

**Why this priority**: P3. Demonstrates that the governance leaf surface (proposal procedures' return address, treasury-withdrawal target) is served by the same entity index — no governance-specific rename kind is needed.

**Acceptance Scenarios**:

1. **Given** the proposal tx, **When** the goldens project, **Then** `returnAddr` and the `TreasuryWithdrawals` target appear as entity names; no raw bech32 surfaces in the proposal subtree.

---

### Edge Cases

- **Whitespace canon between `expected.txt` and a future SPARQL projection**: trailing whitespace stripped per line; exactly one final newline; no tab characters. Documented inline in `expected.txt` headers if needed. The future SPARQL `cli-tree` view must produce output respecting the same canon — that is the contract `expected.txt` locks.
- **`expected.ttl` authored before kmaps#53 Phase A signal**: forbidden. The harness's URI shapes are pinned to whatever kmaps#53 publishes; authoring earlier creates drift the epic orchestrator explicitly excluded. Tasks for `expected.ttl` authoring are blocked on the release signal.
- **Blueprint files (stories 1 and 9) are not full production blueprints**: they are hand-authored, minimal CIP-57 documents that expose only the fields the corresponding rules reference (`recipient` for swap-v2; `requester` for mpfs-fact). Other fields the production blueprint would carry are omitted.
- **Hspec `pending` markers and CI green**: pending items are recorded by Hspec but never fail. `./gate.sh` exits 0 even when every Turtle and text item is pending. The structural shape items always run actively.
- **A future contributor adds a fixture but forgets the blueprint reference**: the structural check fails because the datum-decode step pre-checks the blueprint file's existence for stories whose rules.yaml declares one.
- **A fixture's `Tx.hs` is not bisect-safe — e.g., it references a builder API that the harness commit hasn't introduced yet**: rejected at PR review; each fixture lands as one bisect-safe slice carrying its own builder helpers.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: For each of the ten 044 user stories, the harness MUST ship a `Tx.hs` Haskell module under `test/fixtures/rewrite-redesign/<story-id>/` whose top-level export builds a `Tx ConwayEra` value matching the story's "What's in the tx" description (body field positions, witness-set layout, blueprint-decodable datum shape where required).
- **FR-002**: Each `Tx.hs` MUST be small and readable, favouring declarative `mkTx { ... }` record construction over imperative builder chains. A reviewer must be able to read the file and reconstruct the story narrative without running anything. The harness ships shared builder helpers in `test/fixtures/rewrite-redesign/Helpers.hs` (or equivalent) to keep each `Tx.hs` short.
- **FR-003**: Each fixture directory MUST contain a `rules.yaml` carrying the verbatim YAML from the corresponding 044 user story. Round-trip through `parseRewriteRulesYaml` MUST succeed.
- **FR-004**: Each fixture directory MUST contain an `expected.ttl` Turtle file describing the graph the future emitter (#47) is expected to produce for that tx + rules pair, using the vocabulary terms published by `cardano-knowledge-maps#53` Phase A. `expected.ttl` is normative; the engine matches it byte-for-byte. Authoring `expected.ttl` is gated on the kmaps#53 Phase A release signal — tasks for `expected.ttl` are explicitly blocked until that signal arrives.
- **FR-005**: Each fixture directory MUST contain an `expected.txt` file equal to 044's expected rendered output for the corresponding story byte-for-byte, under the whitespace canon (trailing whitespace stripped per line; exactly one final newline; no tabs). `expected.txt` is the byte-equivalence target the future `cli-tree` SPARQL view (#51) recovers from `expected.ttl`. `expected.txt` is vocab-independent and lands ahead of the kmaps#53 signal.
- **FR-006**: The harness MUST ship two CIP-57 blueprint files under `test/fixtures/rewrite-redesign/blueprints/`:
  - `swap-v2-datum.cip57.json` for Story 1 (`amaru.swap.v2`).
  - `mpfs-fact.cip57.json` for Story 9 (MPFS oracle).
  Each blueprint MUST be minimal and structurally-valid CIP-57, exposing exactly the field(s) the corresponding `rules.yaml` references (`recipient` / `requester`).
- **FR-007**: A new unit-tests module `Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec` MUST be wired into `test/unit-main.hs` and into the cabal `unit-tests` test-suite's `other-modules`. The suite MUST be discoverable and runnable from `nix develop --quiet -c just unit`.
- **FR-008**: For each fixture, `RewriteRedesignGoldenSpec` MUST register a `describe "<story-id>"` block with three Hspec items:
  - **Active**: "produces a Tx ConwayEra of expected shape" — runs the builder, asserts era + presence of required body fields + witness-set layout. Always runs; passes on this PR.
  - **Pending until #47**: "Turtle byte-equivalence" — once `expected.ttl` exists and the emitter ships, runs the emitter on the Tx + rules and asserts byte-equality. Until then, marked `pendingWith "awaits #47 emitter MVP"`.
  - **Pending until #51**: "Text byte-equivalence via cli-tree SPARQL view" — once `expected.ttl` and the cli-tree view both exist, projects the Turtle through the view and asserts byte-equality against `expected.txt`. Until then, marked `pendingWith "awaits #51 cli-tree SPARQL view"`.
- **FR-009**: `./gate.sh` MUST be extended to ensure `RewriteRedesignGoldenSpec` runs as part of `just unit`. No new gate step is added; the unit-tests invocation already in `gate.sh` MUST be sufficient once the spec module is wired into the test-suite. The extension is a documentation-only update of the gate's own header if any change is needed.
- **FR-010**: The harness MUST NOT introduce a new emitter or SPARQL view runtime. Its sole responsibility is to ship fixture artifacts and the goldens-spec scaffolding. The future emitter is #47's responsibility; the future view runner is #51's responsibility.
- **FR-011**: Each fixture MUST be deliverable as a single bisect-safe commit: `Tx.hs` + `rules.yaml` + `expected.txt` + (when authored, `expected.ttl`) + the new `describe` block in `RewriteRedesignGoldenSpec` + any blueprint file the fixture references, all in one commit, with `./gate.sh` green at HEAD.
- **FR-012**: The shared builder helpers MUST expose at minimum the following Conway primitives: `mkTx :: TxBody ConwayEra -> TxWitnesses ConwayEra -> Tx ConwayEra`; smart constructors for inputs / outputs / withdrawals / certs / proposal procedures; helpers for inline datums and reference-script outputs; an `Addresses` module of canonical test bech32 strings (alice, bob, treasury, network-wallet, contingency, recipient, operator, mpfs.oracle, foundation.ops). The intent is that each fixture's `Tx.hs` is a record literal with no inline byte-literal noise.
- **FR-013**: The fixture registry MUST be discoverable from `RewriteRedesignGoldenSpec` — a single list of `(StoryId, Builder, FixturePaths)` records — so future fixtures land by appending one entry to the registry plus one new directory under `test/fixtures/rewrite-redesign/`, no Hspec wiring per fixture.

### Key Entities

- **Fixture**: One 044 user-story-worth of harness artifacts. Identified by a story id (`01-amaru-treasury-swap`, …, `10-governance-treasury-withdrawal`). Carries: a Haskell builder producing a `Tx ConwayEra`; an operator rules YAML; an expected Turtle graph (normative for the future emitter); an expected text rendering (normative for the future SPARQL view's byte-equivalence with 044); optionally a blueprint file.
- **Builder**: A pure top-level function `tx :: Tx ConwayEra` in a fixture's `Tx.hs`. Produces a structurally-correct Conway transaction; values are illustrative.
- **Blueprint** (CIP-57): A minimal hand-authored JSON file describing the shape of a datum or redeemer used by a fixture's script. Two blueprints in this harness: `swap-v2-datum`, `mpfs-fact`.
- **Goldens spec**: The Hspec module `Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec`. Iterates the fixture registry and produces three Hspec items per fixture (one active, two pending). Wired into `unit-tests`.
- **Fixture registry**: A single list inside the goldens spec naming the ten story ids and pointing at each fixture's builder + on-disk paths. Adding a fixture appends one record.
- **Whitespace canon**: The rule by which `expected.txt` (and any future SPARQL projection that targets it) is compared: trailing whitespace stripped per line, exactly one final newline, no tab characters.
- **kmaps#53 Phase A release signal**: An external coordination event from the `cardano-knowledge-maps` worker indicating that prefix bindings + class URI declarations + property URI declarations have been pushed and pinned. The `expected.ttl` authoring tasks are explicitly blocked on this signal arriving; all other harness tasks are vocab-independent and land ahead of it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All ten fixture directories exist on disk under `test/fixtures/rewrite-redesign/` with at minimum `Tx.hs`, `rules.yaml`, and `expected.txt`. Two of them (stories 1 and 9) additionally reference a blueprint under `blueprints/`. `expected.ttl` joins each directory after the kmaps#53 Phase A signal lands.
- **SC-002**: All ten builders compile and produce a `Tx ConwayEra` value whose era is `ConwayEra` and whose body-field counts match the 044 story description (inputs, outputs, certificates, withdrawals, proposal procedures, mint, collateral as applicable). Verified by the active "produces a Tx of expected shape" Hspec item per fixture.
- **SC-003**: All ten `rules.yaml` files parse via `parseRewriteRulesYaml` without error. Verified inside the goldens-suite active item.
- **SC-004**: All ten `expected.txt` files equal the 044 spec's expected text output for the corresponding story byte-for-byte under the whitespace canon. Verified by a static byte-level check against vendored copies of the 044 expected strings.
- **SC-005**: All ten `expected.ttl` files (post-signal) parse as well-formed Turtle, use only `cardano:` URIs published by kmaps#53 Phase A, and contain the operator-declared entity triples plus the per-input typed-leaf triples the future emitter is expected to mint. Verified by the active Turtle parse check.
- **SC-006**: `nix develop --quiet -c just unit` runs the full unit-tests suite including `RewriteRedesignGoldenSpec` to completion. Zero red items. Turtle and text items show as `pending "awaits #NN…"`. `./gate.sh` exits 0 at every commit of this PR.
- **SC-007**: Each fixture's `Tx.hs` is under ~80 lines (excluding imports / module header) and uses declarative record-construction style. A reviewer can read the file and recover the story narrative without running anything. Verified during PR review.
- **SC-008**: When #47 emitter MVP lands, the engine implementer can flip the "Turtle byte-equivalence" items from `pending` to `it` in `RewriteRedesignGoldenSpec` by adding one import + one expression per fixture (or one shared helper). No fixture file rework is required.
- **SC-009**: When #51 cli-tree view lands, the view author can flip the "Text byte-equivalence" items from `pending` to `it` by adding one import + one expression. No fixture file rework.
- **SC-010**: The eight 044 follow-up tickets (#34, #35, #36, #37, #38, #39, #40, #43) are reachable from the fixture set: each ticket maps to at least one fixture whose acceptance scenarios exercise the property. The mapping is recorded in this spec's User Story cross-references and in a per-fixture comment in `Tx.hs`.

## Assumptions

- **kmaps#53 Phase A lands during this PR's lifetime**: the harness epic explicitly coordinates this. The harness PR may merge before kmaps#53 Phase A if every `expected.ttl` task is explicitly carried over to a follow-up. The default assumption is that Phase A lands first, the orchestrator signals, and `expected.ttl` work proceeds before final merge.
- **The current `parseRewriteRulesYaml` accepts the 044 YAML extensions**: where it does not (the `entities:` list and the `blueprints:` section), this harness PR is allowed to extend the parser as part of a `feat(rewrite): extend rule YAML for 045 entity sugars` slice, gated on the structural fixture work landing first. The parser extension is additive — legacy `kind: address | script` documents must continue to parse identically.
- **Illustrative transaction values**: each fixture's tx is structurally-correct but not necessarily ledger-valid. Min-UTxO, value-conservation, fee bounds, protocol parameters, and witness-coverage are not enforced. Reviewers grade fixtures on the shape, not on whether the chain would admit the tx.
- **Blueprint format is CIP-57**: the two blueprints are CIP-57-shaped JSON. Minimum required CIP-57 structure: a `title`, a top-level schema with a `oneOf` covering at least one constructor, named fields with type references the engine needs (`Credential`, `PubKeyHash`). Full CIP-57 schema validation is not enforced — the engine must consume them, but the harness does not verify against a JSON schema.
- **`expected.txt` whitespace canon**: trailing whitespace stripped per line; one final newline; no tabs. Documented inside this spec, in the fixture-directory `README.md` if needed, and respected by any future SPARQL projection.
- **The downstream engine is responsible for whitespace-canonicalising its own output before comparison**, not the harness. The harness ships `expected.txt` in canon form; the engine matches.
- **Test-suite cabal build-deps grow modestly**: the harness needs `aeson`, `bytestring`, `text`, `containers`, `data-default`, `microlens`, `cardano-ledger-conway`, `cardano-ledger-core`, `cardano-ledger-mary`, `cardano-ledger-alonzo`, `cardano-ledger-api`, `cardano-ledger-shelley`, `cardano-slotting`, and `cardano-strict-containers` — all already in `unit-tests`. A Turtle parser dependency may be required for the well-formedness check; the project may use a thin internal parser shim rather than pulling in a heavyweight RDF library — Phase 0 of the plan decides.
- **The eight 044 follow-up tickets are not closed by this PR**: this harness is the contract anchor. The follow-up tickets are reviewed against the harness once #47 lands and the goldens flip green. Their closure / refinement is tracked in the engine PR's description, not here.
- **No regression of existing 032 goldens**: the harness must not change `Cardano.Tx.InspectSpec` or any other existing test outcome. The only test-suite delta is the addition of `RewriteRedesignGoldenSpec`.

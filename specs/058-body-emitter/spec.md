# Feature Specification: Body emitter — Conway tx + UTxO + rules → joint Turtle/JSON-LD

**Feature Branch**: `58-body-emitter`
**Created**: 2026-05-20
**Status**: Draft
**Input**: `Cardano.Tx.Graph.Emit` — walk a Conway transaction plus its resolved
UTxO set and the operator-entity overlay from `Cardano.Tx.Graph.Rules.Load`,
emit one triple per leaf using the `cardano:` Phase A vocab, and reconstitute
the joint RDF graph (entity overlay + body) for each of the 11
`test/fixtures/rewrite-redesign/<NN>/` fixtures. Wave 2 second lander of
epic #46, following the merged #48 rules loader.

## Background — why this is the next Wave-2 lander

The PR #56 / spec [`specs/047-emitter-mvp-deferred/spec.md`](../047-emitter-mvp-deferred/spec.md)
recorded that the originally-scoped #47 body emitter could not land cleanly
while the operator-entity overlay was absent from disk. #48 shipped that
overlay (PR #57, merged 2026-05-20). The path is now clear for the body
emitter to consume `(Tx, UTxO, EntityOverlay)` in one pass and reconstitute
the joint graph.

This PR's contract is one joint Turtle file per fixture, byte-equal to a
regenerated `expected.ttl` checked in by this same PR. The artisan
`expected.ttl` files merged in #45 are retained as reference documents in
git history but overwritten at HEAD — see Clarifications session 2026-05-20
below for the discovery that forced regeneration.

## Clarifications

### Session 2026-05-20

- Q: What does `EmitGoldenSpec` byte-diff the emitter output against?
  → A: A **regenerated** per-fixture `expected.ttl`, checked in by this PR.
    The artisan `expected.ttl` files merged in #45 are structurally
    incompatible with #48's `expected.entities.ttl` overlay output: the
    artisan files used hand-tuned camelCase bnode names (`_:aliceIdPayment`)
    where the loader emits deterministic snake_case (`_:alice_paymentKey`),
    and at least one artisan file (`01-amaru-treasury-swap`) declared
    incorrect identifier shapes (e.g. `_:treasuryComplianceStakeId` typed
    `StakeKey` with bytes `9100eb83...` where the loader emits
    `_:amaru_treasury_network_compliance_stakeScript` typed `StakeScript`
    with bytes `32201dc1...`). The new joint files = `expected.entities.ttl`
    (verbatim from #48) + body section (emitted from Tx + UTxO using #48's
    deterministic bnode names + ledger-authoritative bytesHex). The artisan
    files become reference documents readable from `git show
    HEAD~N:test/fixtures/.../expected.ttl`. **Source**: Q-001 →
    `/tmp/epic-046/tx-58/{questions,answers}/Q-001-emit-golden-target.md`.
- Q: How does the body emitter resolve a transaction's credentials against
    the rules-entity overlay?
  → A: Lookup table keyed on `(LeafType, bytesHex)`. For every credential
    encountered by `conwayDiffProjection`, the emitter computes the leaf
    type (`PaymentKey` / `PaymentScript` / `StakeKey` / `StakeScript` /
    etc.) and the 28-byte (or asset-class) hex payload, then probes the
    overlay's `[EntityDecl]` list. On match, the emitter references the
    entity's deterministic bnode name (`_:<entitySlug>_<roleSuffix>`); on
    miss, the emitter mints a raw-bytes-named blank node
    (`_:cred_<role>_<bytes12>` with a fixed-prefix slug — see FR-005 below).
- Q: Does the loader expose the entity list, or just the serialized overlay
    bytes?
  → A: Just the bytes today. The body emitter needs the in-memory
    `[EntityDecl]` list to build its lookup table; the loader has that data
    internally. This PR extends `RulesLoadResult` with `rulesEntities ::
    [EntityDecl]` (FR-010). The new field is opt-in for callers; existing
    `rulesOverlayTurtle` consumers are unaffected.
- Q: What's the emit ordering for non-shared leaves (multiple inputs, multiple
    outputs)?
  → A: Tx-positional. Inputs in `tx.body.inputs` order; outputs in
    `tx.body.outputs` order; certificates in `tx.body.certs` order. The
    operator-entity overlay (lines 5-N of the joint file) keeps its
    in-overlay-file order from #48's emitter. Determinism inside #58 is
    therefore inherited from the projection's traversal order plus the
    overlay's emit order (already pinned by #48's `RulesLoadGoldenSpec`).
- Q: What surface does `tx-graph` expose for the joint graph after this PR?
  → A: Three modes, dispatched by which flags are present:
    - `tx-graph --rules <file>` (back-compat with #48): overlay only on
      stdout; no `--tx` or `--utxo` required.
    - `tx-graph --tx <tx.cbor> --utxo <resolved.json> --rules <file>
      [--out <file>] [--format turtle|json-ld]`: joint graph (overlay
      + body) on stdout or `--out`.
    - `tx-graph --tx <tx.cbor> [--utxo …]` without `--rules`: body-only
      mode emitting raw-bytes-named bnodes for every credential (no
      overlay section). Useful for ad-hoc inspection.
- Q: How does this PR handle the four entity shapes that don't appear in
    fixture 02 (the simplest fixture)?
  → A: All nine leaf types pinned by #48's FR-013 are handled identically
    by the body emitter via the same `(LeafType, bytesHex)` lookup
    against the overlay. The body emitter does not need to know whether
    an entity was authored via `from-address`, `script`, `asset`,
    `keys+bytes`, `pool`, or `drep` — it sees only the resulting
    identifier in the loader's `[EntityDecl]` output. The acceptance
    contract is anchored on the 11 fixtures, which collectively exercise
    all nine leaf types (see #48 spec → Key Entities → Identifier).
- Q: Are the regenerated `expected.ttl` files committed file-by-file or
    in a single bulk commit?
  → A: The plan picks per-fixture slices to keep each commit bisect-safe
    (one regen broken = one fixture failing, not all 11). Concrete slice
    layout is decided in plan.md after the emitter scaffold + first
    fixture (02-alice-bob-ada, simplest) land.
- Q: The artisan `expected.ttl` files carry substantial narrative comments
    (story arcs, invariant explanations, cross-references — fixture 04 alone
    has 111 comment lines). Where does this design memory live after the
    regen drops it from the joint file?
  → A: A new per-fixture `NOTES.md` file (`test/fixtures/rewrite-redesign/<NN>/NOTES.md`)
    holds the narrative as markdown. The regenerated `expected.ttl` carries
    only machine-emitted comments (uniform section headers per research R4);
    `expected.txt` keeps its structured-YAML format (#51 cli-tree contract);
    `NOTES.md` is documentation-only with no test assertion against it.
    Each artifact stays single-purpose: byte-diff anchor (`expected.ttl`),
    structured fixture data (`expected.txt`), design narrative (`NOTES.md`).
    Migration lands in **T001a** as a single chore slice authoring 11 new
    files before any emitter code touches the fixtures (T002+). **Source**:
    Q-003 → `/tmp/epic-046/tx-58/{questions,answers}/Q-003-narrative-comment-migration.md`.

### Session 2026-05-20 (deferred to plan)

- Q: Which RDF serializer library (if any) handles JSON-LD output?
  → Deferred to plan.md research. Constraint per CLAUDE.md DSL stress-test
    policy: in-house serialization unless a one-shot library import is
    materially cleaner. JSON-LD has an established mapping from Turtle
    (subject grouping + `@context` for prefix declarations), so an
    in-house projection from the same triple stream is plausible.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator runs `tx-graph` and gets the joint graph (Priority: P1)

The operator has a Conway transaction CBOR, a resolved-UTxO JSON file (from
the n2c resolver), and a `rules.yaml`. They run

```bash
tx-graph --tx tx.cbor --utxo resolved.json --rules rules.yaml \
  --out graph.ttl --format turtle
```

and receive a Turtle file containing the operator-entity overlay (from
`Cardano.Tx.Graph.Rules.Load`) immediately followed by the transaction-body
section, with the body's credentials cross-referenced to the overlay's
entity-named blank nodes wherever a `(LeafType, bytesHex)` match exists, and
raw-bytes-named blank nodes otherwise. The Turtle parses with any compliant
RDF tool and the output is byte-identical to the regenerated
`expected.ttl` for that fixture.

**Why this priority**: P1 because every Wave-3 ticket (#49 reasoner, #51
SPARQL views) consumes the joint graph as input. Without the body emitter,
the epic acceptance (#46 SC-001..SC-005) is anchored on a future PR; with it,
all 11 fixtures have a verifiable joint artifact on disk for the rest of the
epic to compose on.

**Independent Test**: For each of the 11 rewrite-redesign fixtures, run

```bash
tx-graph --tx <fixture-driven-cbor> --utxo <fixture-driven-utxo> \
  --rules test/fixtures/rewrite-redesign/<NN>/rules.yaml > /tmp/out.ttl
diff /tmp/out.ttl test/fixtures/rewrite-redesign/<NN>/expected.ttl
```

All 11 byte-equal → P1 passes. The transaction CBOR + UTxO JSON sources
come from the fixture's existing TxBuild builder (under
`test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S<NN>_*.hs`),
serialized as part of the test harness — the executable accepts whatever
shape the harness materializes on disk.

**Acceptance Scenarios**:

1. **Given** `test/fixtures/rewrite-redesign/02-alice-bob-ada/{rules.yaml,
   <tx>, <utxo>}` (the simplest fixture: alice + bob, two outputs, no
   scripts/certs/mints), **When** the body emitter compiles + runs, **Then**
   the produced Turtle byte-equals the regenerated
   `02-alice-bob-ada/expected.ttl`. Every body-section bnode reference for
   alice's payment credential resolves to `_:alice_paymentKey` (the overlay
   bnode), not `_:cred_paymentkey_8bd03209...` (the raw-bytes fallback).
2. **Given** `01-amaru-treasury-swap/{rules.yaml, <tx>, <utxo>}` (the
   load-bearing P1 fixture: five entities, shared-identity case
   between `amaru.swap-order` and `amaru.swap.v2`, multi-output, mint),
   **When** the emitter runs, **Then** the produced Turtle byte-equals the
   regenerated `expected.ttl`; the cross-leaf-identity surface (the
   `amaru.swap.v2` script hash that also appears at body.outputs[0].address)
   is rendered as a single shared `_:amaru_swap_order_paymentScript`
   blank-node reference per the overlay's emit order.
3. **Given** all 11 fixtures, **When** `EmitGoldenSpec` runs under `nix
   develop --quiet -c just unit`, **Then** 11/11 byte-diff items pass and
   `./gate.sh` exits 0.

---

### User Story 2 — Repeated runs produce byte-identical output (Priority: P1)

The operator runs `tx-graph --tx ... --utxo ... --rules ...` twice in a row
on the same inputs and gets two byte-identical Turtle files. No timestamp,
random bnode prefix, or set-iteration nondeterminism leaks into the output.
This is the on-disk anchor for epic #46 SC-005 (byte-identical
reproducibility).

**Why this priority**: P1 because the epic SC depends on it and because
non-determinism in graph output is the trap that has bitten every other
in-house RDF emitter (Set/Map iteration order, HashSet-driven shuffling,
hash-derived bnode names that change run-to-run). The body emitter must be
deterministic by construction: ordered traversal of
`conwayDiffProjection`'s output, sorted credential lookup, no hashing of
PIDs/PRNGs.

**Independent Test**: A `ReproducibilitySpec` test that runs the emitter
twice on each of the 11 fixtures and asserts byte-equality of the two outputs.
Independent of the goldens: this test passes even if the goldens haven't
been regenerated yet.

**Acceptance Scenarios**:

1. **Given** any fixture, **When** the emitter runs twice, **Then** the two
   outputs are byte-equal.
2. **Given** the same Tx + UTxO but two different `rules.yaml` files
   (e.g., one declaring no entities, one declaring entities), **When** the
   emitter runs on each, **Then** each run is internally reproducible
   (no run-to-run drift) — but the two runs differ in their body section's
   bnode references (entity-named vs raw-bytes-named) per the overlay
   they each consume.

---

### User Story 3 — `--format json-ld` produces an equivalent graph (Priority: P2)

The operator passes `--format json-ld` and receives a JSON-LD document
serializing the same triple set as the Turtle output. The JSON-LD `@context`
declares the same prefixes as the Turtle `@prefix` header; subject grouping
preserves the entity-then-body structure. Round-tripping JSON-LD → Turtle
through any compliant RDF library yields the same triple set as the direct
Turtle output (set-equal, not necessarily byte-equal — JSON-LD has
serialization degrees of freedom).

**Why this priority**: P2 because JSON-LD is the secondary surface for
downstream consumers (web tooling, JSON-native indexers); Turtle is the
in-house format and the byte-diff contract anchor. The two surfaces must
serialize the same graph or the abstraction is broken.

**Independent Test**: A `JsonLdEquivalenceSpec` test that, for each fixture,
generates the JSON-LD output, parses it via the chosen JSON-LD library, and
asserts the parsed triple set equals the parsed triple set from the Turtle
output. No fixture-level byte-diff for JSON-LD this PR (JSON-LD canonical
form is RDF Dataset Normalization, c14n — out of scope).

**Acceptance Scenarios**:

1. **Given** any fixture, **When** the emitter runs with `--format turtle`
   and `--format json-ld`, **Then** parsing both outputs yields the same
   triple set.
2. **Given** an unrecognized `--format <value>`, **When** the emitter runs,
   **Then** it exits non-zero with a structured "unknown format" error on
   stderr.

---

### User Story 4 — Credentials not covered by rules emit raw-bytes-named bnodes (Priority: P2)

A Conway transaction includes a credential (payment, stake, script, drep,
pool) whose `(LeafType, bytesHex)` is **not** declared by any entity in the
rules-entity overlay. The emitter mints a raw-bytes-named blank node for
that credential (e.g. `_:cred_paymentkey_8bd03209d227956a`) instead of an
entity-named one. The naming scheme is deterministic and stable across
runs.

**Why this priority**: P2 because operator rule files are not expected to
cover every credential a real-world transaction touches; fall-through to
raw-bytes naming is the universal-coverage guarantee that lets the emitter
run against any Conway tx, not just fixture-shaped ones.

**Independent Test**: A fixture where `rules.yaml` declares only `:alice` but
the transaction also references bob's address (no `:bob` entity). The
emitter must emit bob's payment + stake credentials as `_:cred_paymentkey_...`
+ `_:cred_stakekey_...` blank nodes derived from bob's address bytes.

**Acceptance Scenarios**:

1. **Given** a Tx referencing a credential not covered by any entity,
   **When** the emitter runs, **Then** the credential is emitted with a
   raw-bytes-named bnode following the documented scheme (FR-005).
2. **Given** the same credential appearing under two roles (e.g. the same
   hash used as both `PaymentScript` and `StakeScript` for an enterprise
   address with a script stake credential), **When** the emitter runs,
   **Then** the two roles produce **distinct** bnodes
   (`_:cred_paymentscript_<bytes12>` vs `_:cred_stakescript_<bytes12>`) —
   the structural (role, bytes) key drives bnode identity, not bytes alone.
3. **Given** a credential covered by an entity in the overlay, **When** the
   emitter runs, **Then** the entity's bnode name is used and no raw-bytes
   bnode is minted for that credential.

---

### User Story 5 — Body emitter reuses `conwayDiffProjection` (Priority: P2)

The body emitter walks the transaction via `Cardano.Tx.Diff`'s
`conwayDiffProjection` rather than reimplementing leaf extraction. Each
projection leaf maps to one triple (or a small fixed cluster of triples for
container nodes like `Address`). Adding new leaf coverage to the emitter is
adding one case to a single dispatch function.

**Why this priority**: P2 because the constitution and CLAUDE.md DSL stress-
test policy both forbid duplicating tx-walking logic across modules. The
projection is the single source of truth for what counts as a leaf.

**Independent Test**: Static check (Haddock + a code-review checklist) that
the body emitter imports only `Cardano.Tx.Diff` for projection access and
does not call `Cardano.Ledger.*` directly for leaf navigation. The unit
suite indirectly covers this: a new ledger field landing in
`conwayDiffProjection` should produce an unhandled-case compile error in
the emitter (which lists projection constructors).

**Acceptance Scenarios**:

1. **Given** the emitter module compiles, **When** the source is inspected,
   **Then** every leaf-extraction call routes through
   `conwayDiffProjection`.
2. **Given** a hypothetical new projection variant added to
   `Cardano.Tx.Diff`, **When** the emitter compiles, **Then** it fails with
   a `-Wincomplete-patterns` error pointing at the unhandled variant
   (constitution Principle I — explicit pattern matching, no catch-alls).

---

### Edge Cases

- **Empty Tx body** (no inputs, no outputs, fee-only — synthetic, not a real
  Conway tx but trivially valid): emitter produces `_:tx a
  cardano:Transaction ; cardano:hasFee N .` with no `cardano:hasInput`
  / `cardano:hasOutput` triples. Overlay still emitted.
- **Tx with mint section but no asset entity in overlay**: mint triples use
  raw-bytes-named bnodes for the policy + asset name pair, following FR-005.
- **Withdrawal cert referencing a stake credential not in overlay**: same
  fallback to raw-bytes bnode.
- **Stake-pool delegation cert + `cardano:Entity` declaring a `PoolId`**:
  the cert's stake credential AND the pool ID both lookup against the
  overlay; both can be entity-named independently.
- **DRep vote with a script-DRep credential**: leaf type is `DRepScript`
  (one of #48's nine pinned types); lookup against the overlay works the
  same as any other credential.
- **UTxO file missing a reference an input needs**: structured error
  `UtxoMissing <txIn>`; executable exits non-zero, no partial Turtle
  emitted.
- **UTxO file present but contains a TxIn the tx doesn't reference**:
  silently ignored — the emitter walks the tx and pulls UTxO entries on
  demand, not the other way around.
- **`--utxo` flag absent but tx has inputs**: structured error
  `UtxoRequired <txInCount>`; executable exits non-zero. Body-only mode
  (no `--utxo`) is for tx skeletons that have no inputs (e.g., the
  governance-cert-only fixture, if any).
- **Same credential covered by two overlapping entities** (operator
  authored two entities sharing one `(LeafType, bytesHex)` pair — #48
  forbids same-file dup but allows it across files with a warning per
  US6): the overlay's `[EntityDecl]` list contains both, but only the
  first declaration owns the bnode (per #48's first-wins rule). The body
  emitter sees one bnode name per pair and uses it consistently.
- **Raw-bytes bnode collision** (extremely unlikely but real: two different
  credentials slug to the same `<bytes12>` prefix in FR-005's scheme):
  resolved by using a longer prefix in FR-005 (the minimum prefix length
  needed for collision-freeness across the 11 fixtures is determined
  empirically and pinned in plan.md research).
- **JSON-LD `@context` for an entity-named blank node**: the prefix
  declarations are the same as the Turtle output; blank nodes are
  serialized as JSON-LD `_:<id>` references (no `@id` URI).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module `Cardano.Tx.Graph.Emit` MUST expose a pure
  entry-point function consuming `(ConwayTx, ResolvedUTxO, [EntityDecl])`
  and returning a structured graph representation (in-memory triple set
  plus prefix declarations) usable by both the Turtle serializer and the
  JSON-LD serializer.
- **FR-002**: The body emitter MUST walk the transaction via
  `Cardano.Tx.Diff.conwayDiffProjection`. Direct calls into
  `Cardano.Ledger.*` from inside `Cardano.Tx.Graph.Emit` are forbidden
  except for type aliases already re-exported through `Cardano.Tx.Diff`.
- **FR-003**: For every projection leaf, the emitter MUST emit one triple
  (or a small fixed cluster for container shapes — `Address`, `Output`,
  `Input`) using the kmaps Phase A `cardano:` vocab IRIs published by
  `cardano-knowledge-maps#53`. The vocab terms used by the 11 fixtures
  are enumerated in `research.md` D1 (plan.md).
- **FR-004**: The emitter MUST resolve every credential's `(LeafType,
  bytesHex)` against the `[EntityDecl]` list. On match, the credential's
  bnode reference uses the entity's deterministic bnode name
  (`_:<entitySlug>_<roleSuffix>` per #48 FR-013). On miss, the credential
  is emitted as a raw-bytes-named bnode (FR-005).
- **FR-005**: Raw-bytes bnode naming MUST follow the deterministic scheme
  `_:cred_<rolePrefix>_<bytes-prefix>` where `<rolePrefix>` is the leaf
  type lowercased and `<bytes-prefix>` is the first N hex characters of
  `bytesHex` (N pinned in plan.md research D2, chosen as the minimum
  collision-free length across the 11 fixtures + a +4-char safety
  margin). The scheme MUST be deterministic and stable across runs.
- **FR-006**: The emitter MUST produce byte-identical output across
  repeated runs on the same input triple `(Tx, UTxO, [EntityDecl])`.
  Source of non-determinism (Set/Map iteration, ByteString hashing,
  filesystem `readDirectory`) MUST be ruled out by construction:
  deterministic traversal order, sorted lookup lists, no I/O during emit.
- **FR-007**: The emitter MUST produce two output formats:
  - `turtle` — canonical form: prefix declarations first
    (`cardano:`, `rdfs:`, fixture-local `:`), one entity group per blank
    line, identifiers indented two spaces, statement terminators on every
    non-blank/non-comment line, trailing newline. Same canonical-form
    rules as #48's overlay serializer.
  - `json-ld` — a JSON-LD document with `@context` declaring the same
    prefixes, subject-grouped triples, blank-node IDs preserved.
- **FR-008**: The `tx-graph` executable MUST accept the following flags
  alongside the existing `--rules`:
  - `--tx <file>` — Conway transaction CBOR path.
  - `--utxo <file>` — Resolved UTxO JSON path (same shape consumed by
    `Cardano.Tx.Diff.Resolver`).
  - `--out <file>` — Output file path. Defaults to stdout when absent.
  - `--format turtle|json-ld` — Output format. Defaults to `turtle`.
  The three modes (overlay-only, body-only, joint) are dispatched by
  which flags are present (Clarifications session 2026-05-20).
- **FR-009**: Every leaf URI in the emitter's output MUST trace to a
  `cardano:` vocab term or a `:` (fixture-local) instance URI. Internal
  helpers MUST NOT mint new top-level URIs without going through the
  vocab module (a single source-of-truth point of update if the kmaps
  vocab is later widened).
- **FR-010**: `Cardano.Tx.Graph.Rules.Load.RulesLoadResult` MUST gain a
  new field `rulesEntities :: [EntityDecl]` carrying the in-memory entity
  list (the data the loader already computes internally). Existing
  `rulesOverlayTurtle` consumers MUST be unaffected — record-update
  syntax + a new field is backwards-compatible at the type level. The
  existing `RulesLoadGoldenSpec` byte-diff acceptance from #48 MUST stay
  GREEN after the extension.
- **FR-011**: For each of the 11 `test/fixtures/rewrite-redesign/<NN>/`
  fixtures, the cross-PR contract MUST be: running the body emitter on
  `(<NN>/<tx>, <NN>/<utxo>, <NN>/rules.yaml)` produces output that
  byte-equals a **regenerated** `<NN>/expected.ttl`. The 11 regenerated
  files are checked in by this PR and replace the artisan files merged
  in #45.
- **FR-012**: The `tx-graph` executable MUST exit non-zero and write a
  structured error to stderr on any emitter failure (missing input file,
  malformed CBOR, UTxO mismatch, unknown format, etc.) — same diagnostic
  pattern as #48's `renderRulesLoadError`.
- **FR-013**: The body emitter MUST handle every leaf type pinned by #48's
  FR-013 (`PaymentKey`, `PaymentScript`, `StakeKey`, `StakeScript`,
  `AssetClass`, `Policy`, `PoolId`, `DRepKey`, `DRepScript`). Other
  ledger-level leaf shapes that may appear in future Conway extensions
  trigger a structured `UnsupportedLeafType <name>` error rather than a
  silent skip.
- **FR-014**: Every exported function and type in the new
  `Cardano.Tx.Graph.Emit*` modules added by this PR MUST carry a Haddock
  docstring (constitution Principle IV — strict for new code in this PR;
  anchored by the gate's `cabal haddock` step). The same convention #48
  used.
- **FR-015**: The body emitter MUST default to fully offline behaviour per
  the constitution's Default-Offline Semantics: no network calls during
  emit, no fetching of remote IRIs. Same baseline as #48's loader.

### Key Entities

- **TxGraphEmit**: The pure function `(ConwayTx, ResolvedUTxO,
  [EntityDecl]) → Either EmitError EmittedGraph` that drives the
  projection walk and assembles the triple set.
- **EmittedGraph**: The in-memory triple set, prefix declarations, and
  emit-order metadata. Consumed by both the Turtle and the JSON-LD
  serializer.
- **CredentialKey**: The pair `(LeafType, bytesHex)` used as a lookup key
  against `[EntityDecl]`. Drives the entity-vs-raw-bytes bnode decision.
- **BnodeName**: An entity-named (`_:<entitySlug>_<roleSuffix>`) or
  raw-bytes-named (`_:cred_<rolePrefix>_<bytes-prefix>`) blank-node
  identifier. The same `BnodeName` for the same `CredentialKey` across
  all leaf references in one emit run.
- **EmitError**: Structured failure variants — `UtxoRequired <count>`,
  `UtxoMissing <txIn>`, `MalformedTxCbor <file> <msg>`,
  `MalformedUtxoJson <file> <msg>`, `UnknownFormat <name>`,
  `UnsupportedLeafType <name>`.
- **EmitFormat**: `Turtle | JsonLd`. Pinned at the CLI parse and threaded
  through to the serializer dispatcher.
- **Design narrative (per-fixture `NOTES.md`)**: a non-code, non-test
  documentation artifact per fixture. Holds the story-arc text, invariant
  explanations, and cross-references that the artisan `expected.ttl` files
  merged in #45 carried as comment-lines. Migrated to markdown in T001a
  before any regen begins, keeping the three on-disk artifacts
  single-purpose: `expected.ttl` is the joint byte-diff anchor (machine
  output only), `expected.txt` is the #51 cli-tree structured-YAML
  contract, `NOTES.md` is the design narrative.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For each of the 11 `test/fixtures/rewrite-redesign/<NN>/`
  fixtures, `Cardano.Tx.Graph.Emit.emit (<NN>/<tx>, <NN>/<utxo>,
  <NN>/rules.yaml)` succeeds and produces output that byte-equals the
  regenerated `<NN>/expected.ttl` under `EmitGoldenSpec`.
- **SC-002**: `tx-graph --tx <NN>/<tx> --utxo <NN>/<utxo> --rules
  <NN>/rules.yaml --out /tmp/out.ttl && diff /tmp/out.ttl
  <NN>/expected.ttl` exits 0 for every fixture.
- **SC-003**: `tx-graph --tx … --utxo … --rules … --format json-ld`
  produces a JSON-LD document whose parsed triple set is set-equal to the
  parsed triple set of the Turtle output for every fixture.
- **SC-004**: Two back-to-back emitter runs on the same fixture inputs
  produce byte-equal output (anchors epic #46 SC-005,
  byte-identical-reproducibility).
- **SC-005**: Every URI in the emitter's output is either a `cardano:`
  vocab IRI (published by kmaps#53) or a `:` (fixture-local) instance
  URI. No leaked `_internal:` prefixes, no external-vocab cross-talk.
- **SC-006**: `./gate.sh` (build + unit + cabal-fmt + fourmolu + hlint +
  `cabal check` + `cabal haddock lib:cardano-tx-tools`) is green on
  every commit on this branch; CI mirrors it.
- **SC-007**: `cabal check` is clean — no warnings, no missing fields.
  Constitution-compliance baseline inherits from the #48 sweep (PvP upper
  bounds + `werror` cabal flag); no new dependencies are introduced by
  this PR.
- **SC-008**: The existing `RulesLoadGoldenSpec` (#48's 11/11 byte-diff)
  stays GREEN after the FR-010 loader-API extension lands. The extension
  is purely additive (new field on `RulesLoadResult`); existing callers
  remain on `rulesOverlayTurtle`.

## Assumptions

- The kmaps#53 Phase A vocab IRI
  `https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#`
  is pinned for the emitter's prefix declaration. (Merged 2026-05-19;
  inherited from #48.)
- The 11 rewrite-redesign fixtures' `rules.yaml` files are unchanged by
  this PR. Only `expected.ttl` files are regenerated.
- The fixture txbuild builders under
  `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S<NN>_*.hs`
  produce stable `ConwayTx` values across runs (asserted by the existing
  harness in #45). The emitter consumes whatever they materialize.
- No RDF Haskell library is pulled into the dependency closure. The
  emitter is authored as in-house text-level serialization — consistent
  with CLAUDE.md DSL stress-test policy and #48's precedent.
- `Cardano.Tx.Diff.conwayDiffProjection` is stable enough as an interface
  for `Cardano.Tx.Graph.Emit` to depend on it directly. If the projection
  grows new variants during this PR's life, the emitter's pattern match
  fails to compile (FR-006 + Principle I) and the slice landing the new
  variant covers the emitter case in the same commit.

## Out of Scope

- OWL 2 RL inference / EYE reasoner integration over the emitted graph
  — wave 3, ticket #49. The emitted joint graph is pre-reasoner; any
  `owl:sameAs` deductions land downstream.
- SPARQL views over the emitted graph — wave 3, ticket #51. The emitter
  produces the data; views project it back into operator-readable shapes.
- Blueprint / CIP-57 datum decoding — wave 3, ticket #50. Inline datums in
  outputs and redeemers in witness sets are emitted as raw CBOR-hex
  literals at this PR's surface; #50 swaps them for typed triples.
- Editing the existing `rules.yaml` or `expected.entities.ttl` files
  (the #48 contract is frozen). Only `expected.ttl` files change.
- Network resolution of any IRI — the constitution's Default-Offline
  baseline is inherited.
- Migration / consolidation of `tx-inspect` and `tx-diff` into the new
  surface — ticket #53.
- Migration docs + deprecation timeline + CHANGELOG — ticket #54 (a small
  CHANGELOG entry for this PR is in scope but the broader migration plan
  is not).

## Glossary

- **Joint graph**: The union of operator-entity overlay (from #48's
  loader) and transaction body (from this PR's emitter) — the file
  this PR contracts on as `expected.ttl`.
- **Design narrative (`NOTES.md`)**: Per-fixture markdown file holding
  the artisan story-arc text, invariant explanations, and ticket
  cross-references that the artisan `expected.ttl` carried as
  comment-lines. Authoring artifact only — no test assertion runs
  against it. Migration in T001a (Q-003 → A-003).
- **Body section**: The triples derived from a transaction's structural
  shape (inputs, outputs, certs, mints, withdrawals, votes, fees) plus
  the resolved UTxO entries they reference.
- **Operator-entity overlay**: The slice of the joint graph derived from
  the operator's `rules.yaml` — entity declarations + identifier blank
  nodes. Produced by #48; consumed verbatim by this PR.
- **Credential key**: The `(LeafType, bytesHex)` pair the emitter uses to
  decide between entity-named and raw-bytes-named bnodes.
- **Raw-bytes bnode**: A blank node minted from the credential's leaf type
  and a deterministic prefix of its `bytesHex`. Used when no entity in
  the overlay covers the credential.

## Followup (orchestrator-owned, not this PR)

- **#49** (reasoner): OWL 2 RL inference over the emitted joint graph.
  Closes any post-emit `owl:sameAs` deductions that this PR's emitter
  cannot produce by construction (e.g., cross-leaf identity for two
  entities sharing identical bytes under different role classes — those
  surface in the overlay via #48's first-declarant rule, but a reasoner
  is needed to materialize the `owl:sameAs` triples).
- **#50** (blueprint): CIP-57 datum schema decoding. Swaps the
  raw-CBOR-hex datum literals this PR emits for typed triples.
- **#51** (cli-tree views): SPARQL projections from the emitted joint
  graph back to the 044 text shape.
- **#52** (diff-as-view): RDF symmetric-difference mode using SPARQL.
- **Epic #46**: Update Wave-2 sequencing once this PR merges. Mark child 4
  done; Wave 3 (#49, #50, #51) unblocked.

## References

- Issue: lambdasistemi/cardano-tx-tools#58
- Epic: lambdasistemi/cardano-tx-tools#46
- Deferral context: [`specs/047-emitter-mvp-deferred/spec.md`](../047-emitter-mvp-deferred/spec.md)
- Rules loader (consumed): [`specs/048-rules-loader/spec.md`](../048-rules-loader/spec.md)
- Harness: [`specs/033-rewrite-redesign-harness/spec.md`](../033-rewrite-redesign-harness/spec.md)
- In-house Turtle predicate decision (precedent):
  [`specs/033-rewrite-redesign-harness/research.md` D5](../033-rewrite-redesign-harness/research.md)
- Vocab: lambdasistemi/cardano-knowledge-maps#53 (merged 2026-05-19)
- 11 fixtures: `test/fixtures/rewrite-redesign/{01..11}-*/`
- Q-001 (regen-vs-carve-vs-defer arbitration):
  `/tmp/epic-046/tx-58/{questions,answers}/Q-001-emit-golden-target.md`

# Feature Specification: Transaction-to-RDF emitter with OWL-driven entity inference

**Feature Branch**: `045-graph-emit-pivot`
**Created**: 2026-05-19
**Status**: Draft
**Supersedes**: `specs/044-rewrite-rules-redesign/` (the entity-centric ADT + text-renderer plan). Spec 044's ten user stories (the Amaru swap, the multi-asset transfer, the contingency-disburse #43 reproducer, the MPFS facts request, etc.) carry over as the **structural acceptance contract**: every "expected rendered output" in 044 is preserved here as a SPARQL view query whose projection over the new pipeline's output graph produces byte-equivalent text.

**Input**: Re-target the rewrite-rules engine from "in-memory ADT + text renderer" to **"Conway tx → RDF graph"**. The engine becomes a triple emitter under the existing `cardano-knowledge-maps` `cardano:` namespace. Operator rules become Turtle files (with optional YAML sugar). Cross-leaf identity is deduced by an OWL 2 RL reasoner via `owl:sameAs` propagation rather than engineered at render time. Reviewer-facing views (CLI tree, browser, narrative summary, asset-flow, per-entity reverse-index) are SPARQL `SELECT` / `CONSTRUCT` queries over the unified graph. The engine has one job (emit triples); views compose without engine changes.

## Background — why supersede 044

Spec 044's plan delivers an entity-centric ADT + a typed-leaf walker + a text renderer. While drafting it, two insights reshaped the target:

1. **"Views for free" via RDF.** Once the tx is a graph of typed triples, the CLI tree, browser inspector, narrative summary, asset-flow diagram, and per-entity reverse-index are different SPARQL queries over the *same* graph. The engine doesn't have views; the engine has a graph; views are derived. Adding a new view is writing a query, not editing the engine.

2. **Cross-leaf identity is `owl:sameAs`.** 044 engineered cross-leaf identity as a typed-leaf walker that dispatches through an `(role-class, bytes) → entity` map. RDF gives it for free: two triples about the same URI *are* the same entity by definition, and the reasoner unifies hash-matching credentials into entity URIs via `owl:sameAs`. The Wireshark-style name-resolution chain disappears as a concept.

3. **Vocabulary is now public API.** Once we emit RDF, class names (`cardano:Transaction`, `cardano:Input`) and property names (`cardano:hasInput`, `cardano:atAddress`) become public API the moment any third tool binds to them. Getting `cardano:hasInput` wrong is a versioning event. Nomenclature work is no longer a doc polish — it's load-bearing design.

4. **`cardano-knowledge-maps` already has the ontology infrastructure.** A mature multi-file Turtle ontology under the `cardano:` namespace (`https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#`) already exists, using `prov:` / `skos:` / `org:` / `time:` / `foaf:` / `dcterms:` cleanly. Extending it for transactions is the natural home; building a parallel ontology in `cardano-tx-tools` would fragment the vocabulary surface.

The combination is more ambitious than 044 but the payoff is correspondingly larger: composability with the existing knowledge-graph stack, free integration with downstream visualisation (graph-browser, governance graphs), declarative operator rules, and a candidate Cardano vocabulary CIP.

## Clarifications

### Session 2026-05-19

- Q: What is the engine's output artifact?
  → A: An **RDF graph**. Default serialization is Turtle (human-readable, diffable); JSON-LD is a secondary output for browser consumers. The CLI text output 044 specified is preserved as a SPARQL `CONSTRUCT` view that produces it from the graph — text becomes a derived projection, not an engine primitive.
- Q: Where does the ontology live?
  → A: In `cardano-knowledge-maps` as a new file `data/rdf/transactions.ttl` (or extension to existing `cardano.ontology.ttl` / `smart-contracts.ttl`), under the established `cardano:` namespace. `cardano-tx-tools` imports the ontology by fetching the Turtle file at build time (vendored via a Nix input for reproducibility) and generating Haskell constants for the term URIs.
- Q: What is the URI namespace?
  → A: The existing `cardano:` prefix `https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#`, controlled by lambdasistemi. URI migration to a Cardano-Foundation-controlled prefix is reserved for if/when the vocabulary is submitted as a CIP; the migration is mechanical (one prefix constant swap in the emitter) provided every URI is routed through a `Namespace` constant from day one.
- Q: What is the form of operator rules?
  → A: **Turtle triples** are the canonical form. Operators may also author **YAML** (the legacy 044 grammar plus the new `entities:` form) that the loader compiles to Turtle at load time. The internal representation is RDF; YAML is sugar for less-RDF-fluent operators. Both forms compose monoidally with `owl:imports` (Turtle) or `imports:` (YAML).
- Q: What reasoner does the pipeline use?
  → A: **EYE** ([eyereasoner/eye](https://github.com/eyereasoner/eye)), shelled out via subprocess. Justification: small (single binary, bundleable via Nix), fast, mature (used by W3C / DBpedia), declarative N3 rule support that extends OWL 2 RL, no JVM dependency, aligned with the "rules are triples" framing. Alternatives considered: Apache Jena (heavyweight JVM), hand-rolled subset (limits future expressivity).
- Q: How is blueprint decode integrated?
  → A: **Phase A**: keep the existing `Cardano.Tx.Blueprint.decodeBlueprintData` imperative decode; the emitter walks the decoded AST and emits typed triples directly. **Phase C**: introduce SHACL shapes that operators can author to extend decode without recompiling the engine (a constructor-0-with-two-fields-of-type-X is a SHACL pattern that, on match, emits typed triples). Phase A ships in this spec; Phase C is a follow-up.
- Q: How does this spec relate to 044's ten user stories?
  → A: Each of 044's ten stories is **preserved structurally** — same "what's in the tx", same "rules YAML" (or its Turtle equivalent), same cross-leaf-identity property to be demonstrated. The artifact changes: 044's "expected rendered output" (text tree) becomes "expected graph (`expected.ttl`) + SPARQL CONSTRUCT view query that derives the same text". The harness ticket [#45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45) is re-aimed accordingly.

## User Scenarios & Testing *(mandatory)*

The four user stories below cover the pipeline shape, the OWL deduction property, the multi-view payoff, and the operator-authoring story. They are independently testable. **The ten 044 transactions are referenced as the structural acceptance contract**: each must produce a graph whose default CLI-tree SPARQL view is byte-equivalent to 044's expected text output.

---

### User Story 1 — Operator emits a tx graph and queries it (Priority: P1)

A treasury reviewer has a Conway tx CBOR + a resolved UTxO set + a `rules.ttl` declaring two entities (a treasury, a counterparty). They run:

```bash
tx-graph tx.cbor --utxo resolved.json --rules rules.ttl --out graph.ttl
sparql query views/cli-tree.rq --graph graph.ttl
```

The first command emits a Turtle graph of triples encoding the tx (`tx:abc cardano:hasInput tx:def#0`, `tx:def#0 cardano:atAddress <bech32>`, `<bech32> cardano:hasPaymentCredential _:cred1`, `_:cred1 cardano:bytesHex "32201dc1…"`) plus the operator's rule triples. The second command runs a packaged SPARQL view query (`cli-tree.rq`) that walks the graph and emits the same text the 044 `tx-inspect` would have rendered.

**Why this priority**: P1 because this is the pipeline's load-bearing user-facing flow. Every other story builds on it.

**Independent Test**: Run the two commands on a checked-in tx + rules pair; assert the SPARQL projection equals the 044-style expected text.

**Acceptance Scenarios**:

1. **Given** a Conway tx CBOR + resolved UTxO + a minimal `rules.ttl` declaring one entity, **When** the emitter runs, **Then** the output `graph.ttl` contains the expected base triples + the operator's entity triples + the inferred `rdfs:label` for matching credentials.
2. **Given** the same `graph.ttl` and the bundled `views/cli-tree.rq` SPARQL query, **When** the query runs, **Then** its text output equals the 044 `tx-inspect` text output for the same tx + rules (byte-equal, modulo whitespace canonicalisation).

---

### User Story 2 — Cross-leaf identity via `owl:sameAs` in the Amaru swap (Priority: P1)

This story is 044's User Story 1 (Amaru swap settled), re-targeted to the RDF pipeline.

The operator declares the treasury as:

```turtle
@prefix : <https://amaru.network/treasury#> .
@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

:network_compliance a cardano:Entity ;
  rdfs:label "amaru-treasury.network_compliance" ;
  cardano:hasIdentifier [
    a cardano:PaymentScript ;
    cardano:bytesHex "32201dc1e82708364c6c42a53f89f675314bb9ad5da2734aa10baa0d" ] .
```

The reasoner, given:

- the operator's rule above
- the emitted base graph (33 SwapOrder inputs each with a payment credential and a blueprint-decoded `cardano:swapRecipient` field pointing at the same script hash)
- the ontology axiom `cardano:Identifier owl:hasKey (cardano:leafType cardano:bytesHex)` (any two identifiers of the same type with the same bytes are the same identifier)

deduces `owl:sameAs` between every site referencing that hash and the entity URI `:network_compliance`. The CLI view query then prints `amaru-treasury.network_compliance` at the output address site AND inside each input's `swapRecipient` field — without the engine doing a per-site lookup; the deduction is graph-level.

**Why this priority**: P1 because this is the load-bearing demonstration that the OWL approach delivers the cross-leaf identity payoff 044 set as its acceptance contract.

**Independent Test**: Render the swap-settlement tx through the full pipeline (emitter → reasoner → SPARQL view); assert the entity label appears at both site classes; assert the deduction trace (a SPARQL `DESCRIBE` on the entity URI) shows `owl:sameAs` links to the matched credentials.

**Acceptance Scenarios**:

1. **Given** the swap CBOR + Turtle rules above, **When** the full pipeline runs with EYE inference enabled, **Then** the inferred graph contains `owl:sameAs` triples linking each `_:cred*` blank node carrying the treasury script hash to `:network_compliance`, and the SPARQL CLI-view output matches 044's User Story 1 expected text byte-for-byte (modulo whitespace canonicalisation).
2. **Given** the same inputs **with reasoning disabled** (`--no-reason`), **Then** the base graph contains the operator's `cardano:hasIdentifier` triples and the tx's `cardano:bytesHex` triples but no `owl:sameAs` deductions; the CLI view falls back to a JOIN-based substitution that produces equivalent text but takes one or more SPARQL `JOIN`s extra per leaf. This documents that the reasoner provides the deduction; the engine is provably correct without it.

---

### User Story 3 — Multi-view from one graph (Priority: P2)

After running the emitter once, the reviewer runs three different SPARQL views over the same `graph.ttl`:

1. `views/cli-tree.rq` — produces the structured text 044 specified.
2. `views/asset-flow.rq` — produces a per-asset summary: `usdm: 95 (treasury → treasury)`, one line per asset class moved.
3. `views/entity-occurrences.rq` — produces a reverse-index: `amaru-treasury.network_compliance: 34 sites` (33 input recipients + 1 output address).

**Why this priority**: P2 because this is the "views for free" payoff. Each query is a few dozen lines of SPARQL, no engine change.

**Independent Test**: Run all three views over the User Story 2 graph; assert each produces deterministic, structurally-distinct text outputs the operator finds useful.

**Acceptance Scenarios**:

1. **Given** the `graph.ttl` from Story 2, **When** the three SPARQL views run in turn, **Then** each produces its specified output without any modification to the emitter or the rules. The same graph supports all three.

---

### User Story 4 — Operator composes rule files (Priority: P2)

The operator factors the Amaru treasury rules into three Turtle files: `amaru-network.ttl` (operator wallets), `amaru-treasury.ttl` (the treasury entities), `amaru-swap.ttl` (the swap.v2 script entity + blueprint reference). A top-level `tx-rules.ttl` imports all three via `owl:imports`. The emitter loads the top-level file and the imports are followed transitively.

**Why this priority**: P2 because rule composition is the modularity payoff of the RDF target. Operators publish per-domain rule files (a treasury team publishes its treasury rules; a DEX team publishes its swap-script rules; a reviewer composes them).

**Independent Test**: Author three rule files + one importer; render a tx that uses entities from all three; assert no duplication, no collision, and that the rendered output references the entities defined in each imported file.

**Acceptance Scenarios**:

1. **Given** four Turtle files (three rule files + one importer), **When** the emitter loads the importer, **Then** all entity declarations from the transitively imported files appear in the unified graph; SPARQL queries see them as a single rule corpus.
2. **Given** two imported files that declare entities with the same URI but different `rdfs:label`, **When** the emitter loads them, **Then** the loader emits a warning naming both files and uses the lexicographically-first label (deterministic, but flagged).

---

### Reference acceptance — the ten 044 transactions

Every transaction in `specs/044-rewrite-rules-redesign/spec.md` user stories 1–10 is preserved here as a golden test. The artifact for each story is:

- The same Haskell builder producing the same Conway `Tx` (delivered by harness [#45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45), re-aimed to emit graphs).
- The 044 rules YAML, transparently compiled to Turtle by the loader.
- A new `expected.ttl` capturing the emitter's graph output for that tx + rules pair.
- The bundled `views/cli-tree.rq` SPARQL view, asserted to produce text byte-equivalent to the 044 expected output.

This preserves 044's design contract: cross-leaf identity, blueprint decode, nested collapse, asset entity rendering, #43 fix. The implementation route changes; the acceptance does not weaken.

### Edge Cases

- **Operator declares an entity with no identifier**: emitter rejects at load with `EntityZeroIdentifiers <uri>`.
- **Two operator rule files declare the same `(role-class, bytes)` under different entity URIs**: reasoner deduces `owl:sameAs` between the two entity URIs; the emitter warns operator about the unification (this is correct behaviour — they declared two names for the same on-chain thing — but worth a diagnostic).
- **Operator declares an entity whose identifier bytes do not match anything in the tx**: silent (no-op); the entity triples still appear in the output graph but contribute nothing to the CLI view.
- **Reasoner failure / timeout**: emitter falls back to base-graph-only output (no `owl:sameAs` deductions) and emits a structured warning. The CLI view query degrades to JOIN-based substitution (slower but correct).
- **A `views/*.rq` query references a vocabulary term that doesn't exist in the loaded ontology**: SPARQL engine returns empty result; the view's output is empty; an explicit `cardano-tx-tools-doctor` subcommand checks view-vs-ontology compatibility (out of scope for v1; tracked as a follow-up).
- **Operator authors Turtle that doesn't parse**: emitter rejects at load with the parser error + file/line.
- **Blueprint decode failure on a datum**: emitter emits the raw bytes as a `cardano:RawDatum` node attached via `prov:wasDerivedFrom` to the blueprint and a `cardano:decodeError` literal explaining why. The view query renders raw datum verbatim; rename does not fire inside.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The emitter MUST produce an RDF graph in Turtle format (default) for every Conway transaction it processes. JSON-LD output MUST be available via `--format json-ld`.
- **FR-002**: Every URI minted by the emitter MUST be derived from a configurable namespace constant (`cardano:`, `tx:`, etc.), routed through a single `Namespace` module so URI prefix migration is one constant swap.
- **FR-003**: The transaction ontology MUST live in `cardano-knowledge-maps` as a versioned Turtle file. `cardano-tx-tools` MUST consume it via a build-time Nix input (vendored for reproducibility), not via runtime HTTP.
- **FR-004**: The emitter MUST emit base triples for: transaction body fields (inputs, outputs, fee, validity interval, certificates, withdrawals, governance proposals, mint, scriptIntegrityHash, collateral, reference inputs); the witness set (vkey witnesses, scripts, redeemers, datums); and the resolved UTxO context (address, value, datum hash / inline datum / reference script per input).
- **FR-005**: The emitter MUST emit typed-leaf triples (`?leaf a cardano:PaymentScript ; cardano:bytesHex "…"`) for every credential, script hash, pool ID, DRep credential, policy ID, and asset class encountered in the projection. Role-class types MUST be drawn from the ontology's `cardano:LeafType` `skos:ConceptScheme`.
- **FR-006**: The emitter MUST integrate the existing `Cardano.Tx.Blueprint.decodeBlueprintData` for any datum/redeemer whose script appears in the loaded blueprint index. Decoded leaves MUST be emitted as typed triples (e.g. `_:datum cardano:swapRecipient _:cred`) using property names declared in the ontology.
- **FR-007**: Operator rules MUST be accepted in two forms: Turtle (canonical) and YAML (sugar; 044's grammar plus extensions). YAML rules MUST be compiled to an equivalent Turtle representation at load time before the reasoner sees them.
- **FR-008**: Rule files MUST compose via `owl:imports` (Turtle) or an `imports:` key (YAML). Transitive imports MUST be resolved; cycles MUST be detected and rejected with a structured error naming the cycle.
- **FR-009**: The pipeline MUST support an `--no-reason` flag that emits the base graph + rule triples without invoking the reasoner. With `--reason` (default), the pipeline MUST invoke EYE to compute the inferred graph and merge inferred triples into the output.
- **FR-010**: Every rendered label in a view output MUST be traceable to its source via `prov:wasDerivedFrom` (operator-declared / blueprint-derived / legacy-sugar / inferred). The default CLI view MUST surface provenance on request (`--show-provenance`).
- **FR-011**: The default CLI-tree SPARQL view (`views/cli-tree.rq`) MUST produce text byte-equivalent (modulo whitespace canonicalisation) to 044's `tx-inspect` text output for every 044 golden story.
- **FR-012**: At least three additional SPARQL views MUST ship: `views/asset-flow.rq` (per-asset summary), `views/entity-occurrences.rq` (per-entity reverse-index), `views/json-ld.rq` (graph-to-JSON-LD projection for browser consumers).
- **FR-013**: The loader MUST validate every operator-declared entity has at least one identifier (FR-011-analogue from 044). Zero-identifier entities MUST be rejected at load with `EntityZeroIdentifiers <uri>`.
- **FR-014**: Reasoner failures (timeout, crash, malformed N3) MUST NOT cause the emitter to fail. The emitter MUST emit the base-graph-only output and a structured warning. Downstream views MUST work correctly against the un-reasoned graph (with JOIN-based fallbacks where deductions would have helped).
- **FR-015**: The emitter MUST be reproducible: given the same tx, UTxO set, rules, and ontology version, the emitted Turtle MUST be byte-identical across runs (canonical triple ordering, deterministic blank-node identifiers via a hash of the triple content).
- **FR-016**: All ten golden-test transactions from `specs/044-rewrite-rules-redesign/spec.md` MUST produce a graph that, when projected via `views/cli-tree.rq`, equals 044's expected text output byte-for-byte. Delivered by harness [#45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45), re-aimed.

### Key Entities (ontology terms)

The ontology adds the following to `cardano-knowledge-maps`' `cardano:` namespace. This is the **vocabulary draft** — Phase 0 of the plan refines it against existing terms in `cardano.ontology.ttl` / `smart-contracts.ttl`.

- **`cardano:Transaction`** — a Conway transaction. Properties: `cardano:hasInput`, `cardano:hasOutput`, `cardano:hasFee`, `cardano:hasValidityInterval`, `cardano:hasCertificate`, `cardano:hasWithdrawal`, `cardano:hasProposal`, `cardano:hasMint`, `cardano:hasCollateralInput`, `cardano:hasReferenceInput`, `cardano:hasWitnessSet`.
- **`cardano:Input`** — a tx input. Properties: `cardano:atOutRef`, `cardano:resolvedTo`. `cardano:resolvedTo` points at an `cardano:Output` from the resolved UTxO context (preserves the resolved-input pattern from `tx-inspect`).
- **`cardano:Output`** — a tx output. Properties: `cardano:atAddress`, `cardano:hasValue`, `cardano:hasDatum`, `cardano:hasReferenceScript`.
- **`cardano:Address`** — a Cardano address. Properties: `cardano:hasPaymentCredential`, `cardano:hasStakeCredential`, `cardano:bech32`.
- **`cardano:Credential`** — a credential. Subclasses: `cardano:PaymentCredential`, `cardano:StakeCredential`. Each carries a `cardano:hasIdentifier` to the typed-leaf node.
- **`cardano:LeafType`** — a `skos:ConceptScheme`. Members: `cardano:PaymentKey`, `cardano:PaymentScript`, `cardano:StakeKey`, `cardano:StakeScript`, `cardano:DRepKey`, `cardano:DRepScript`, `cardano:PoolId`, `cardano:Policy`, `cardano:AssetClass`. Each is a `skos:Concept` carrying `skos:related` links to siblings (key vs. script of the same role) and `skos:broader` to a `cardano:Hash28` super-concept where applicable.
- **`cardano:Identifier`** — the typed leaf. Properties: `cardano:bytesHex` (the canonical hex), `cardano:leafType` (one of `LeafType`'s concepts). `cardano:Identifier owl:hasKey (cardano:leafType cardano:bytesHex)` — two identifiers with the same type + bytes are the same identifier (this axiom is what enables OWL deduction of `owl:sameAs` for entities).
- **`cardano:Entity`** — operator-declared on-chain identity. Properties: `rdfs:label` (display name), `cardano:hasIdentifier` (one or more, each linking to an `cardano:Identifier`).
- **`cardano:Asset`** — a native asset. Properties: `cardano:hasPolicy` (a `cardano:Policy` identifier), `cardano:hasAssetName` (xsd:hexBinary). An `AssetClass` identifier is computed from `policy <> name`.
- **`cardano:Datum`**, **`cardano:Redeemer`** — script-locked data. Properties: `cardano:hasRawBytes`, `cardano:decodedAs` (a blueprint URI), plus blueprint-specific properties minted into the ontology when the blueprint is loaded (e.g., `swap:recipient`).
- **`cardano:Script`** — a Plutus or native script. Properties: `cardano:hasHash`, `cardano:hasVersion`.
- **Reasoning axioms**: `cardano:Identifier owl:hasKey (cardano:leafType cardano:bytesHex)`; `cardano:resolvedTo owl:inverseOf cardano:hasResolution`; `cardano:hasInput / cardano:resolvedTo / cardano:atAddress owl:propertyChainAxiom cardano:hasSpenderAddress`; etc. Phase 0 of the plan finalises the axiom set.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All ten 044 golden transactions, when run through the new pipeline, produce a graph whose `views/cli-tree.rq` projection is byte-equal (modulo whitespace canonicalisation) to 044's expected text output. (Pass/fail per story; 10/10 to ship.)
- **SC-002**: The Amaru swap (User Story 2 here / 044 Story 1) produces an inferred graph in which the treasury entity URI has `owl:sameAs` edges to every credential blank node carrying the treasury's script hash — verified by a SPARQL query that counts `?cred owl:sameAs :network_compliance` and asserts the count equals the number of distinct sites (output address + 33 input recipients = 34).
- **SC-003**: The three sample SPARQL views (`cli-tree`, `asset-flow`, `entity-occurrences`) produce useful, distinct outputs over the same `graph.ttl` from User Story 2. (Qualitative: each output structurally distinct from the others and human-readable on first glance.)
- **SC-004**: The transaction ontology lands in `cardano-knowledge-maps` as `data/rdf/transactions.ttl` and validates as well-formed Turtle + consistent OWL 2 RL (verified by an HermiT or EYE consistency check in CI).
- **SC-005**: The emitter is reproducible — running it twice on the same inputs produces byte-identical Turtle output. (CI assertion.)
- **SC-006**: End-to-end pipeline time for the Amaru swap fixture (emit → reason → CLI view) under 2 seconds on a developer laptop. (Looser than 044's SC-006 because the reasoner adds a fixed overhead; the budget is to flag a runaway reasoner, not to win speed.)
- **SC-007**: Every issue from 044's open-issues cross-reference table (`#34, #35, #36, #37, #38, #39, #40, #43`) is closed or refined against the new pipeline. The closing PR description includes a per-issue disposition table identical in spirit to 044's.

## Assumptions

- **`cardano-knowledge-maps` accepts the extension**: the ontology PR against `cardano-knowledge-maps` is in-scope for this work; this spec assumes that PR will land in coordination with the engine PR in `cardano-tx-tools`. The two are coupled: the engine cannot build until the ontology is published.
- **EYE is available**: EYE is packaged and bundled via Nix into the `cardano-tx-tools` flake. If EYE turns out to be impractical (cross-platform issues, packaging trouble), Phase 0 picks a fallback (Apache Jena via subprocess, or a hand-rolled OWL 2 RL subset).
- **Operators willing to author Turtle (or use the YAML sugar)**: the operator-facing surface is a real change. The YAML sugar is the migration path for operators who don't want to learn Turtle; ontology terms are stable enough that the YAML compiles deterministically.
- **CIP path is later, not now**: the URI namespace stays under `lambdasistemi.github.io/cardano-knowledge-maps/`. A future CIP submission would migrate URIs; the migration is mechanical thanks to the `Namespace` constant abstraction.
- **044 supersession is partial**: the design context and the ten user stories from 044 carry over verbatim. The 044 plan (slices S1–S7) and the 044 data-model are obsoleted; the 044 spec gets a "Superseded by 045" notice but is not deleted. The 044 branch + PR are closed once 045 lands a working pipeline.
- **Harness ticket #45 is re-aimed, not re-filed**: the ten Conway tx builders are still the test-fixture surface. The expected-output file format changes from text to Turtle; the SPARQL CLI view is added alongside as a packaged artifact. Issue #45's body will be updated to reflect the new artifact set.
- **Multi-view shape is operator-controllable**: the three SPARQL views shipped in this PR are starter set, not exhaustive. Operators are encouraged to author their own views; the engine doesn't gate which queries it serves.
- **Blueprint properties are minted dynamically**: when a blueprint is loaded, the loader emits transient property URIs (`cardano:bp/<scriptHash>/<fieldName>`) into the ontology graph so SPARQL queries can reference them. Phase C (SHACL shapes) is when these become persistent ontology terms.
- **Provenance is load-bearing**: every applied label carries `prov:wasDerivedFrom`. This was a recommendation from the literature review and lands in the v1 implementation, not deferred.

# Research — harness for ten Conway tx fixtures + Turtle/text goldens

**Phase**: 0 (resolve NEEDS-CLARIFICATION; record decisions and alternatives).
**Date**: 2026-05-19

The spec did not raise any `[NEEDS CLARIFICATION]` markers. This document captures the technical decisions that shape the plan, the alternatives considered, and the rationale for each choice. Decisions are ordered from broadest impact to narrowest.

## D1 — Fixture builders are Haskell modules, not on-disk CBOR

**Decision**: Each fixture's `Tx ConwayEra` is built by a Haskell module under `test/fixtures/rewrite-redesign/<story-id>/Tx.hs`, imported and invoked at test time. No CBOR artifact, no JSON encoding, no `cborHex` round-trip.

**Rationale**:

- Reviewability. The 044 spec's reviewer-facing payoff is "read the fixture, recover the story". A Haskell builder using `mkTx { ... }` declarative style is dense, readable, and obvious; a serialized CBOR blob is opaque.
- Bisect-safety. Each fixture is a self-contained Haskell module that compiles or doesn't; there is no flake (CBOR encoder version drift, ledger-binary serialization changes) between the source-of-truth and the test input.
- Cost. Building a `Tx ConwayEra` value in memory is microseconds; serialising and reloading is irrelevant for ten fixtures.
- Engine-agnosticism. The future emitter (#47) consumes `Tx ConwayEra` directly. The harness produces the same in-memory shape; no marshal/unmarshal hop.

**Alternatives**:

- *Pre-built CBOR under each fixture dir.* Rejected — adds an encode/decode hop, hides the fixture intent, requires a CBOR snapshotting script as another tool the harness must maintain.
- *YAML-described fixtures parsed by a builder.* Rejected — adds a fixture-description grammar (a third grammar alongside `rules.yaml` and the future Turtle), more code surface, no win.

## D2 — Shared builder helpers in a single `Helpers.hs` module

**Decision**: All fixtures share one module `Fixtures.RewriteRedesign.Helpers` (or equivalent) under `test/fixtures/rewrite-redesign/Helpers.hs`. The module exposes a thin record-style `mkTx :: TxBody ConwayEra -> TxWitnesses ConwayEra -> Tx ConwayEra` plus canonical addresses (alice, bob, treasury, network-wallet, contingency, recipient, operator, mpfs.oracle, foundation.ops), smart constructors for inputs / outputs / withdrawals / certs / proposals, and inline-datum / reference-script helpers. Goal: each `Tx.hs` is a few `mkTx { ... }` literal calls, no inline byte literals, no nested `do`-block builder chains.

**Rationale**:

- Brevity. The 044 spec asks for "small and readable"; SC-007 puts each `Tx.hs` under ~80 lines. A central helpers module is the most direct path.
- Locality. The helpers do not belong in `src/` — they are not public API. Keeping them under `test/fixtures/rewrite-redesign/` keeps the library namespace clean while still being importable from `RewriteRedesignGoldenSpec` and from every fixture `Tx.hs`.
- Test-suite reach. The cabal `unit-tests` test-suite already lists `test/` under `hs-source-dirs`; adding `test/fixtures/rewrite-redesign` to that list is one line in `cardano-tx-tools.cabal`.

**Alternatives**:

- *Helpers in `src/Cardano/Tx/TestFixtures/`* — rejected — would expose test-only API as library surface, violating Hackage-Ready quality (constitution IV).
- *Helpers inlined per fixture* — rejected — duplication; fixtures balloon past the 80-line SC-007 ceiling.

## D3 — Hspec `pendingWith` for upstream-dependent items

**Decision**: Each fixture's `describe "<story-id>"` block registers three Hspec items:

1. `it "produces a Tx ConwayEra of expected shape" $ ...` — active; passes today.
2. `it "Turtle byte-equivalence" $ pendingWith "awaits #47 emitter MVP"` — pending until #47.
3. `it "Text byte-equivalence via cli-tree SPARQL view" $ pendingWith "awaits #51 cli-tree SPARQL view"` — pending until #51.

**Rationale**:

- Hspec's `pendingWith` reports yellow ("pending"), not red. `./gate.sh` exits 0. The contract is documented in the test output without breaking CI.
- The pending message is searchable. Engine and view implementers see exactly which items they need to flip when they ship.
- Flipping `pending` to `it` is a one-line change per fixture — SC-008 / SC-009 hold.

**Alternatives**:

- *Real failing assertions against a stub emitter* — rejected — `./gate.sh` fails for the entire PR lifetime, blocking resolve-ticket's per-commit gate. Requires removing `just unit` from `gate.sh`, which is a fragile carve-out.
- *Hidden behind a CLI flag (`--with-emitter`)* — rejected — adds a parallel invocation path the harness has to maintain.
- *Hspec's `pending` without a message* — rejected — silent contract; the message names the upstream ticket, which is load-bearing for future contributors.

## D4 — `expected.txt` ships ahead of kmaps#53 Phase A signal; `expected.ttl` is signal-gated

**Decision**:

- `expected.txt` is a verbatim copy of the corresponding 044 spec's "Expected rendered output" code-block. Whitespace canonicalisation: trailing whitespace stripped per line, exactly one final newline, no tab characters. The file ships with the fixture's A-side commit.
- `expected.ttl` is hand-authored after `cardano-knowledge-maps#53` Phase A publishes prefix bindings + class URI declarations + property URI declarations. Tasks for `expected.ttl` are explicitly BLOCKED on the release signal arriving on the epic orchestrator's pane. See `contracts/kmaps-signal.md`.

**Rationale**:

- 044's text shape is locked at the 044 spec commit; it does not depend on kmaps#53. Authoring `expected.txt` now locks the text-recovery contract immediately, ahead of #51.
- `expected.ttl` depends entirely on the published vocab URIs. Authoring before the signal creates drift that the orchestrator explicitly excluded ("no ten-fixture rewrite").
- The two artifacts can be hand-authored independently because the contract between them (cli-tree SPARQL view projects `expected.ttl` to text byte-equal `expected.txt`) is the responsibility of `#51`, not the harness.

**Alternatives**:

- *Ship only `expected.ttl` (skip `expected.txt`)* — rejected — defers the text-recovery contract to `#51`; weakens the harness; loses the byte-equivalence pin against 044.
- *Block all fixture work on the signal* — rejected — violates Wave-0 parallelism the epic explicitly requires.
- *Author `expected.ttl` with placeholder URIs and rewrite later* — rejected — drift risk; the orchestrator explicitly excluded this.

## D5 — Turtle parse uses a thin internal shim, not a heavyweight RDF library

**Decision**: The well-formed-Turtle check for `expected.ttl` files uses an internal helper, written within the harness as a minimal-surface predicate (e.g., a regex-and-tokenizer pair, ~60 lines of Haskell, just enough to confirm prefix declarations and that triples terminate with `.`). The check answers "this file is well-formed Turtle that uses only the kmaps `cardano:` prefix" — not "this file is semantically valid against the ontology".

**Rationale**:

- Cost. Pulling in `swish`, `rdf4h`, or a similar lib adds a multi-package transitive closure to `unit-tests` for what amounts to a sanity check.
- Scope. Semantic validity belongs to `#47` (when the emitter has to actually produce the graph) and to `#49` (reasoner). The harness's job at the Turtle level is "this file is structurally well-formed and uses our vocab prefix", nothing deeper.
- Maintainability. The shim is < 100 lines; the harness commits define and test it.

**Alternatives**:

- *`swish`* — rejected — large transitive closure; adds build time across CI.
- *`rdf4h`* — rejected — heavy; the harness needs none of its query API.
- *Shell out to `rapper -i turtle -c`* — rejected — adds a non-Haskell runtime dep to the test-suite, complicates the Nix dev shell, and is overkill for a static parse check.

The shim is added in slice S1 (or as part of S15 — the first `expected.ttl` slice), bundled into `Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec` or a dedicated `Turtle.hs` private helper.

## D6 — Per-fixture commit slice; expected.ttl as a separate post-signal slice

**Decision**: Each A-side fixture lands as one bisect-safe commit (`test(045): fixture <NN-story-id>`) that includes the fixture's `Tx.hs`, `rules.yaml`, `expected.txt`, the registry entry in `RewriteRedesignGoldenSpec`, and the new `describe` block. The corresponding B-side `expected.ttl` lands as its own commit (`test(045): pin <story-id> expected.ttl to kmaps#53 Phase A vocab`) once the kmaps#53 Phase A signal arrives.

**Rationale**:

- Bisect-safety. Each commit at HEAD compiles and `./gate.sh` is green. The structural Hspec check passes the moment the fixture lands; the Turtle and text items are `pending` until their upstreams ship.
- Reviewability. A reviewer triages by reading one commit per fixture — Tx.hs + rules.yaml + expected.txt side by side.
- Signal coordination. The A-side does not need the signal; the B-side does. Splitting at the signal boundary makes the dependency obvious in the git log.

**Alternatives**:

- *One huge "all-fixtures" commit* — rejected — bisect-hostile; review-hostile.
- *Tx.hs / rules.yaml / expected.txt in separate commits per fixture* — rejected — each isolated commit fails the structural Hspec check ("Tx of expected shape" must round-trip the YAML and reach `expected.txt`); breaks bisect.

## D7 — YAML parser extension (S4) is conditional, not pre-committed

**Decision**: The harness PR ships an additive `feat(rewrite): extend parseRewriteRulesYaml for 045 entity/blueprint sugars` slice ONLY IF the existing parser cannot accept the 044 user-story YAMLs. The decision point is the first A-side fixture that uses the 045 `entities:` list, `blueprints:` section, or new `kind:` sugars (likely fixture 02-alice-bob-ada).

**Rationale**:

- Minimise spec-vs-implementation risk. The parser extension may turn out to be invasive; if so, the orchestrator pauses the harness and re-cuts the plan.
- Additive only. Whatever the extension is, it must accept every 044/032 YAML unchanged. The S4 brief carries the legacy-YAML regression list as RED.
- Drop-able. If the existing parser happens to accept the 044 YAMLs as-is (because the new sugars are loader-translated by the future engine, not the parser), S4 is dropped from the plan with no follow-up needed.

**Alternatives**:

- *Always ship the parser extension* — rejected — risks unnecessary churn if not needed.
- *Defer the parser extension to a separate PR* — rejected — fixture YAMLs would fail to parse on this PR's CI, breaking `./gate.sh` and the harness suite's RED→GREEN proof.

## D8 — Blueprint files are minimal hand-authored CIP-57 documents

**Decision**: The two blueprint files (`swap-v2-datum.cip57.json` and `mpfs-fact.cip57.json`) are hand-authored to the minimum CIP-57 shape that exposes the field(s) the corresponding fixture references (`recipient` for swap, `requester` for fact). The harness does not validate them against a full CIP-57 JSON schema.

**Rationale**:

- Scope. Blueprint validation belongs to `#50` (blueprint decode). The harness's job is to ship example blueprints the engine will consume.
- Cost. A full CIP-57 schema validator is its own engineering effort; the harness needs none of it.
- Reviewability. Minimal blueprints are < 30 lines of JSON each, readable side-by-side with the fixture's `rules.yaml`.

**Alternatives**:

- *Pull production blueprints (e.g., from the live amaru-swap repo)* — rejected — couples the harness to upstream artifacts that may evolve; loses reviewability.
- *Validate against the CIP-57 JSON schema* — rejected — out of scope; #50's responsibility.

## D9 — Module name convention for fixtures

**Decision**: Fixture modules live under the Haskell module path `Fixtures.RewriteRedesign.S<NN>_<CamelCaseSlug>` (e.g. `Fixtures.RewriteRedesign.S01_AmaruTreasurySwap`, `Fixtures.RewriteRedesign.S02_AliceBobAda`). The Helpers module is `Fixtures.RewriteRedesign.Helpers`. All under the `test/fixtures/rewrite-redesign/` filesystem path.

**Rationale**:

- The `Fixtures.*` namespace separates test fixtures from the library's `Cardano.Tx.*` namespace, preserving constitution II (module namespace discipline) while keeping the modules importable by `RewriteRedesignGoldenSpec`.
- The `S<NN>_` numeric prefix matches the fixture directory name and the 044 story order; reviewers can scan by either path or module name.

**Alternatives**:

- *`Cardano.Tx.Rewrite.Fixtures.S<NN>`* — rejected — test-only modules under `Cardano.Tx.*` create the impression they are library API.
- *Cabal-discovered "test-discover"-style fixtures* — rejected — adds a code-generation step; the registry list is short enough (10 entries) to write by hand.

## Summary

All NEEDS CLARIFICATION markers were resolved in the spec without leaving residual ambiguity. The decisions above pin the harness shape end-to-end; no further research is required before Phase 1.

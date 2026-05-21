# Implementation Plan: Blueprint decode → typed triples (CIP-57)

**Feature**: `Cardano.Tx.Graph.Emit.Blueprint` (typed datum/redeemer emission)
**Branch**: `050-blueprint-decode-typed-triples`
**Spec**: [spec.md](./spec.md)
**Tasks**: [tasks.md](./tasks.md)
**Analyzer report** (after dispatch): [analysis.md](./analysis.md)
**Predecessor plan**: [`specs/070-body-emit-conway-semantic/plan.md`](../070-body-emit-conway-semantic/plan.md)
**Parent answer**: `/tmp/epic-046/tx-50/answers/A-001-design-decisions.md`

## Constitution gate

- **One-Way Dependency** (Principle I): the work stays inside
  `Cardano.Tx.Graph.Emit.*` and `Cardano.Tx.Graph.Rules.Load.*`. The new
  `Emit.Blueprint` module depends on `Cardano.Tx.Blueprint` (already in
  the library) and on `Emit.Triple` + `Emit.Lookup`. No new edges from
  `Emit` to `Diff` beyond what #58/#70/#77 already imports.
- **Module Namespace** (Principle II): `Emit.Blueprint` is a sibling of
  `Emit.Project`, `Emit.Witness`, `Emit.Triple`, `Emit.Vocab`,
  `Emit.Lookup`, `Emit.Serialize.*`, `Emit.Monad`, `Emit.VocabExport`. No
  fresh namespace.
- **Conway-Only** (Principle III): the decoder consumes `Data ConwayEra`
  via the existing blueprint module signature; no era generalisation.
- **Hackage-Ready** (Principle IV): Haddock on every exported function;
  module headers in `{- | … -}` form; `cabal check` + `cabal haddock
  lib:cardano-tx-tools` clean. Inherits #58/#70's PvP-upper-bounds +
  `werror` cabal flag baseline.
- **Strict Warnings** (Principle V): incomplete-pattern warnings still
  surface unhandled `OpenValue` constructors at the emitter ↔ blueprint
  boundary. The new `BlueprintDecodeResult` ADT propagates via
  `-Wincomplete-patterns` into the emitter call sites.
- **Default-Offline** (Principle VI): blueprint JSON paths are relative
  to the rules.yaml directory; absolute / `file://` / `http(s)://` paths
  rejected with the new `AbsoluteBlueprintPath` / `HttpsBlueprintPath`
  loader-error variants. No network temptation.
- **TDD With Vertical Bisect-Safe Commits** (Principle VII): every
  implementation slice S0..S11 is one bisect-safe commit with
  RED+GREEN folded; the per-slice TDD shape is captured in tasks.md.

## Pinned decisions (D-001a..D-001g per A-001)

The seven decisions from A-001 anchor every slice below. Quoted summaries
(full rationale in `Q-001-design-decisions.md` + A-001):

- **D-001a — Blueprint loading surface.** Extend `rules.yaml`
  `blueprints:` loader to read each entry's `datum: <path>` file (relative
  to rules dir; `owl:imports` policy), parse via `parseBlueprintJSON`,
  thread the index through `RulesLoadResult`. **No new CLI flag.**
- **D-001b — Predicate namespace.** Mint blueprint-derived predicates
  into the fixture-scoped default `:` prefix as
  `:<ConstructorTitle>_<FieldTitle>`. Naming-collision is a **hard
  loader error** `DuplicateBlueprintPredicate`.
- **D-001c — Vocab traceability narrowing.** `VocabTraceabilitySpec`
  narrows to the `cardano:` namespace only. Blueprint-minted predicates
  get their own `BlueprintPredicateTraceabilitySpec` (set-equality
  check). One new canonical term: `cardano:decodeError` — via kmaps
  Phase A.4.
- **D-001d — Decode-failure semantics.** Emit `hasRawBytes` +
  `cardano:decodeError "<reason>"` literal (the **first** decoder error
  only — never multiple `decodeError` literals on the same Datum
  subject). Stderr warning per failure. **Pipeline exits 0.**
- **D-001e — Reasoner interplay.** #50 emits typed triples only — **no
  OWL annotations**. Acceptance row 4 of ticket #50 is #49's integration
  test, not a #50 gate.
- **D-001f — Test fixtures.** Three new fixtures with pinned slugs:
  `12-blueprint-typed`, `13-blueprint-passthrough`,
  `14-blueprint-decode-fail`. Existing fixture 01 stays frozen.
- **D-001g — CLI surface.** No new flags. The existing `--rules <path>`
  is the single blueprint-input surface.

## Owned-file set (final, per A-001)

Library:

- `src/Cardano/Tx/Graph/Emit/Blueprint.hs` — **NEW**: typed
  `BlueprintDecodeResult` ADT + `decodeDatumForOutput` +
  `decodeRedeemerForPurpose` + the constructor-to-IRI minter used by
  the projection walker.
- `src/Cardano/Tx/Graph/Emit/Project.hs` — extend `emitOutputDatum`
  (~line 1573) to consult the blueprint index and emit typed triples on
  match.
- `src/Cardano/Tx/Graph/Emit/Witness.hs` — extend the datum-witness path
  symmetrically (FR-006).
- `src/Cardano/Tx/Graph/Emit.hs` — extend the `emit` signature with the
  blueprint-index parameter (defaults to `[]` = no-op for the existing
  11 fixtures); re-export `BlueprintDecodeResult` for tests.
- `src/Cardano/Tx/Graph/Rules/Load/Types.hs` — new `RulesLoadError`
  variants: `BlueprintFileMissing`, `BlueprintParseError`,
  `AbsoluteBlueprintPath`, `HttpsBlueprintPath`,
  `DuplicateBlueprintForScript`, `DuplicateBlueprintPredicate`.
- `src/Cardano/Tx/Graph/Rules/Load.hs` — `RulesLoadResult` gains
  `rulesBlueprints :: ![(ScriptHash, Blueprint, Text)]`; new render
  cases in `renderRulesLoadError`.
- `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs` — extend the existing
  shape-validating walker to **actually read + parse** the `datum:`
  path; gather the blueprint index; raise the new error variants.
- `cardano-tx-tools.cabal` — wire the new `Emit.Blueprint` module.

Tests:

- `test/Cardano/Tx/Graph/Emit/BlueprintSpec.hs` — **NEW**: unit spec
  for the pure decoder + IRI minter; synthetic blueprints (no fixtures
  loaded).
- `test/Cardano/Tx/Graph/Emit/BlueprintPredicateTraceabilitySpec.hs` —
  **NEW**: FR-010 / D-001c set-equality check.
- `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` — extend the byte-diff
  enumeration to cover the three new fixtures.
- `test/Cardano/Tx/Graph/Rules/Load/*Spec.hs` (existing or new) —
  loader-error variants get round-trip tests.

Fixtures (D-001f slugs pinned):

- `test/fixtures/rewrite-redesign/12-blueprint-typed/` — typed path.
- `test/fixtures/rewrite-redesign/13-blueprint-passthrough/` —
  no-blueprint passthrough.
- `test/fixtures/rewrite-redesign/14-blueprint-decode-fail/` —
  decode-failure path.
- `test/fixtures/rewrite-redesign/blueprints/wrong-shape.cip57.json`
  (or per-fixture variant) — the deliberately-wrong blueprint for 13.

Surfaces (deliverables enumeration):

- `docs/assets/asciinema/tx-graph.cast` +
  `docs/assets/asciinema/scripts/tx-graph.sh` — re-record on fixture 11.
- `docs/tx-graph.md` + `README.md` — blueprint-decode paragraph + extra
  CLI example.
- `CHANGELOG.md` — one entry under the next release cut.
- `test/fixtures/canonical-vocab/transactions.ttl` +
  `test/fixtures/canonical-vocab/PINNED.md` — refresh once kmaps Phase
  A.4 patch lands.
- `.github/workflows/darwin-dev-homebrew.yml` — validation-string check
  if `--help` changed.

## Vertical slices

Slice order pinned by A-001's "Continue" section. Every slice ends with
`./gate.sh` GREEN and a regenerated `expected.ttl` byte-diff GREEN against
the predecessor's expectation (which is rolled forward in the same commit).

| Slice | Subject | Conventional Commit prefix | Tasks |
|---|---|---|---|
| S0 | Extend `RulesLoadResult` with the blueprint-index field; loader reads + parses + threads (no emitter changes). New `RulesLoadError` variants ship in the same commit. Byte-diff GREEN on every existing fixture (no blueprint loaded → no behaviour change). | `chore(050):` | T100 |
| S1 | `Cardano.Tx.Graph.Emit.Blueprint` module with `BlueprintDecodeResult`, `decodeDatumForOutput`, `decodeRedeemerForPurpose`. Pure functions, unit-tested with synthetic inputs. **No `emit` signature change yet.** | `feat(050):` | T101 |
| S2 | Extend `emit` signature to accept the blueprint index; thread through `projectBody` + `projectWitness`; `emitOutputDatum` consults the index. Callers pass `[]` for existing fixtures → byte-diff still GREEN. | `feat(050):` | T102 |
| S3 | Vendor fixture **12-blueprint-typed** + extend `EmitGoldenSpec` to cover it. **First operator-visible behavior-changing slice.** | `feat(050):` | T103 |
| S4 | Vendor fixture **13-blueprint-passthrough**; `BlueprintPredicateTraceabilitySpec` asserts no `:_<>` predicates appear when no blueprint registered. | `feat(050):` | T104 |
| S5 | Vendor fixture **14-blueprint-decode-fail**; `decodeError` literal + stderr warning + exit 0 asserted. | `feat(050):` | T105 |
| S6 | Draft + publish Phase A.4 patch for `cardano:decodeError`. PARENT-ACTION on STATUS.md → parent files kmaps#58. | `chore(050):` | T106 |
| S7 | Refresh canonical-vocab pin to kmaps#58 branch tip; flip `VocabTraceabilitySpec` from 33/33 to 34/34. | `chore(050):` | T107 |
| S8 | Re-record `tx-graph.cast` on fixture 11; refresh `docs/tx-graph.md` + README. | `docs(050):` | T108 |
| S9 | Refresh canonical-vocab pin to merged kmaps#58 main SHA — **finalization-blocking**; pin must match a merged SHA before PR #79 flips to ready. | `chore(050):` | T109 |
| S10 | `CHANGELOG.md` entry under the next release cut. | `docs(050):` | T110 |
| S11 | Drop `gate.sh`; `gh pr ready`. | `chore(050):` | T111 |

The slice count is 12 (S0..S11). S0/S1 are no-behavior-change "plumbing"
slices; S2 is a still-byte-stable signature refactor; S3..S5 are the
behavior-changing fixture slices; S6..S11 are deliverables wire-up +
finalization.

**Note on commit order**: S7 must commit BEFORE the first behavior-changing
fixture that emits `cardano:decodeError` references it in the canonical
vocab — which is fixture 13 (S5). The recommended commit order is
`S0 → S1 → S2 → S3 → S4 → S6 → S7 → S5 → S8 → S10 → S9 → S11` if the
canonical-vocab strict check would fail on fixture 13 without S6/S7. If S5's
`expected.ttl` can ship before kmaps Phase A.4 lands (`VocabTraceabilitySpec`
stays at 33/33 strict on `cardano:*` and a new term in `expected.ttl` does
NOT fail the check until the pin is refreshed), the table order works as
listed. Plan validation in S0 / tasks.md confirms this.

## Test strategy

### RED/GREEN per slice (TDD with vertical bisect-safe commits)

Each behavior-changing slice (S1..S5) ships its own RED first:

| Slice | RED proof (failing test added in the SAME commit, with the GREEN fix) |
|---|---|
| S0 | New `RulesLoadResult` field `rulesBlueprints` is unit-tested via a synthetic in-memory YAML blob that declares a `blueprints:` entry pointing to a synthetic on-disk JSON. The assertion is: `rulesBlueprints` is non-empty after a successful load, AND its `ScriptHash` keys match the referenced entity's `PaymentScript` identifier bytes. RED before the loader is wired; GREEN after. |
| S1 | New `BlueprintSpec` asserts `decodeDatumForOutput` returns `Decoded openValue blueprint` on a synthetic match, `NoBlueprintRegistered` on a synthetic miss, and `DecodeFailed err` on a synthetic mismatch. Pure-function tests; no fixtures. RED before the module lands; GREEN after. |
| S2 | New invariant in `EmitGoldenSpec` asserts the regenerated `expected.ttl` for every existing fixture is **byte-equal** to the pre-S2 expectation (signature refactor proves no drift). The `emit` signature change requires updating every caller in tests; the invariant catches any walker-path bug. |
| S3 | `EmitGoldenSpec` extends to fixture 11; the new `expected.ttl` carries `:SwapOrder_recipient _:recipient1` and `_:recipient1 a cardano:Identifier ; cardano:bytesHex <hex> ; cardano:leafType "PaymentScript"`. RED before fixture vendoring; GREEN after the emitter wires the typed-emission path. SPARQL invariant (from spec.md SC-002) is asserted by a smoke test that runs `arq` or equivalent over the emitted Turtle (or — if `arq` is not in the toolbox — by a substring-based assertion equivalent). |
| S4 | `BlueprintPredicateTraceabilitySpec` asserts fixture 12's `expected.ttl` contains **no** `:_<>` predicates from the blueprint index (set-equality on emitted-vs-declared predicate sets; declared set is empty when `rules.yaml` carries no `blueprints:` entries). RED on first introduction; GREEN once fixture 12 ships. |
| S5 | New `DecodeFailureSpec` (or extension of `EmitGoldenSpec`) asserts fixture 13's `expected.ttl` contains both `cardano:hasRawBytes` and `cardano:decodeError` on the same Datum subject (the latter once only — D-001d FIRST-error invariant). Also asserts (a) exit code 0, (b) the stderr warning substring matches `expected.txt`. RED on first introduction; GREEN once fixture 13 ships. |

For each slice the RED runs FIRST locally (developer observes the
failure), then the GREEN fix is added, then `./gate.sh` is invoked,
then the commit is created. Tasks.md captures this rhythm.

### Live-boundary diagnostic per slice

Per resolve-ticket's "live-boundary smoke" addition, every slice that
touches operator-observable behavior gets a diagnostic question at
review-time: "what is the boundary this slice would fail at, and how
do we know the test exercises it?"

For #50:

| Slice | Boundary | How exercised |
|---|---|---|
| S0 | rules-loader ↔ blueprint-JSON file (filesystem read + JSON parse) | Synthetic in-memory YAML + on-disk JSON in `test/Cardano/Tx/Graph/Rules/Load/*Spec.hs`. The path-resolution policy (`owl:imports` mirroring) is exercised by absolute/`file://`/`https://` rejection unit tests. |
| S1 | blueprint-decoder ↔ `OpenValue` AST | Pure unit tests on synthetic `Data ConwayEra` values + synthetic `BlueprintSchema`. Boundary is structural; no I/O. |
| S2 | emitter signature ↔ all callers | `EmitGoldenSpec` regression sweep over all existing fixtures with `[]` blueprint index — byte-diff invariant. |
| S3 | emitter ↔ blueprint-decoder + fixture-scoped namespace minter | Fixture 11 `expected.ttl` byte-diff; SPARQL invariant from SC-002; live-CBOR boundary (the operator-paste SwapOrder datum is real Conway bytes). |
| S4 | emitter ↔ rules-loader (no-blueprint path) | Fixture 12 `expected.ttl` byte-diff vs the post-#77 baseline; `BlueprintPredicateTraceabilitySpec` set-equality. |
| S5 | emitter ↔ blueprint-decoder (failure path) + stderr | Fixture 13 `expected.ttl` byte-diff + exit-code + stderr substring assertions in the exe spec. |
| S6 | kmaps repo ↔ vendored pin | n/a from this PR's perspective — the patch draft lives in `/tmp/epic-046/tx-50/`, kmaps#58 is the parent's responsibility. |
| S7 / S9 | canonical-vocab pin ↔ `VocabTraceabilitySpec` strict CI gate | `VocabTraceabilitySpec` invariant count goes 33/33 → 34/34; pin refresh is byte-stable. |
| S8 | asciinema-cast viewer ↔ docs preview | Manual reviewer check at the preview URL. |
| S10 | none (docs / changelog) | n/a |
| S11 | none (gate.sh drop) | n/a |

Fixture 11 (S3) is the **strongest live-boundary signal** in the slice
plan — it loads real on-chain CBOR bytes (the operator-paste SwapOrder
datum) and exercises the new emitter path end-to-end without mocking
any ledger or blueprint type.

### Existing invariant carry-over (#58 / #70 / #77 SC-001..SC-008)

All eight #58 success criteria and the #70/#77 byte-diff + vocab traceability
invariants are explicitly carried forward by re-running the existing
`EmitGoldenSpec`, `JsonLdEquivalenceSpec`, `ReproducibilitySpec`,
`VocabTraceabilitySpec`, etc. against the regenerated `expected.ttl` files
for the 11 existing fixtures **plus** the three new ones. A regression on
any of these is a GATE-FAIL on the slice that introduced it; the offending
slice is reworked, not bypassed.

## Risks

- **R1** — The `Cardano.Tx.Blueprint.parseBlueprintJSON` decoder is
  exercised on the two vendored CIP-57 fixtures so far
  (`swap-v2-datum.cip57.json`, `mpfs-fact.cip57.json`); the typed-emission
  path is sensitive to schema edge cases (heterogeneous `anyOf`,
  `SchemaListOf` with mixed leaves, deep `SchemaReference` cycles) that
  the existing tests may not exercise. Mitigation: synthetic unit tests
  in `BlueprintSpec` cover each `BlueprintSchemaKind` constructor; any
  decoder bug surfaces as a `BlueprintDataError` fed into the
  decode-failure path (graceful degradation).
- **R2** — The fixture 11 `expected.ttl` minting requires deciding the
  exact byte-shape of typed-emission for a nested constructor. Plan
  decision: pin the exact shape in tasks.md's T103 before authoring
  `expected.ttl`; document it as a small ADR-style note inside the
  fixture's `NOTES.md`.
- **R3** — kmaps Phase A.4 patch (S6) is a cross-repo dependency that
  the worker cannot land directly. PARENT-ACTION mechanism surfaces it
  via STATUS.md → parent files kmaps#58. The blocker is finalization
  (S9, S11) not the implementation slices (S0..S5), so the worker
  continues; if kmaps#58 stalls more than 48h the worker logs `BLOCKED
  Q-NNN-kmaps-phase-a4-stall` and waits.
- **R4** — `RulesLoadResult` is consumed by multiple callers
  (`tx-graph` exe, harness builders). Extending the record may break
  consumers. Mitigation: S0 ships pattern-match audit + targeted
  callsite updates in the same commit; CI build catches misses.
- **R5** — Fixture-scoped IRI minting (`:<Ctor>_<field>`) may collide
  with existing entity slugs in operator-authored `rules.yaml`. The
  loader's `DuplicateBlueprintPredicate` hard error covers the same-fixture
  case; cross-namespace (entity slug vs predicate slug) collisions are
  resolved by the fact that entities use `:<slug> a cardano:Entity .`
  (subject position) and predicates use `:<slug>` in predicate position
  — Turtle grammar disambiguates them. Plan validation: add a unit test
  in `BlueprintSpec` exercising a fixture where an entity slug matches
  a blueprint predicate name.

## Pre-implementation prereqs

None outside this branch — S0 is self-contained. The PARENT-ACTION for
kmaps#58 only blocks the canonical-vocab pin refresh (S7, S9), not the
implementation slices. The harness #45 `build-fixture.hs` regen path is
already in place from #58/#70.

## Sequencing tie-in to epic #46

After #50 merges, the epic state is:

- Child 1 (vocab Phase A): merged via [kmaps#55..#57].
- Child 2 (emitter MVP): merged as #60 (#58 spec) + #77 (#70 spec).
- **Child 3 (blueprint decode): this PR (#50 / #79).**
- Child 4 (reasoner #49): unblocked once #50 merges. The owl:sameAs
  derivation referenced by ticket #50 acceptance row 4 becomes #49's
  integration test.
- Child 5 (SPARQL views #51): can author views over typed datum/redeemer
  shapes once #50 ships.

The epic stays open until the no-stub SPARQL view + the published
`tx-graph` asciinema cast demonstrate rich output (per the epic's
"Cast gate — demonstrable rich output" section). #50's S8 contributes
the final piece of cast content.

# Implementation Plan: Body emitter — Conway tx + UTxO + rules → joint Turtle/JSON-LD

**Feature**: `Cardano.Tx.Graph.Emit`
**Branch**: `58-body-emitter`
**Spec**: [spec.md](./spec.md)
**Research**: [research.md](./research.md)

## Constitution gate

- **One-Way Dependency** (Principle I): `Cardano.Tx.Graph.Emit` imports
  only from `Cardano.Tx.*` (the existing `Cardano.Tx.Diff` for
  projection access, `Cardano.Tx.Graph.Rules.Load` for the entity
  overlay), `Cardano.Ledger.*` types already re-exported through
  `Cardano.Tx.Diff`, and the existing dep closure. No new reverse arrow
  into `cardano-node-clients`.
- **Module Namespace** (Principle II): The new module sits alongside
  `Cardano.Tx.Graph.Rules.Load` under the `Cardano.Tx.Graph.*` subtree
  reserved for the graph layer (epic #46). Wave-3 modules
  (`Cardano.Tx.Graph.Reason`, `Cardano.Tx.Graph.View`) will sit as
  siblings.
- **Conway-Only** (Principle III): The emitter consumes `ConwayTx` and
  Conway-era projections; no era-generic generalization is attempted.
- **Hackage-Ready** (Principle IV): Haddock on every exported function
  in the new modules; module headers in `{- | … -}` form; `cabal check`
  clean. Inherits #48's PvP-upper-bounds + `werror` cabal flag baseline;
  no new direct deps.
- **Strict Warnings** (Principle V): no escape hatches; the module
  inherits the `warnings` common stanza. Incomplete-pattern warnings
  surface unhandled `conwayDiffProjection` variants at compile time
  (FR-005 spec / D2 below).
- **Default-Offline** (Principle VI): no network access during emit; no
  fetching of remote IRIs.
- **TDD With Vertical Bisect-Safe Commits** (Principle VII): every
  slice in this plan is one bisect-safe commit, with RED+GREEN folded
  in. The TDD shape is captured in tasks.md per slice.

## High-level architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│  app/tx-graph/Main.hs   (extended)                               │
│    optparse: --rules <file>  (existing, #48)                     │
│              --tx <file>     (new)                               │
│              --utxo <file>   (new)                               │
│              --out <file>    (new, defaults to stdout)           │
│              --format turtle|json-ld  (new, defaults to turtle)  │
│    flag-presence dispatcher:                                     │
│      --rules only       → overlay (#48's path; unchanged)        │
│      --tx + --rules     → body+overlay                           │
│      --tx only          → body, no entity-named bnodes           │
└──────────────────────────────────────────────────────────────────┘
                            ▲
                            │ depends
                            │
┌───────────────────────────┴──────────────────────────────────────┐
│  src/Cardano/Tx/Graph/Emit.hs                                    │
│    public:                                                       │
│      data EmitError = …                                          │
│      data EmittedGraph                                           │
│      data EmitFormat = Turtle | JsonLd                           │
│      emit       :: ConwayTx -> ResolvedUTxO -> [EntityDecl]      │
│                 -> Either EmitError EmittedGraph                 │
│      serialize  :: EmitFormat -> EmittedGraph -> ByteString      │
│    private (other-modules under Cardano.Tx.Graph.Emit.*):        │
│      Vocab     -- single-source-of-truth `cardano:` IRI registry │
│      Lookup    -- (LeafType, bytesHex) → BnodeName via overlay   │
│      Project   -- projection-walker, leaf → triples              │
│      Serialize.Turtle -- canonical-form Turtle of EmittedGraph   │
│      Serialize.JsonLd -- JSON-LD projection of EmittedGraph      │
│                                                                  │
│  src/Cardano/Tx/Graph/Rules/Load.hs  (extended)                  │
│    RulesLoadResult gains: rulesEntities :: [EntityDecl]          │
│    (new field; existing rulesOverlayTurtle unchanged)            │
└──────────────────────────────────────────────────────────────────┘
```

Library-vs-executable boundary:

- The library function `emit :: ConwayTx -> ResolvedUTxO -> [EntityDecl]
  -> Either EmitError EmittedGraph` is pure. It consumes typed values,
  not CBOR/JSON files. Tests call it directly via the fixture builders
  (which already produce `ConwayTx` values in-memory).
- The executable does the CBOR/JSON decoding via existing helpers in
  `Cardano.Tx.Diff.Resolver` (UTxO JSON) and the ledger's `DecCBOR`
  (Conway tx CBOR). On decode failure, it returns a structured error.
- The byte-diff golden runs the **library** path (no CBOR roundtrip),
  so a CBOR encoding/decoding bug cannot mask an emitter bug. An
  end-to-end executable smoke test for one fixture rounds the full
  exe pipeline (one fixture is enough — no byte-diff against the
  exe-roundtripped output is asserted, only Turtle parseability).

The shape of the emit pipeline:

```haskell
emit conwayTx utxo entities = do
    1. build lookup table: Map (LeafType, ByteString) BnodeName
       from `entities` (entity-named) PLUS lazy raw-bytes fallback
    2. walk `conwayDiffProjection` on `conwayTx`
    3. for every leaf, dispatch on its projected shape:
         - Address  → AddressBnode + 2 hasCredential triples
         - Input    → Input bnode + resolvedTo triple (from utxo)
         - Output   → Output bnode + atAddress + value triple
         - Cert     → Cert-specific triple cluster
         - Mint     → policy/asset triples
         - …
    4. accumulate triples in deterministic source order
    5. assemble EmittedGraph = (prefixes, overlay-triples-passthrough,
                                body-triples)
    6. return EmittedGraph
```

The serializer is dispatched by `EmitFormat` at the call boundary:

```haskell
serialize Turtle  g = renderCanonicalTurtle g    -- D5 below
serialize JsonLd  g = renderCanonicalJsonLd g    -- D6 below
```

## Key design decisions

### D1 — No new RDF library

In-house Turtle + JSON-LD serializers. Inherits #48's precedent. JSON-LD
output is a `@context`-prefixed JSON document with subject-grouped
triples; no full JSON-LD framing / c14n is attempted. See
[research.md R1](./research.md) for the in-house-vs-`rdf4h`/JSON-LD-Java
tradeoff and the in-scope/out-of-scope JSON-LD subset.

### D2 — Projection-driven walker (single source of truth for leaves)

The emitter walks the transaction via
`Cardano.Tx.Diff.conwayDiffProjection`. Each call returns a list of
projection leaves with their typed shapes (e.g. `ConwayTxInValue`,
`ConwayInputsValue`, `ConwayOutputValue`, `ConwayAddressValue`,
`ConwayCertValue`, etc.). The emitter's `Project` module dispatches on
the leaf constructors via an exhaustive `case`; any new constructor
added upstream produces a `-Wincomplete-patterns` compile error
(constitution Principle V), which is the explicit-coverage gate.

The mapping from projection leaves to vocab triples is enumerated in
[research.md R2](./research.md) — one row per leaf type seen across the
11 fixtures, with the corresponding `cardano:` predicate and triple
cluster. Leaves not present in the 11 fixtures but allowed by Conway
ledger types are flagged in research R2 as "deferred to a follow-up
(no fixture coverage)" and produce an `UnsupportedLeafType <name>`
error at runtime, surfaced before any partial output.

### D3 — Credential lookup table

The lookup table is built once at the start of `emit`:

```haskell
type LookupTable = Map (LeafType, ByteString) BnodeName

buildLookup :: [EntityDecl] -> LookupTable
buildLookup entities = Map.fromList
    [ ((leafType, bytes), entityBnode entity ident)
    | entity <- entities
    , ident  <- entityIdentifiers entity
    , let leafType = entityIdLeafType ident
          bytes    = decodeHex (entityIdBytesHex ident)
    ]
```

Per #48 FR-013 + D2 (rules loader): the first declaration in source
order owns the bnode name; later entities sharing the same `(LeafType,
bytes)` reference the same bnode. The `[EntityDecl]` list returned by
`RulesLoadResult` already preserves source order, so `Map.fromList`'s
right-biased semantics naturally take the **last** entity; we use
`Map.fromListWith (\_new old -> old)` to keep the **first**. This
matches #48's first-declarant-wins rule.

On lookup miss, the emitter falls through to the raw-bytes-named
bnode scheme (D4).

### D4 — Raw-bytes-named bnode scheme

For a credential `(LeafType, bytesHex)` not covered by any entity, the
bnode name is:

```
_:cred_<rolePrefix>_<bytes-prefix>
```

where:

- `<rolePrefix>` is the leaf type lowercased verbatim:
  `paymentkey` / `paymentscript` / `stakekey` / `stakescript` /
  `assetclass` / `policy` / `poolid` / `drepkey` / `drepscript`.
- `<bytes-prefix>` is the first N hex characters of `bytesHex`.

`N` is chosen as the minimum value such that, across the 11 fixtures'
**full set of credentials** (entity-covered AND not-entity-covered),
no two distinct `(LeafType, bytes)` pairs collide on the
`(rolePrefix, bytes-prefix)` prefix. Empirically — see
[research.md R3](./research.md) — `N = 16` (8 bytes of hex) is
collision-free across all fixtures with a 4-character safety margin
above the maximum needed; the analysis is pinned in research R3 with
the per-fixture credential census.

Rationale for prefix-based naming (vs full 56-char hex):

- 16 characters is short enough for visual scanning in `expected.ttl`
  files (the goldens reviewers look at);
- collisions across 11 fixtures with the +4-char margin are
  vanishingly unlikely;
- determinism is preserved (same bytes → same prefix → same bnode).

If a future fixture introduces a collision, the bump-N migration is a
single `chore: bump raw-bnode prefix to N=N+2` slice that re-runs the
goldens.

### D5 — Joint Turtle serializer

The serializer emits in this exact form, replicating the artisan
fixture layout but with #48-deterministic bnode names:

```turtle
@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .
@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .
@prefix :        <https://lambdasistemi.github.io/cardano-tx-tools/fixtures/<slug>#> .

#
# Operator-declared entities (from rules.yaml).
#

<...verbatim copy of expected.entities.ttl entity-overlay body...>

#
# Transaction body.
#

_:tx a cardano:Transaction ;
  cardano:hasInput _:input1 ;
  cardano:hasOutput _:output1 ;
  ...
  cardano:hasFee 175000 .

#
# Input — <comment from emit metadata> .
#

_:input1 a cardano:Input ;
  cardano:resolvedTo _:resolvedInput1 .

...
```

Rules (rules in addition to #48 D4 — which the overlay section inherits
unchanged):

- After the overlay section, a single blank line, then comment
  `# Transaction body.`, then a blank line, then the `_:tx` block.
- Inputs / outputs / certs / mints / withdrawals are each blocked by a
  preceding **uniform** comment line `# Input N` / `# Output N` /
  `# Cert N` / etc. — no per-fixture descriptive prose. The artisan
  narrative migrates to `NOTES.md` per fixture in T001a (Q-003 → A-003);
  the joint `expected.ttl` carries only machine-emitted comments so the
  emitter contract stays narrative-free.
- Each leaf gets exactly the artisan-reference predicate cluster (e.g.
  an `Address` leaf gets 4 triples: `a cardano:Address ;`,
  `cardano:bech32 "..." ;`, `cardano:hasPaymentCredential _:... ;`,
  `cardano:hasStakeCredential _:... .`).
- Trailing newline at end-of-file.

This is the byte-stable serializer the cross-PR contract anchors on.
See [research.md R4](./research.md) for the byte-shape rationale (which
predicates anchor which leaves, comment-style conventions, leaf-vs-block
ordering).

### D6 — JSON-LD serializer

```jsonld
{
  "@context": {
    "cardano": "https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#",
    "rdfs":    "http://www.w3.org/2000/01/rdf-schema#",
    "":        "https://lambdasistemi.github.io/cardano-tx-tools/fixtures/<slug>#"
  },
  "@graph": [
    {
      "@id": ":alice",
      "@type": "cardano:Entity",
      "rdfs:label": "alice",
      "cardano:hasIdentifier": [
        { "@id": "_:alice_paymentKey" },
        { "@id": "_:alice_stakeKey" }
      ]
    },
    ...
  ]
}
```

Subject grouping, blank-node IDs preserved (`_:` prefix), no JSON-LD
framing. JSON-LD acceptance is set-equality on the parsed triple set,
not byte-equality (FR-007 + SC-003 in spec).

### D7 — `RulesLoadResult` extension (FR-010)

The loader's public type gains:

```haskell
data RulesLoadResult = RulesLoadResult
    { rulesOverlayTurtle :: !ByteString   -- existing (#48)
    , rulesWarnings      :: ![RulesLoadWarning]   -- existing (#48)
    , rulesEntities      :: ![EntityDecl]   -- NEW (this PR)
    }
```

`rulesEntities` carries the in-memory entity list — the same value the
loader's serializer consumes internally to produce `rulesOverlayTurtle`.
The extension is additive at the type level (Haskell record-update
syntax still works for callers constructing or destructuring the type).
The #48 `RulesLoadGoldenSpec` byte-diff continues to assert on
`rulesOverlayTurtle` and stays GREEN (SC-008 in spec).

### D8 — `tx-graph` CLI dispatch by flag presence

The flag-set dispatcher:

| `--rules` | `--tx` | `--utxo` | Behaviour |
|-----------|--------|----------|-----------|
| present   | absent | absent   | Overlay-only (#48 mode; back-compat) |
| present   | present | present | Joint graph (this PR's P1) |
| present   | present | absent  | Error: `UtxoRequired N` if tx has inputs; else body-only |
| absent    | present | optional | Body-only, no entity bnodes (raw-bytes for all) |
| absent    | absent | …        | Usage error (no input specified) |

The mode dispatch happens in `Main.hs` after `optparse-applicative`
parses the flag set. Each mode calls a specific top-level function and
serializes the result through `serialize EmitFormat`.

### D9 — Fixture serializer for executable smoke tests

The library byte-diff goldens use the in-memory `ConwayTx` directly from
the txbuild builders (`S<NN>_*.hs`). The executable smoke test, by
contrast, needs CBOR + UTxO JSON files on disk. A small test-only
serializer module materializes those files at the start of the smoke
test run:

```haskell
-- in test/, not in lib
materialiseFixture
    :: FixtureRegistryEntry
    -> FilePath
    -> IO (FilePath, FilePath)
materialiseFixture entry tmpDir = do
    let tx     = fixtureTx entry          -- ConwayTx from builder
        utxo   = fixtureResolvedUtxo entry
    BS.writeFile (tmpDir </> "tx.cbor")   (encodeConwayTxCbor tx)
    BSL.writeFile (tmpDir </> "utxo.json") (encodeResolvedUtxoJson utxo)
    pure (tmpDir </> "tx.cbor", tmpDir </> "utxo.json")
```

The `encodeConwayTxCbor` helper reuses ledger primitives (`EncCBOR`);
the `encodeResolvedUtxoJson` reuses `Cardano.Tx.Diff.Resolver`'s
existing aeson encoder. No new direct deps.

## Vertical slices

Each slice ships as exactly one bisect-safe commit. Brief contracts
live in [tasks.md](./tasks.md). Estimated line counts include both
production code and tests.

| # | Slice | Lines (est.) | Touches |
|---|-------|-------------|---------|
| 1 | `RulesLoadResult.rulesEntities` extension (FR-010, D7); existing `RulesLoadGoldenSpec` stays GREEN | ~40 LOC | `src/Cardano/Tx/Graph/Rules/Load.hs`, +tests/RulesLoadResultSpec test |
| 2 | Body emitter scaffold: `Cardano.Tx.Graph.Emit` module + `EmitError`, `EmittedGraph`, `EmitFormat` types + `emit` stub returning empty graph + smoke test asserting the stub compiles and returns an empty graph for an empty Tx | ~120 LOC | `src/Cardano/Tx/Graph/Emit.hs`, cabal, smoke test |
| 3 | `tx-graph` CLI extension: `--tx`, `--utxo`, `--out`, `--format` flags + flag-presence dispatcher (D8) + structured error rendering for missing files / decode failures | ~150 LOC | `app/tx-graph/Main.hs`, +exe-level smoke test |
| 4 | Credential lookup + raw-bytes-named bnode scheme (D3, D4) + unit tests for entity-named, raw-bytes-named, and shared-identity cases | ~120 LOC | `src/Cardano/Tx/Graph/Emit/Lookup.hs`, +unit tests |
| 5 | Body-section Turtle serializer skeleton (Tx + Input + Output + Address + Fee) + `Vocab.hs` IRI registry + `VocabTraceabilitySpec` + first fixture (02-alice-bob-ada) byte-diff GREEN against a freshly-regenerated `expected.ttl` | ~320 LOC | `src/Cardano/Tx/Graph/Emit/Project.hs`, `src/Cardano/Tx/Graph/Emit/Serialize/Turtle.hs`, `src/Cardano/Tx/Graph/Emit/Vocab.hs`, `test/Cardano/Tx/Graph/EmitGoldenSpec.hs`, `test/Cardano/Tx/Graph/Emit/VocabTraceabilitySpec.hs`, **regenerated** `test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.ttl` |
| 6 | Mint + asset-class leaves; fixture **03** GREEN (multi-asset transfer) — regenerated `expected.ttl` (fixture 10 moved to slice 10 per analyzer H2) | ~120 LOC | `Project.hs`, +1 regenerated `expected.ttl` |
| 7 | Script witness + redeemer leaves; fixtures **04, 05, 08** GREEN (mint-spend script overlap, withdrawal-script-stake, contingency disburse) — regenerated `expected.ttl` for all three | ~200 LOC | `Project.hs`, +3 regenerated `expected.ttl` |
| 8 | Stake/pool/drep cert leaves; fixtures **06, 07** GREEN (stake-pool delegation, vote delegation) — regenerated `expected.ttl` for both | ~150 LOC | `Project.hs`, +2 regenerated `expected.ttl` |
| 9 | MPFS facts + complex-multi-feature leaves; fixture **09** (mpfs-facts-request) GREEN — regenerated `expected.ttl` | ~80 LOC | `Project.hs`, +1 regenerated `expected.ttl` |
| 10 | Largest + governance-action fixtures **01, 10, 11** (amaru-treasury-swap hypothetical + governance treasury withdrawal + amaru-treasury-swap-real) GREEN — regenerated `expected.ttl` for all three; emits `Vote` + `TreasuryWithdrawal` governance-action leaves unique to fixture 10. By this slice the emitter must handle every leaf type used by any fixture; this slice is the last byte-diff slice (fixture 10 moved here from slice 6 per analyzer H2) | ~150 LOC | `Project.hs` (governance-action + any tail-end leaves), +3 regenerated `expected.ttl` |
| 11 | JSON-LD serializer + `JsonLdEquivalenceSpec` (parse JSON-LD, assert set-equal triple set to Turtle output) | ~200 LOC | `src/Cardano/Tx/Graph/Emit/Serialize/JsonLd.hs`, +unit tests |
| 12 | Reproducibility spec: `ReproducibilitySpec` runs emit twice on each fixture and asserts byte-equality | ~50 LOC | new test module |
| 13 | README + CHANGELOG + executable docs entries for the new flags | ~80 LOC | `README.md`, `CHANGELOG.md`, `docs/` if applicable |
| 14 | Drop gate.sh + mark PR ready | n/a | `chore: drop gate.sh` |

Slice S5 is the natural acceptance pivot — by the end of S5 the emitter
works end-to-end for one fixture with a regenerated joint `expected.ttl`
checked in. S6-S10 extend coverage to all 11 fixtures.

Each regen slice has a two-step internal shape:
1. Extend the emitter with whatever new projection cases the fixture(s)
   require (one or more new pattern matches in `Project.hs`).
2. Run the emitter on the fixture(s), inspect the candidate output
   against the artisan reference via `git show
   main:test/fixtures/.../expected.ttl`, accept the candidate by
   committing it as the new `expected.ttl`. The `EmitGoldenSpec` then
   pins the candidate.

The "candidate review" workflow is the orchestrator's responsibility
(per resolve-ticket invariants): the subagent produces the candidate,
the orchestrator compares it to the artisan reference and decides
accept-vs-iterate.

## Test strategy

- **`EmitGoldenSpec`**: a new test module under
  `test/Cardano/Tx/Graph/EmitGoldenSpec.hs`, registered in the existing
  `unit-tests` stanza. Iterates over the same 11-fixture registry. Per
  fixture: read the in-memory `ConwayTx` from the builder, read the
  resolved-UTxO map, load the rules file via `Cardano.Tx.Graph.Rules.Load`
  (returning the new `rulesEntities` field), call `emit`, serialize as
  Turtle, byte-diff against `expected.ttl`.

- **`JsonLdEquivalenceSpec`**: per fixture, generate both Turtle and
  JSON-LD outputs, parse both, assert set-equal triple sets. No
  byte-diff on JSON-LD (FR-007 + spec SC-003).

- **`ReproducibilitySpec`**: per fixture, call `emit` twice, assert
  byte-equality of the two outputs (FR-006 + spec SC-004).

- **`RawBytesBnodeSpec`**: a fixture with no rules.yaml entities; assert
  every credential bnode follows the `_:cred_<rolePrefix>_<bytes-prefix>`
  scheme.

- **`LookupTableSpec`**: unit tests for `buildLookup` covering
  entity-named, raw-bytes-named, and shared-identity cases (first-wins,
  second-entity-references-first's-bnode).

- **Executable smoke test**: a `tx-graph --tx <tx-cbor> --utxo
  <utxo-json> --rules <fixture>/rules.yaml --out -` invocation,
  asserting Turtle parseability of the output (no byte-diff; the
  library path covers byte-diff). Run for one fixture (02-alice-bob-ada,
  simplest) to keep the unit suite fast.

- **Local-vs-CI sandbox**: the executable smoke test follows the
  pattern established by #48 — read the `tx-graph` executable path
  from `TX_GRAPH_EXE` env var; the nix-check derivation passes it
  through (existing wiring from #48 commit 920a496).

- **`./gate.sh`**: extended at S3 only if the new exe surface needs
  new gate steps (likely just `cabal build` picks up the extended
  `executable tx-graph` stanza without new gate edits).

## Risks

- **R-1**: The mapping from projection leaves to vocab triples (D2 +
  research R2) is the heart of the cross-PR contract. If a leaf's
  predicate cluster is wrong, every fixture's byte-diff fails. Mitigate
  by drafting the leaf-to-triple table in research.md before S5 and
  cross-checking it against the artisan reference layouts for fixtures
  01, 02, and one cert-heavy fixture (06 or 07).
- **R-2**: The artisan `expected.ttl` files have at least one known
  identifier-shape error (01-amaru-treasury-swap's
  `_:treasuryComplianceStakeId` typed `StakeKey` where the loader
  emits `StakeScript`). The regenerated files correct this. Reviewers
  should be flagged at PR-body level: the diff vs the artisan file is
  expected, not a regression.
- **R-3**: The `usdm` asset name encoding in fixture 01 has an existing
  typo (per #48 plan R-5). #48's loader emits the **correct** ASCII
  encoding (`USDM` → `0x55534D4D`); this PR's regenerated joint
  `expected.ttl` will reference that same correct encoding. The artisan
  `expected.ttl` carried the typo (`0x55534446` = `USDF`) and is
  obsoleted by the regen.
- **R-4**: Determinism is fragile if the projection's underlying
  `Map`/`Set` iteration leaks (e.g., a fold over a `Map` in
  `conwayDiffProjection` may produce key-sorted output that the emitter
  relies on without realising). Mitigation: the `ReproducibilitySpec`
  (S12) runs the emitter twice and asserts byte-equality, catching
  any iteration-order leak before merge.
- **R-5**: The raw-bytes-bnode prefix length N (D4) needs empirical
  pinning across all 11 fixtures. If two distinct credentials in the
  same fixture happen to share an 8-byte prefix, the scheme breaks.
  Mitigation: research R3 enumerates every credential across all
  fixtures and computes the minimum collision-free N; the constant is
  pinned in code with a comment citing the research.
- **R-6**: The JSON-LD serializer might inadvertently produce a
  different triple set than the Turtle serializer (e.g., predicate
  cardinality mismatch, blank-node identity drift). Mitigation: the
  `JsonLdEquivalenceSpec` (S11) is the contract; if it fails on a
  fixture, the JSON-LD serializer is wrong, not the Turtle one
  (Turtle is the byte-diff anchor).
- **R-7**: The "candidate review" workflow for regenerating
  `expected.ttl` files is informal — the operator must visually inspect
  each new file against the artisan reference. A typo in the projection
  cluster mapping could silently produce a "wrong but reproducible"
  golden that future PRs lock into. Mitigation: the orchestrator
  reviews each regen slice carefully against the artisan reference at
  PR-review time; this is documented in spec.md (Clarifications →
  bootstrapping workflow).
- **R-8** *(analyzer M4)*: **kmaps#53 Phase A vocab term gap.** If a
  fixture's regen needs an IRI that the merged kmaps Phase A vocab
  does not declare (a leaf-cluster predicate research R2 missed),
  the emitter blocks at the affected slice. The 11 fixtures' leaf
  coverage is claimed within Phase A by design, but the artisan
  layouts were never run end-to-end through the kmaps schema.
  Mitigation: research R2's predicate enumeration is closed against
  the artisan reference layouts before T005 dispatches; if a gap
  surfaces at T005-T010, the worker escalates via Q-file to the
  orchestrator, who either files a kmaps PR + pauses the cross-PR
  contract or selects a fallback predicate (e.g.
  `cardano:hasMetadata` shape) with a documented follow-up to widen
  kmaps in a sibling PR.

## Pre-implementation prereqs

Before S1 starts, the orchestrator should confirm:

- **PRE-1**: Cross-PR contract decision (regenerate `expected.ttl`
  in-PR) — locked by Q-001 → A-001 (2026-05-20). No further
  confirmation needed.
- **PRE-2**: Loader API extension (FR-010 / D7) is acceptable — adding
  a new field to `RulesLoadResult` is non-disruptive. Confirm via
  analyzer-dispatch.
- **PRE-3**: Raw-bytes-bnode prefix length N (D4) — to be pinned in
  research.md R3 before S4 starts. Q-file if a fixture introduces a
  collision the proposed N=16 doesn't cover.
- **PRE-4**: `tx-graph` CLI flag dispatch (D8) — three modes by flag
  presence. Confirm via analyzer-dispatch that the mode matrix is the
  right surface (the alternative is sub-commands like `tx-graph emit
  --…`).
- **PRE-5**: Per-fixture regen as separate slices (vs one bulk regen)
  — locked by A-001 (per-fixture for bisect-safety). No further
  confirmation needed.

## Sequencing tie-in to epic #46

After #58 lands, the epic resequences as:

- Wave 1 (closed): #45 harness; #56 #47-deferral.
- Wave 2 (in flight, this PR closes): **#48 rules loader (merged 2026-05-20)**;
  **#58 body emitter (this PR)**.
- Wave 3 (next): #49 reasoner, #50 blueprint decode, #51 SPARQL views.
- Wave 4: #52 diff-as-view, #53 executable consolidation,
  #54 migration docs.

The orchestrator should update the parent #46 issue body after this
PR merges so downstream waves see the new sequencing.

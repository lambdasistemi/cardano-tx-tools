# Implementation Plan: Rules loader — Turtle + YAML sugar + `owl:imports`

**Feature**: `Cardano.Tx.Graph.Rules.Load`
**Branch**: `48-rules-loader`
**Spec**: [spec.md](./spec.md)
**Research**: [research.md](./research.md)

## Constitution gate

- **One-Way Dependency** (Principle I): `Cardano.Tx.Graph.Rules.Load`
  imports only from `Cardano.Tx.*` and from the existing dep closure.
  No new reverse arrow into `cardano-node-clients`.
- **Module Namespace** (Principle II): The new module sits under
  `Cardano.Tx.Graph.Rules.Load` — a fresh `Cardano.Tx.Graph.*` subtree
  reserved for the graph layer (epic #46). Wave-2/3 modules
  (`Cardano.Tx.Graph.Emit`, `Cardano.Tx.Graph.Rules.Apply`, …) will
  sit alongside as siblings.
- **Conway-Only** (Principle III): N/A — this PR has no era-specific
  surface.
- **Hackage-Ready** (Principle IV): Haddock on every exported function;
  module header in `{- | … -}` form; `cabal check` clean. The new
  module is added to `exposed-modules` of the existing `library`
  stanza in `cardano-tx-tools.cabal`.
- **Strict Warnings** (Principle V): no escape hatches; the module
  inherits the `warnings` common stanza.
- **Default-Offline** (Principle VI): imports resolved on disk only;
  no HTTP, no `file://` at non-local URIs.
- **TDD With Vertical Bisect-Safe Commits** (Principle VII): every
  slice in this plan is one bisect-safe commit, with RED+GREEN folded
  in. The TDD shape is captured in tasks.md per slice.

## High-level architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│  app/tx-graph/Main.hs   (new executable)                         │
│    optparse: --rules <file>                                      │
│    Cardano.Tx.Graph.Rules.Load.loadRulesFile path                │
│      ↳ on Right → BS.hPut stdout (overlayTurtle result)          │
│      ↳ on Left  → hPutStrLn stderr (renderError err), exit 1     │
└──────────────────────────────────────────────────────────────────┘
                            ▲
                            │ depends
                            │
┌───────────────────────────┴──────────────────────────────────────┐
│  src/Cardano/Tx/Graph/Rules/Load.hs                              │
│    public:                                                       │
│      data RulesLoadError = …                                     │
│      data RulesLoadWarning = …                                   │
│      data RulesLoadResult                                        │
│      loadRulesFile :: FilePath -> IO (Either RulesLoadError      │
│                                              RulesLoadResult)    │
│    private (other-modules under Cardano.Tx.Graph.Rules.Load.*):  │
│      Parse.Turtle     -- structural Turtle reader → [Triple]     │
│      Parse.Yaml       -- YAML sugar reader → [EntityDecl] +      │
│                                               imports + …        │
│      Resolve.Imports  -- DAG walker + cycle detection            │
│      Emit.Overlay     -- canonical-form Turtle serializer        │
│      Naming           -- (leafType, bytes) → blank-node name     │
│      Bech32           -- address/pool/drep bech32 → leaf bytes   │
└──────────────────────────────────────────────────────────────────┘
```

The shape of the loader pipeline:

```haskell
loadRulesFile path = do
    1. dispatch by extension (.ttl / .yaml / .yml)
    2. parse the file into a normalized intermediate
       data NormalizedFile = NormalizedFile
         { nfSelf    :: FilePath          -- absolute resolved path
         , nfImports :: [FilePath]        -- resolved relative to nfSelf's dir
         , nfTriples :: [Triple]          -- already in canonical form
         , nfEntities :: [EntityDecl]     -- structured handle for warnings
         , nfWarnings :: [RulesLoadWarning]
         }
    3. resolve imports DFS with cycle detection
    4. merge triples in source order (first declaration wins per URI)
    5. validate every cardano:Entity has ≥ 1 cardano:hasIdentifier
    6. compute deterministic blank-node names for identifiers
    7. serialize entity overlay to canonical Turtle bytes
    8. return RulesLoadResult { triples, overlayTurtle, warnings }
```

## Key design decisions

### D1 — No new RDF library

In-house structural parser bounded by FR-003's Turtle subset. Pulls
no `swish`/`rdf4h`/`rapper` into the dep closure. Precedent:
[`specs/033-rewrite-redesign-harness/research.md` D5](../033-rewrite-redesign-harness/research.md).
See [research.md](./research.md#r1) for the full
rationale, alternatives considered, and the in-scope/out-of-scope
Turtle subset.

### D2 — Deterministic blank-node naming

For every (`leafType`, `bytesHex`) pair extracted from the rules
file's entity declarations:

1. Collect all entities that produce this pair (in YAML/source order).
2. The bnode name is `_:<entitySlug>_<roleSuffix>` where
   `entitySlug` = the **first** entity's `name` after running
   `slugify` (lowercased, `[^a-z0-9]` → `_`, collapse repeated `_`,
   trim leading/trailing `_`), and `roleSuffix` = the leafType with
   **only** the first character lowercased (other characters preserved
   verbatim — there is no internal camel-case lowering). The roleSuffix
   for every leafType used by the 11 fixtures is pinned:

   The **same `entitySlug` is also the entity's IRI local part**:
   the entity declaration emits `:<entitySlug> a cardano:Entity ;` and
   each `cardano:hasIdentifier` references `_:<entitySlug>_<roleSuffix>`
   from the same slug. The original entity `name:` is preserved in
   `rdfs:label`. Resolution per Q-001 (Option A — slug-everywhere): see
   `/tmp/epic-046/tx-48/answers/A-001-entity-iri-slug-application.md`.


   | leafType        | roleSuffix      |
   |-----------------|-----------------|
   | `PaymentKey`    | `paymentKey`    |
   | `PaymentScript` | `paymentScript` |
   | `StakeKey`      | `stakeKey`      |
   | `StakeScript`   | `stakeScript`   |
   | `AssetClass`    | `assetClass`    |
   | `Policy`        | `policy`        |
   | `PoolId`        | `poolId`        |
   | `DRepKey`       | `dRepKey`       |
   | `DRepScript`    | `dRepScript`    |
3. Every subsequent entity that produces the same pair references the
   *same* bnode name in its `cardano:hasIdentifier` triple — the OWL
   hasKey-driven identity sharing.

Worked example for `01-amaru-treasury-swap/rules.yaml`:

| Source decl (order) | Produces                                | Bnode name |
|---|---|---|
| `amaru-treasury.network_compliance` (`from-address`) | (PaymentScript, `32201dc1…aa10baa0d`) | `_:amaru_treasury_network_compliance_paymentScript` |
| ″ | (StakeKey, `9100eb83…42ea906`) | `_:amaru_treasury_network_compliance_stakeKey` |
| `amaru.swap-order` (`from-address`) | (PaymentScript, `fa6a58bb…3c8f3077`) | `_:amaru_swap_order_paymentScript` |
| ″ | (StakeKey, same `9100eb83…42ea906`) | reuses `_:amaru_treasury_network_compliance_stakeKey` |
| `amaru.swap.v2` (`script`) | (PaymentScript, same `fa6a58bb…3c8f3077`) | reuses `_:amaru_swap_order_paymentScript` |
| `amaru.network-wallet` (`from-address`) | (PaymentKey, `…`) + (StakeKey, `…`) | `_:amaru_network_wallet_paymentKey`, `_:amaru_network_wallet_stakeKey` |
| `usdm` (`asset`) | (AssetClass, policy+name) | `_:usdm_assetClass` |

This deviates from the existing `expected.ttl`'s artisan names
(`_:treasuryComplianceId`, `_:swapOrderPaymentId`, etc.), but the
spec's clarification records that the carve-out `expected.entities.ttl`
is *regenerated* against this scheme. The body emitter (#58) will
reference these same names in one pass.

See [research.md R2](./research.md#r2) for alternative naming schemes
considered (hash-based, sequential, slugify-only) and why source-order
+ entity-slug + role-suffix wins on byte-stable output + reviewer
readability.

### D3 — `from-address` decomposition reuses existing helpers

The YAML compiler reuses `Cardano.Tx.Diff.decodeBech32Address` (already
in the dep tree) to decode each `from-address: <bech32>` into a
`Cardano.Ledger.Address.Addr`, then classifies the payment and stake
credentials into `(PaymentKey | PaymentScript)` and
`(StakeKey | StakeScript | <none>)` via inspection of the
`Cardano.Ledger.Credential.Credential` constructor. Enterprise
addresses (no stake) produce only the payment identifier. Byron
bootstrap addresses are rejected with a structured error (the
constitution targets Conway-only).

For `pool: <bech32>` and `drep: <CIP-129 bech32>` (one fixture each,
in 06 and 07), the decoder is added locally to the loader's `Bech32`
internal module. CIP-129 encodes the credential kind in the prefix
byte; the loader decodes that to `DRepKey` vs `DRepScript`.

### D4 — Canonical Turtle serializer

The serializer emits in this exact form (lines, in order):

```turtle
@prefix cardano: <https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#> .
@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .
@prefix :        <https://lambdasistemi.github.io/cardano-tx-tools/fixtures/<slug>#> .

#
# Operator-declared entities (from rules.yaml).
#

:<entityIRI> a cardano:Entity ;
  rdfs:label "<entity-name-original>" ;
  cardano:hasIdentifier _:<bnode1> ;
  cardano:hasIdentifier _:<bnode2> .

_:<bnode1> a cardano:Identifier ;
  cardano:leafType "<LeafType>" ;
  cardano:bytesHex "<hex>" .

_:<bnode2> a cardano:Identifier ;
  cardano:leafType "<LeafType>" ;
  cardano:bytesHex "<hex>" .

:<entityIRI2> a cardano:Entity ;
  rdfs:label "<…>" ;
  cardano:hasIdentifier _:<bnodeN> .

…
```

Rules:

- One blank line between every entity block.
- Entity block: `:slug a cardano:Entity ; rdfs:label "…" ;
  cardano:hasIdentifier _:bnodeK .` — each identifier on its own
  indented line ending in `;`; final identifier line ends in `.`.
- Each `_:bnodeK` declaration block: `_:bnodeK a cardano:Identifier ;
  cardano:leafType "…" ; cardano:bytesHex "…" .` — three lines,
  indented two spaces; final terminator `.`.
- After every entity's identifier blocks (in the order they appear in
  the entity's `cardano:hasIdentifier` list, but each identifier is
  emitted **at most once**, on first occurrence in document order),
  one blank line, then the next entity.
- Shared-identity case: the identifier block is emitted once at the
  first entity that references it; later entities just emit
  `cardano:hasIdentifier _:<bnode>` referencing the prior block.
- The fixture base IRI in the third `@prefix` is derived from the
  fixture directory name; the loader is parametrized on this prefix
  (default `https://lambdasistemi.github.io/cardano-tx-tools/fixtures/<derived-from-input-file>`).
  For the `tx-graph --rules` CLI, the prefix is derived from the
  input file's parent directory name. (The fixture's existing
  `expected.ttl` uses this convention — `02-alice-bob-ada` → `…/fixtures/02-alice-bob-ada#`.)
- Trailing newline at end-of-file.

This is the byte-stable serializer the cross-PR contract anchors on.
See [research.md R3](./research.md#r3) for the byte-shape rationale
(why `;` continuation, why two-space indent, why fixed prefix order).

### D5 — Error type is exhaustive

A flat sum `data RulesLoadError = …` with explicit variants per
failure mode (see spec FR-018 / Key Entities). The `Show` instance
produces a single-line human-readable message; the constructor stays
inspectable so the CLI and a future LSP can render structured form.

### D6 — Imports DAG walker with cycle detection

DFS with a colour-stamped visit map: `White` (unseen), `Grey`
(currently in the DFS stack — cycle detected when revisited),
`Black` (fully processed — diamond-imports merge cleanly because a
Black node is loaded once and its triples already merged in).

The DFS produces a topologically sorted load order; triples merge in
*reverse* topological order (deepest imports first) so a parent
file's declarations can override a child's by virtue of the
"first-declaration wins" rule applied in source order during the
final merge.

### D7 — `tx-graph` executable layout

A new `executable tx-graph` cabal stanza, app/tx-graph/Main.hs,
optparse-applicative for the CLI. The `--rules <file>` flag is the
only consumed flag in this PR; the `--utxo`, `--out`, `--tx`,
`--format` flags are reserved (rejected with "deferred to #58" usage
text if a reviewer tries them). This keeps the executable surface
forward-compatible without committing to #58's flag shape.

## Vertical slices

Each slice ships as exactly one bisect-safe commit. Brief contracts
live in [tasks.md](./tasks.md).

| # | Slice | Lines (est.) | Touches |
|---|-------|-------------|---------|
| 1 | Module skeleton + types + cabal expose + smoke unit test that the empty loader exists and returns `Left UnsupportedExtension` for `.foo` | ~150 LOC | `src/Cardano/Tx/Graph/Rules/Load.hs`, cabal, `test/Cardano/Tx/Graph/Rules/LoadSmokeSpec.hs` |
| 2 | YAML parser for `entities:` with `from-address` / `script` / `asset` shapes + slugify + bech32-address decomposition + identifier extraction (no serializer yet) | ~250 LOC | `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs`, `src/Cardano/Tx/Graph/Rules/Load/Bech32.hs`, +unit tests |
| 3 | Canonical Turtle serializer (entity overlay only) + deterministic naming + carve out & byte-diff fixtures **02, 03, 05, 06, 07, 08, 10** (7 fixtures that use only basic entity shapes) | ~350 LOC | overlay emitter, `RulesLoadGoldenSpec`, 7 `expected.entities.ttl` |
| 4 | YAML `keys: + bytes:` (compound-key entity from fixture 04) + carve out 04 | ~50 LOC | YAML compiler, expected.entities.ttl 04, +pool/drep bech32 if needed for 06/07 (likely folds into S3) |
| 5 | YAML `pool:` (PoolId leafType, decoded from pool1 bech32) + `drep:` (DRepKey/Script, CIP-129) — only if not already done in S3/S4 | ~80 LOC | bech32 decoder, carve outs for 06/07 |
| 6 | Shared-identity case + `blueprints:` validation + `collapse:` pass-through + carve out **01, 09, 11** (complex fixtures) — all 11 fixtures pass byte-diff | ~150 LOC | YAML compiler, expected.entities.ttl 01, 09, 11 |
| 7 | Turtle parser (structural subset per FR-003) + round-trip unit test (US2) | ~200 LOC | `src/Cardano/Tx/Graph/Rules/Load/Parse/Turtle.hs`, +unit tests |
| 8 | Imports composition (`owl:imports` in Turtle; `imports:` in YAML; DFS resolver; diamond) — US3 | ~150 LOC | `src/Cardano/Tx/Graph/Rules/Load/Resolve/Imports.hs`, +unit tests |
| 9 | Cycle detection + structured `RulesImportCycle` error — US4 | ~50 LOC | resolver, +unit tests |
| 10 | Validation errors with file+line (zero-id, bad bech32, duplicate-in-file, blueprint-refs-unknown-script, parser errors) — US5 | ~100 LOC | error type, parsers, +unit tests |
| 11 | Cross-file duplicate-entity warning — US6 | ~50 LOC | resolver, +unit tests |
| 12 | `app/tx-graph/Main.hs` + cabal stanza + `--rules` flag wiring + executable-level smoke test (US7) | ~100 LOC | new app, cabal, smoke test invoking the binary |
| 13 | Drop gate.sh + mark PR ready | n/a | `chore: drop gate.sh` |

The natural acceptance pivot is **S3** (P1 byte-diff for 7 simple
fixtures) and **S6** (all 11 fixtures green). S7–S11 close US2–US6;
S12 closes US7.

**Plan vs tasks slice mapping** (post-analyzer C6): the tasks.md
breakdown collapses pool/drep (plan S5) directly into **T003** (which
carves fixtures 06 + 07 alongside 02/03/05/08/10), and compound-key
(plan S4) into **T004**. Plan slices S6 onward map 1:1 to tasks
T005..T013 with one offset (plan S6 = tasks T005, plan S7 = tasks T006,
etc.).

**Post-Q-002 sequencing addendum** (Option B, constitution sweep
in-scope): three chore slices land at the head of the implementation
sequence, ahead of T001 — **T001b** (PvP upper bounds across every
dep), **T001c** (gate `-Werror` behind a cabal `werror` flag), then
**T001a** (extend `gate.sh` with `cabal check` + `cabal haddock`).
After T001a, T001 (module scaffold) proceeds. See research.md R13
for the rationale. Total slice count: 13 → **15 implementation +
chore slices** + 3 orchestrator-owned (T000, T000a, T012, T013).

The plan table above is kept as the high-level decomposition;
[tasks.md](./tasks.md) is the authoritative per-commit list a subagent
runs against.

## Test strategy

- **`RulesLoadGoldenSpec`**: a new test module under `test/Cardano/Tx/Graph/Rules/LoadGoldenSpec.hs`,
  registered in `cardano-tx-tools.cabal`'s `unit-tests` stanza, that
  iterates over the same 11-fixture registry the existing
  `RewriteRedesignGoldenSpec` uses. Per fixture: read `rules.yaml`,
  call `loadRulesFile`, compare the result's `overlayTurtle`
  byte-for-byte to `expected.entities.ttl`.

- **Per-slice unit tests** for parsers, naming, error messages,
  cycle detection, etc. — small focused inputs constructed in-line so
  the failure modes are easy to read.

- **Executable smoke test**: a `tx-graph --rules <fixture>/rules.yaml |
  diff - <fixture>/expected.entities.ttl` shell invocation wrapped in
  an `Hspec` `it` block, run only for one fixture to keep the unit
  suite fast.

- **`./gate.sh`**: extended only if needed (S12 adds the executable;
  if `just build` already picks up the new exe stanza, no gate edit
  is needed).

## Risks

- **R-1**: The deterministic naming algorithm I chose (D2) is one of
  several plausible schemes. The orchestrator may prefer a different
  algorithm before the carve-out files are committed (S3). Mitigation:
  raise as a Q-file *before* S3 begins, since changing the algorithm
  after the carve-outs land is a large rewrite.
- **R-2**: `from-address` decomposition needs to handle every Conway
  address class (payment-key+stake-key, payment-key+stake-script,
  payment-script+stake-key, payment-script+stake-script, enterprise
  payment-key, enterprise payment-script). The existing helpers cover
  this but the test surface needs all six combinations to keep S2
  bisect-safe.
- **R-3**: The 11 fixtures include one (07-vote-delegation) where
  the `drep:` bech32 string looks short (`drep1y2v5h0g4qjqj9p6h9rp3z5lyqz3xczvqj5x3z7c7gj7nf2c52u7m3`,
  60 chars) — short by CIP-129 standards. May actually fail bech32
  validation. Mitigation: in S5, if the string fails to decode, raise
  a Q-file with the analyzer to fix the fixture's `rules.yaml` (a
  small `chore:` slice).
- **R-4**: The `tx-graph` executable name might be reserved by
  another (future) ticket. Mitigation: confirm with the orchestrator
  via Q-file before S12; the alternative name `tx-rules` or `tx-rdf`
  is acceptable.
- **R-5**: The `usdm` asset name encoding in
  `01-amaru-treasury-swap/expected.ttl` is `…55534446` (ASCII
  `"USDF"`), not `"USDM"` (`…55534D4D`). This appears to be an
  existing fixture typo; the loader will emit the *correct*
  `…55534D4D` and the carve-out `expected.entities.ttl` will be
  authored to match. The existing `expected.ttl` becomes the body
  emitter's #58 reference but its bytes for that asset will be
  *re-encoded* there, not at this PR. (Noted in spec
  clarifications; tracked here for the carve-out author.)

## Pre-implementation prereqs

Before S1 starts, the orchestrator should confirm:

- **PRE-1**: Naming algorithm (D2) is acceptable. The carve-out
  authoring depends on this. (Raise as Q-file before S3 begins.)
- **PRE-2**: Executable name `tx-graph` (D7) is acceptable.
- **PRE-3**: The new `Cardano.Tx.Graph.*` subtree is the right place
  for the loader (epic-level architectural decision).
- **PRE-4**: The cross-PR contract is: this PR ships the *loader* +
  the *executable* + the 11 `expected.entities.ttl` carve-outs; #58
  ships the body emitter and regenerates the joint `expected.ttl`.
  No edits to the existing `expected.ttl` files in this PR.

## Sequencing tie-in to epic #46

After #48 lands, the epic resequences as:

- Wave 1 (closed): #45 harness; #56 #47-deferral.
- Wave 2 (closed by this PR): **#48 rules loader (this PR)**.
- Wave 3 (next): #58 body emitter (depends on this PR's
  `expected.entities.ttl` + the existing `Tx.hs`/`rules.yaml` set).
- Wave 4: #49 reasoner, #50 blueprint, #51 views.

The orchestrator should update the parent #46 issue body after this
PR merges so downstream waves see the new sequencing.

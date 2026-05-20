# Research — Body emitter (058)

## R1 — No new RDF library

**Decision**: Author the Turtle and JSON-LD serializers in-house. No
new Haskell RDF library (`rdf4h`, `swish`, `json-ld`) and no shell-out
to external tools.

**Rationale**:

- Inherits #48's precedent ([`specs/048-rules-loader/research.md` R1](../048-rules-loader/research.md))
  — the in-house Turtle serializer is already in the dep closure and
  produces canonical byte-stable output proven by 11/11 #48 goldens.
- JSON-LD output is bounded to `@context` + `@graph` + subject-grouped
  triples (D6 in plan.md). No JSON-LD framing, no RDF Dataset
  Normalization (c14n), no JSON-LD `@type` polymorphism — all out of
  scope for SC-003 (set-equality, not byte-equality on JSON-LD).
- DSL stress-test policy (CLAUDE.md): try in-house first; only file an
  upstream issue + skip cleanly if a needed combinator is missing.

**Alternatives**:

- **`rdf4h`** — rejected — transitive closure cost, not needed for
  the bounded subset.
- **`swish`** — rejected — same as #48; bundles SPARQL + reasoning we
  do not use.
- **`json-ld` (Hackage)** — rejected — heavy framing + c14n features;
  the JSON-LD acceptance is set-equality only.
- **`aeson` for JSON-LD output** — accepted (already in dep closure
  via existing modules). The serializer constructs `Aeson.Value`
  manually and renders via `Aeson.encode`. No new dep.

**JSON-LD subset in scope**:

- `@context` keyword (multi-prefix map).
- `@graph` keyword (top-level array of subject groups).
- `@id` and `@type` on subject nodes.
- Predicate keys named via the compact-IRI form (`cardano:hasInput`).
- Blank-node references as `{"@id": "_:<name>"}` objects inside arrays.
- Integer literals serialized as JSON numbers; string literals as JSON
  strings (no language tags, no datatype suffixes).

**JSON-LD subset out of scope** (the serializer never emits these):

- `@base`, `@vocab`, `@language` keywords.
- Typed literals (`{"@value": …, "@type": …}`) — out of scope for the
  Conway leaves enumerated in R2.
- JSON-LD framing.
- RDF Dataset Normalization (c14n). Per SC-003: set-equality on the
  parsed triple set, not byte-equality on the JSON-LD output.

## R2 — Projection-leaf → vocab-triple mapping

**Decision**: One row per Conway-projection leaf type, mapping to the
triple cluster the emitter produces. Each row is the artisan reference
layout (the layout merged in #45) crossed with #48's deterministic
bnode naming.

The table below enumerates every leaf shape used by at least one of
the 11 rewrite-redesign fixtures. The "Source fixture(s)" column is
the trace from the artisan `expected.ttl`. Predicates are kmaps Phase A
`cardano:` terms unless noted.

| Leaf shape | Triple cluster | Source fixture(s) |
|------------|----------------|-------------------|
| `ConwayTxBody` (root) | `_:tx a cardano:Transaction ; cardano:hasInput _:input_K ; cardano:hasOutput _:output_K ; cardano:hasFee N .` (cert/mint/withdrawal/vote predicates added when present) | every fixture |
| `ConwayTxInValue` (input) | `_:input_K a cardano:Input ; cardano:resolvedTo _:resolvedInput_K .` | every fixture |
| Resolved-UTxO entry (the input's target output) | `_:resolvedInput_K a cardano:Output ; cardano:atAddress _:addr_for_K .` | every fixture |
| `ConwayOutputValue` (body output) | `_:output_K a cardano:Output ; cardano:atAddress _:addr_for_K .` (+ `cardano:withMint _:mint_K` when an output carries a mint asset) | every fixture |
| `ConwayAddressValue` | `_:addr_K a cardano:Address ; cardano:bech32 "…" ; cardano:hasPaymentCredential _:cred_payment_K ; cardano:hasStakeCredential _:cred_stake_K .` (stake credential omitted for enterprise addresses) | every fixture |
| `Credential PaymentKey` (payment-key hash) | `_:cred_payment_K a cardano:PaymentCredential ; cardano:hasIdentifier _:<bnode-name> .` where `<bnode-name>` is the entity bnode (lookup hit) or the raw-bytes bnode (lookup miss) | every fixture |
| `Credential PaymentScript` (script hash for payment) | `_:cred_payment_K a cardano:PaymentCredential ; cardano:hasIdentifier _:<bnode-name> .` (same shape as `PaymentKey`; the identifier's `cardano:leafType` differentiates) | 01, 04, 05, 08, 09, 10, 11 |
| `Credential StakeKey` | `_:cred_stake_K a cardano:StakeCredential ; cardano:hasIdentifier _:<bnode-name> .` | 02, 03, 06, 09 |
| `Credential StakeScript` | `_:cred_stake_K a cardano:StakeCredential ; cardano:hasIdentifier _:<bnode-name> .` (same shape; differentiated by leafType) | 01, 04, 05, 11 |
| `ConwayCertValue StakeRegistration` | `_:cert_K a cardano:StakeRegistration ; cardano:onCredential _:cred_K .` | 06 (delegation precedes registration) |
| `ConwayCertValue StakeDelegation` | `_:cert_K a cardano:StakeDelegation ; cardano:onCredential _:cred_K ; cardano:toPool _:pool_K .` | 06 |
| `ConwayCertValue VoteDelegation` | `_:cert_K a cardano:VoteDelegation ; cardano:onCredential _:cred_K ; cardano:toDRep _:drep_K .` | 07 |
| `PoolId` (target of stake-delegation cert) | `_:pool_K a cardano:Pool ; cardano:hasIdentifier _:<bnode-name> .` | 06 |
| `DRep` (target of vote-delegation cert) | `_:drep_K a cardano:DRep ; cardano:hasIdentifier _:<bnode-name> .` | 07 |
| `ConwayMintValue` (per-policy mint) | `_:mint_K a cardano:Mint ; cardano:hasPolicy _:policy_K ; cardano:hasAsset _:asset_K .` (one cluster per mint asset; same policy may appear under multiple assets) | 03, 09, 10 |
| `Policy` (mint policy identifier) | `_:policy_K a cardano:Policy ; cardano:hasIdentifier _:<bnode-name> .` | 03, 09, 10 |
| `AssetClass` (policy + asset name) | `_:asset_K a cardano:Asset ; cardano:hasIdentifier _:<bnode-name> .` (the AssetClass-typed identifier's bytesHex is `policy ++ hex(ascii(name))` per #48) | 01, 03, 09, 10, 11 |
| `Withdrawal` | `_:withdrawal_K a cardano:Withdrawal ; cardano:onCredential _:cred_stake_K ; cardano:withAmount N .` | 05 |
| `ConwayDatumHash` (output reference) | `_:output_K cardano:withDatumHash "…" .` (literal hex string) | 09, 11 |
| `ConwayDatumInline` (output inline) | `_:output_K cardano:withInlineDatum "…" .` (literal hex string; #50 will replace with typed triples) | 11 |
| `ScriptRef` (output script reference) | `_:output_K cardano:withScriptRef "…" .` (literal hex string) | 11 |
| `Redeemer` (witness redeemer) | `_:redeemer_K a cardano:Redeemer ; cardano:purpose "…" ; cardano:asPayload "…" .` | 04, 05, 08, 11 |
| `Vote` (governance vote) | `_:vote_K a cardano:Vote ; cardano:onAction _:action_K ; cardano:byVoter _:cred_K ; cardano:withChoice "…" .` | 10 |
| `TreasuryWithdrawal` (governance action) | `_:action_K a cardano:TreasuryWithdrawal ; cardano:toAccount _:account_K ; cardano:withAmount N .` | 10 |

**Caveats**:

- The cluster shapes above are the **artisan reference layout** (from
  the `expected.ttl` files merged in #45). #58's job is to regenerate
  byte-equivalent layout under the new bnode naming. If a regen reveals
  the artisan layout was internally inconsistent for a leaf (e.g.,
  fixture 01's `_:treasuryComplianceStakeId` typed `StakeKey` where the
  loader emits `StakeScript`), the regen file uses the **correct**
  shape and the artisan file is obsoleted.
- Predicates not on the kmaps#53 Phase A vocab (e.g., new vocab terms
  needed for a leaf that the artisan files never had) trigger a
  research-time decision: either request the term upstream (kmaps PR)
  or use a fallback `cardano:hasMetadata` shape until the upstream lands.
  The 11 fixtures' leaf coverage is already within Phase A by design.
- The "K" suffix in bnode names above is a positional index inside the
  emitter (e.g., `_:input1`, `_:input2`, ...). Concrete index choice
  (per-leaf-class numbering vs global sequential vs hash-derived) is a
  serializer detail pinned in R4.

**Open enumeration items (deferred to per-slice tasks)**:

- The full set of `cardano:` vocab terms used by the table above. Any
  term not already declared in kmaps#53 is a research-time Q-file.
- The `purpose` enum for `Redeemer` (Spend / Mint / Cert / Reward /
  Vote / Propose) — kmaps#53 declares `Spend`, `Mint`, `Cert`,
  `Reward`; `Vote` and `Propose` need confirmation against the merged
  vocab.

## R3 — Raw-bytes-bnode prefix length N

**Decision**: Pin `N = 16` (eight bytes of hex) as the default
collision-free prefix length for raw-bytes-named bnodes (FR-005 +
plan D4). Confirm empirically across all 11 fixtures' credential
census during T004 (the lookup-table slice).

**Methodology**:

1. For each fixture, enumerate every credential `(LeafType, bytesHex)`
   pair that appears in the artisan or regenerated `expected.ttl`.
2. Project each pair to `(rolePrefix, bytes[:N])` for `N = 8, 12, 16,
   20, 24`.
3. The minimum `N` such that no two distinct pairs collide on the
   projection is the **collision floor**. Add +4 chars safety margin to
   pick the final `N`.

**Conservative starting point**:

- Sample run on fixture 02 (`02-alice-bob-ada`):
  - alice payment: `(PaymentKey, 601f58e4…)` (artisan) /
    `(PaymentKey, 8bd03209…)` (loader-derived)
  - alice stake: `(StakeKey, 80226c84…)` /
    `(StakeKey, 4c7889c6…)`
  - bob payment: `(PaymentKey, 2841f2c6…)`
  - bob stake: `(StakeKey, e54e05af…)`
  - First 8 hex chars of the loader-derived bytes are pairwise
    unique within the fixture. `N = 8` is **collision-free** for
    fixture 02 alone, but with N=8 the cross-fixture collision risk
    is realistic (e.g., another fixture's credential could start with
    `8bd03209…`).
- `N = 16` (default) gives ≈ 64 bits of effective namespace per
  `(rolePrefix, bytes-prefix)` tuple; the probability of a
  cross-fixture collision across the ≤ 100 credentials we deal with
  is vanishingly small.

**If a collision is detected during T004**: bump `N` to the next
safe value (20 → 24 → 32 → full 56 chars). The cost of bumping is one
constant change + the regen of every fixture's `expected.ttl`. To
avoid that rework cost, T004 pins `N = 16` upfront and asserts the
collision-free property by construction (a unit test enumerates all
pairs and asserts the projection is injective).

## R4 — Joint Turtle byte-shape (section blocking + comment conventions)

**Decision**: The joint `expected.ttl` reproduces the artisan
section-blocked layout:

```
<prefix declarations>

<#-comment "Operator-declared entities (from rules.yaml).">

<entity overlay block — verbatim from #48's expected.entities.ttl>

<#-comment "Transaction body.">

<_:tx subject block>

<#-comment "Input N — <description>.">
<_:inputN subject block>
<_:resolvedInputN subject block>
...

<#-comment "Output N — <description>.">
<_:outputN subject block>
...

<#-comment "Address decompositions — payment + stake credential per leaf.">

<address subject blocks, each followed by its credential decomposition>
```

Rules (rules in addition to #48 D4):

- **Prefix declarations**: same as #48 (cardano:, rdfs:, fixture-local
  base prefix). No new prefixes are introduced by the body section.
- **Section headers**: 3-line comment blocks `# / # text / #` with a
  preceding blank line and a trailing blank line.
- **Subject blocks**: one subject per block, predicates each on their
  own line indented two spaces, terminator `.` on the last predicate.
- **Inter-subject spacing**: one blank line between every subject
  block in the body section.
- **Per-input/-output description text**: the comment description text
  (e.g. `# Input — alice's 100 ADA UTxO.`) is **NOT emitted** by the
  emitter. The artisan fixtures carried descriptive comments authored
  by hand; the regenerated files emit a uniform `# Input N` /
  `# Output N` form. Per-fixture narrative content (story arcs,
  invariants, cross-references) migrates to a new `NOTES.md` markdown
  file per fixture in T001a (Q-003 → A-003 discovery section below);
  the structured-YAML `expected.txt` keeps its #51 cli-tree contract
  unchanged.
- **Address decompositions**: emitted once per address, regardless of
  how many inputs/outputs reference the address. The first occurrence
  wins; later inputs/outputs reference the same bnode.
- **Trailing newline**: at end-of-file.

**Open**: The artisan files don't strictly conform to one
section-blocking convention across all 11 fixtures (e.g., 01 has more
elaborate `#-block` headers than 02). The regenerated files emit the
**uniform** version above; the artisan elaborations are obsoleted as
authoring artifacts. The orchestrator confirms this at PR-review time
(see plan R-7).

**Q-003 discovery (2026-05-20)**: An audit of comment-line density per
fixture showed substantial design narrative buried inside the artisan
`expected.ttl` files — fixture 04 alone carries 111 comment-lines of
story arc + invariant explanations + ticket cross-references. The
artisan content cannot fit `expected.txt`'s structured-YAML format
without breaking #51's cli-tree contract. Per A-003 the narrative
migrates to a new per-fixture `NOTES.md` markdown file. The audit
breakdown:

```
01-amaru-treasury-swap:           72  comment-lines
02-alice-bob-ada:                 18
03-multi-asset-transfer:          28
04-mint-spend-script-overlap:    111
05-withdrawal-script-stake:       44
06-stake-pool-delegation:         45
07-vote-delegation:               50
08-contingency-disburse:          69
09-mpfs-facts-request:            35
11-amaru-treasury-swap-real:      40
```

T001a is the migration slice: 11 new `NOTES.md` files authored before
any emitter code touches the fixtures. Rationale: pure machine output
from the emitter side, pure documentation in `NOTES.md`, structured
data in `expected.txt`. Three artifacts, three single-purpose
contracts.

## R5 — Loader API extension (FR-010): new field vs separate function

**Decision**: Extend `RulesLoadResult` with a new field `rulesEntities
:: [EntityDecl]`. Do **not** add a new top-level loader function
(`loadRulesFileWithEntities`).

**Alternatives considered**:

- **A. New field on `RulesLoadResult`** (chosen). Pros: backwards-compat
  at the type level (record-update + pattern matching keep working);
  one canonical loader path; the body emitter and the overlay
  serializer share the same in-memory entity list. Cons: callers that
  pattern-match on `RulesLoadResult` exhaustively need to add the new
  field (no record-wildcard caller exists today).
- **B. New top-level function** `loadRulesFileWithEntities`. Pros:
  doesn't touch existing callers. Cons: two loader paths to maintain;
  internal duplication; the loader would either run twice on the same
  input or expose a "stage-0" parse + "stage-1" serialize boundary
  that's an internal detail leaking into the public API.
- **C. Re-parse the serialized overlay Turtle in the body emitter**.
  Pros: doesn't touch loader API at all. Cons: wasteful (parse +
  serialize + re-parse); the body emitter would carry a Turtle parser
  inside its own boundary; the resulting `[EntityDecl]` list is a
  bytes-rotation of the loader's internal representation, which is
  fragile (any future change to the loader's serializer breaks the
  emitter's parse).

**A wins** on shared-source-of-truth + smallest public-API surface.

**Impact on existing callers**: the existing #48 callers are
(a) `RulesLoadGoldenSpec` (reads `rulesOverlayTurtle`, unaffected) and
(b) `app/tx-graph/Main.hs` (reads `rulesOverlayTurtle` and
`rulesWarnings`, unaffected). The new field is opt-in.

## R6 — `tx-graph` CLI mode dispatch: flag-presence vs sub-commands

**Decision**: Flag-presence dispatch (plan D8). The CLI is `tx-graph
--rules <…> [--tx <…> --utxo <…>] [--out <…>] [--format …]`. Sub-commands
(`tx-graph emit …`, `tx-graph rules …`) are **not** used in this PR.

**Alternatives considered**:

- **A. Flag-presence** (chosen). Pros: tiny CLI surface; one binary;
  smooth back-compat with #48's `--rules`-only invocation; no
  sub-command sprawl. Cons: the dispatcher is implicit; the help text
  has to spell out the three modes.
- **B. Sub-commands** (`tx-graph emit-overlay`, `tx-graph emit-joint`,
  `tx-graph emit-body`). Pros: explicit; each mode has its own help
  text. Cons: breaks #48's `tx-graph --rules <file>` invocation
  (which would become `tx-graph emit-overlay --rules <file>`);
  needs deprecation aliasing; introduces a sub-command pattern this
  project doesn't otherwise use.
- **C. Single mode with all flags required**. Pros: rigid. Cons:
  breaks back-compat with #48; forces overlay-only callers to pass
  meaningless `--tx` arguments.

**A wins** on back-compat + minimal CLI surface. The dispatcher logic
lives in `Main.hs` and is small (a 5-arm `case` on which flags are
present).

**Help text shape**:

```
tx-graph — Cardano transaction → RDF graph emitter

Usage: tx-graph (--rules FILE | --tx FILE [--utxo FILE]) [--out FILE]
                [--format turtle|json-ld]

Modes (selected by flag presence):
  Overlay only      --rules FILE
  Body only         --tx FILE [--utxo FILE]
  Joint graph       --tx FILE --utxo FILE --rules FILE  (recommended)
```

## R7 — Library boundary: in-memory `ConwayTx` vs CBOR roundtrip

**Decision**: The library function `emit :: ConwayTx -> ResolvedUTxO ->
[EntityDecl] -> Either EmitError EmittedGraph` consumes typed values
in-memory. CBOR/JSON decoding happens at the executable boundary
(plan D9).

**Alternatives considered**:

- **A. Library takes typed values** (chosen). Pros: tests can call
  `emit` directly from the fixture builders (which already produce
  `ConwayTx`); byte-diff goldens cover the emitter, not the CBOR
  roundtrip; faster test loop. Cons: the executable does the decoding
  itself.
- **B. Library takes file paths**. Pros: smaller executable. Cons: the
  library now depends on file I/O + CBOR/JSON decoders; tests have to
  serialize the in-memory fixtures to disk every run; byte-diff
  goldens cover the round-trip, not the emitter.
- **C. Library takes raw `ByteString` (CBOR bytes)**. Pros: one
  function for both CBOR and library paths. Cons: same as B with
  worse ergonomics.

**A wins** on test ergonomics + emitter isolation. The executable's
decoding path uses existing helpers from `Cardano.Tx.Diff.Resolver`
(UTxO JSON) and `Cardano.Ledger.Conway.Tx` (`DecCBOR` instance),
already in the dep closure.

**Smoke-test coverage**: the executable still rounds the full pipeline
in a single test (parse CBOR + decode UTxO + load rules + emit + diff),
asserting Turtle parseability (no byte-diff — the library path covers
that). This catches a regression in the CBOR decoder or UTxO loader
without conflating it with an emitter regression.

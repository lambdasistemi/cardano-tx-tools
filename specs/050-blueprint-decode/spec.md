# Feature Specification: Blueprint decode → typed triples (CIP-57)

**Feature Branch**: `050-blueprint-decode-typed-triples`
**Created**: 2026-05-21
**Status**: Draft (specs phase stop — awaiting parent review via `A-001-design-decisions.md`)
**Input**: Wire the existing `Cardano.Tx.Blueprint.decodeBlueprintData` into the
post-#77 body+witness-set emitter so datums and redeemers belonging to a script
with a registered CIP-57 blueprint produce typed RDF triples keyed by the
blueprint's constructor + field names, replacing the opaque
`cardano:hasRawBytes "<cbor-hex>"` shape that ships today.

## Background — what shipped under #58/#70/#77 and what this PR closes

Three sibling PRs closed in epic #46's Wave 2 produced today's emitter:

- **#58 / PR #60** (merged 2026-05-20, `46f963b`): the projection walker +
  Turtle serializer with byte-stable output across 11 rewrite-redesign fixtures.
- **#70 / PR #77** (merged 2026-05-20, `d2e88ad`): semantic completeness over
  every Conway leaf `Cardano.Tx.Diff.conwayDiffProjection` reaches. Inputs,
  outputs, datums, redeemers, mint, withdrawals, certificates, proposals,
  collateral, witness-set, votingProcedures all surface; the
  `VocabTraceabilitySpec` strict check (33/33 invariants GREEN) gates every
  emitted `cardano:` CURIE against the canonical kmaps `transactions.ttl`.

In particular, **inline datums and Plutus redeemers** in the post-#77 emitter
surface as:

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_9e1199a988ba72ff ;
  cardano:hasRawBytes "d8799fd8799f581c64f3...".
```

— a `cardano:Datum`-typed bnode carrying its hash (as an Identifier-typed
sub-bnode) plus the verbatim CBOR-hex of the datum payload. The PlutusData
inside that CBOR is **invisible** to RDF: a SwapOrder datum reads as
`d8799fd8799f581c64f3...`, not as `:SwapOrder_recipient :recipient1 .` The
shape is wire-correct and reproducible, but downstream SPARQL views (#51) and
the entity-rules reasoner (#49) cannot reach the script-domain leaves inside
the datum because RDF has no decoder for opaque CBOR.

This PR closes that gap. The library already ships
`Cardano.Tx.Blueprint.decodeBlueprintData :: BlueprintSchema -> Data ConwayEra
-> Either BlueprintDataError OpenValue` (verified at `src/Cardano/Tx/Blueprint.hs:228`
on the merged HEAD), and the operator-authored `rules.yaml` schema already
shape-validates a top-level `blueprints:` list whose entries carry
`script: <entity-name>` (cross-checked against declared script entities)
and `datum: <path-to-cip57-json>` (path currently parsed but unused — see
`src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs:296-352`). #50 wires the
decoder into the body emitter and resolves the rules-loaded blueprint paths
into the actual `[Blueprint]` index the emitter consumes.

The PR keeps the post-#77 byte-diff baseline intact for **fixtures that do not
opt into blueprint decoding**. New fixtures (and one refactored fixture)
exercise the typed-emission, no-blueprint passthrough, and decode-failure
paths. The `VocabTraceabilitySpec` strict check stays in force for the
`cardano:` namespace; blueprint-minted predicates live in the operator-owned
default `:` namespace and are subject to their own loose check (each predicate
has a matching blueprint-field declaration in the loaded `[Blueprint]` index).

## Clarifications

### Session 2026-05-21

Seven cross-cutting design questions surfaced during the brief absorption.
All seven are consolidated into `/tmp/epic-046/tx-50/questions/Q-001-design-decisions.md`
with worker recommendations. The clarifications below quote the
recommendations; the parent's `A-001-design-decisions.md` writes the final
values, after which the spec receives a follow-up commit (if any
recommendation is overridden) and the plan phase begins.

- **Q-001a** Blueprint loading surface. Recommendation: extend the existing
  `rules.yaml` `blueprints:` schema with file-loading semantics — the
  loader reads each entry's `datum: <path>` value (resolved relative to the
  rules file directory, matching the `owl:imports` policy), parses it via
  `parseBlueprintJSON`, and threads the resulting blueprint index through
  `RulesLoadResult`. No new CLI flag.
- **Q-001b** Predicate namespace. Recommendation: mint blueprint-derived
  predicates into the fixture-scoped default `:` prefix that the emitter
  already declares (e.g. `:SwapOrder_recipient`).
- **Q-001c** Vocab traceability for `VocabTraceabilitySpec`. Recommendation:
  narrow the strict check to the `cardano:` namespace; blueprint-minted
  predicates are checked separately (loose check: every emitted blueprint
  predicate has a matching field declaration in the loaded blueprint index).
- **Q-001d** Decode-failure semantics. Recommendation: emit `hasRawBytes` +
  `cardano:decodeError "<reason>"` literal; pipeline exits 0; stderr warning.
  Adds `cardano:decodeError` to the canonical vocab via a kmaps Phase A.4
  patch.
- **Q-001e** Reasoner interplay with #49. Recommendation: #50 emits typed
  triples only; OWL annotations and `owl:sameAs` derivation stay #49's
  contract. Acceptance row 4 in the ticket is an integration property
  tested when #49 lands, not a #50 gate.
- **Q-001f** Test fixtures. Recommendation: add fixtures 11/12/13 (or
  next-free integer triple) covering the typed, no-blueprint, and
  decode-failure paths; keep fixture 01 byte-diff baseline as-is.
- **Q-001g** CLI surface for `tx-graph`. Recommendation: no new flags.
  Blueprints flow through the existing `--rules <path>` channel.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator reads a typed datum (Priority: P1)

An operator pastes a Conway transaction CBOR-hex + a `rules.yaml` that
declares a `blueprints:` entry for the spending validator into `tx-graph`.
The output Turtle's datum block names the constructor + field decoded
from the datum:

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_9e1199a988ba72ff ;
  :SwapOrder_recipient _:datum1_recipient .

_:datum1_recipient a cardano:Identifier ;
  cardano:leafType "PaymentScript" ;
  cardano:bytesHex "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef" .
```

The blueprint's `recipient` field is recognised as a `Credential`-shaped
record; the decoded credential bytes flow into a `cardano:Identifier`-typed
sub-bnode with the correct `leafType` (`PaymentScript` for a script
credential, `PaymentKey` for a pubkey credential — same machinery the
existing operator-entity overlay uses).

**Acceptance**: a SPARQL query against the emitted Turtle returns the
recipient bnode:

```sparql
PREFIX : <https://lambdasistemi.github.io/cardano-tx-tools/fixtures/11-blueprint-typed#>

SELECT ?recipient ?bytes
WHERE {
  ?datum :SwapOrder_recipient ?recipient .
  ?recipient cardano:bytesHex ?bytes .
}
```

returns exactly one row, and `?bytes` matches the script-credential bytes
emitted by the body emitter independently from the datum walk. (The reasoner
join that derives `owl:sameAs` between the datum-side recipient and the
output-address-side credential is **#49's contract**, not #50's — see
Clarification Q-001e.)

### User Story 2 — No-blueprint passthrough (Priority: P1)

An operator runs `tx-graph` against a transaction whose spending validator
has **no** entry in the rules.yaml `blueprints:` list. The emitted Turtle
falls back to the post-#77 opaque shape:

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_9e1199a988ba72ff ;
  cardano:hasRawBytes "d8799fd8799f581c64f3...".
```

The byte-diff against `expected.ttl` is identical to the post-#77 baseline —
no `:SwapOrder_*` predicates appear; no `cardano:decodeError` literal appears;
no stderr warning is emitted.

**Acceptance**: the new fixture (Q-001f recommendation) ships an
`expected.ttl` byte-equal to the post-#77 shape; the byte-diff test gates
this invariant in CI.

### User Story 3 — Decode-failure path (Priority: P1)

An operator runs `tx-graph` against a transaction whose spending validator
**does** have a `blueprints:` entry, but the blueprint's declared schema
does not match the actual datum shape (e.g. expects a `bytes` leaf where
the datum carries an `integer`). The emitted Turtle carries both the opaque
shape and a `cardano:decodeError` literal:

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_9e1199a988ba72ff ;
  cardano:hasRawBytes "01" ;
  cardano:decodeError "BlueprintDataTypeMismatch \"bytes\"" .
```

The pipeline exits with status 0; `tx-graph` writes one line to stderr per
failed decode:

```text
tx-graph: WARN: blueprint decode failed for output 1 (script hash <script-hash-hex>): BlueprintDataTypeMismatch "bytes"
```

**Acceptance**: the new fixture ships an `expected.ttl` with both literals
and an `expected.txt` line documenting the expected stderr warning. The
executable-spec test asserts (a) exit code 0, (b) byte-diff match against
`expected.ttl`, (c) substring match for the stderr warning line.

### User Story 4 — Existing #58/#70/#77 invariants stay GREEN (Priority: P1)

All eleven existing rewrite-redesign fixtures continue to pass byte-diff
against their `expected.ttl` files unchanged. The
`VocabTraceabilitySpec` strict check stays at 33/33 invariants GREEN for
the `cardano:` namespace; one new term (`cardano:decodeError`) is added to
the canonical vocab via the Phase A.4 kmaps patch (see Q-001c). The
`build-fixture.hs` regeneration harness #45 continues to regenerate each
fixture's `expected.ttl` from the in-tree emitter without touching the
builder code.

**Acceptance**: `nix develop -c just unit` and `nix develop -c just smoke`
stay GREEN; the byte-diff suite over the 11 + 3 (new) fixtures returns zero
divergences.

### Edge cases

1. **Empty `blueprints:` list in rules.yaml** — the existing parser already
   handles this; the loaded blueprint index is empty; every datum/redeemer
   falls through to the opaque shape. No change.
2. **`blueprints:` entry references a script entity whose hash is not the
   payment credential of any output's address** — the blueprint loads but
   is never consulted. No emitted triples; no warning.
3. **Datum is `NoDatum`** — the existing `emitOutputDatum` no-op
   path is preserved unchanged.
4. **Datum is `DatumHash`-only (output references a hash, the datum body
   appears in the witness set)** — the existing emitter shape (just
   `cardano:hasHash`) is preserved for the output position. The
   datum-witness position (which carries the inline body via
   `cardano:hasRawBytes`) is the one that grows blueprint-typed triples
   when a blueprint is registered.
5. **Same script hash appears in two `blueprints:` entries (duplicate
   blueprint registration)** — first-wins, with a non-fatal warning
   `DuplicateBlueprintForScript` analogous to the existing
   `DuplicateEntityAcrossFiles` warning. The kept entry's source file path
   is logged so the operator can locate the duplicate.
6. **Blueprint JSON file does not exist on disk** — the loader returns a
   new `BlueprintFileMissing !FilePath !Int !Text` error (file path of
   rules.yaml + 1-based source line of the offending `- script:` key +
   the bad path string). Renders via `renderRulesLoadError` as
   `<rules-yaml-path>:<line>: BlueprintFileMissing: <path-string>`.
7. **Blueprint JSON file fails CIP-57 parse** — the loader returns
   `BlueprintParseError !FilePath !Int !Text !Text` (rules.yaml path +
   line + path string + aeson error). Mirrors the existing `ParserError`
   shape.
8. **Blueprint path is absolute or `file://` or `http(s)://`** — same
   filesystem-only policy as imports: returns `AbsoluteBlueprintPath` /
   `HttpsBlueprintPath` errors mirroring the `AbsoluteImport` /
   `HttpsImport` variants.
9. **A redeemer for a Spend purpose without a matching output datum**
   (script consumes a UTxO from an earlier transaction whose datum body is
   not in this tx's witness set) — the redeemer is still decoded against
   its own blueprint `redeemer:` shape, independent from the datum path.
   Datum decoding only fires when the datum body is in scope (either
   inline at an output or as a `DatumWitness`).
10. **Plutus list with heterogeneous items** — the existing decoder
    already handles this via `SchemaList` (fixed length, position-typed)
    vs `SchemaListOf` (uniform item type); both paths produce typed
    `OpenArray` values; the walker translates them into per-index
    predicates (`:field0`, `:field1`, …) or a single repeating predicate
    + sequence under the fixed-vs-uniform distinction.

## Requirements *(mandatory)*

### Functional Requirements

**FR-001** — The `Cardano.Tx.Graph.Rules.Load.RulesLoadResult` record gains
a `rulesBlueprints :: [(ScriptHash, Blueprint, Text)]` field (third
component is the blueprint title — preserved for predicate naming and
diagnostic messages). The loader populates the field by reading each
`blueprints:` entry's `datum: <path>` file, parsing it via
`Cardano.Tx.Blueprint.parseBlueprintJSON`, and looking up the referenced
script entity's `PaymentScript` identifier bytes for the script-hash key.

**FR-002** — A new module `Cardano.Tx.Graph.Emit.Blueprint` exposes a
public function `decodeDatumForOutput :: [(ScriptHash, Blueprint)] -> TxOut
ConwayEra -> Datum ConwayEra -> BlueprintDecodeResult` where
`BlueprintDecodeResult = NoBlueprintRegistered | Decoded OpenValue Blueprint
| DecodeFailed BlueprintDataError`. A sibling
`decodeRedeemerForPurpose :: [(ScriptHash, Blueprint)] -> RdmrPurpose ->
ScriptHash -> Data ConwayEra -> BlueprintDecodeResult` covers the redeemer
path.

**FR-003** — `Cardano.Tx.Graph.Emit.emit` signature extends to accept the
loaded blueprint index alongside `[EntityDecl]`. The composite shape is
either (a) a new parameter `[(ScriptHash, Blueprint)]` after the
`[EntityDecl]` parameter, or (b) a refactor of the `[EntityDecl]` parameter
into a `RulesEmitInput` record carrying both. The plan phase picks one;
spec contract is callers can pass `[]` for "no blueprints" and the emitter
behaves byte-identically to the post-#77 shape.

**FR-004** — `Cardano.Tx.Graph.Emit.Project.emitOutputDatum` consults the
blueprint index. When a blueprint matches the output's payment-credential
script hash AND `decodeBlueprintData` returns `Right openValue`, the
function emits one typed `:<Constructor>_<field>` predicate per top-level
field of the decoded constructor, with object position equal to the
decoded sub-value (a nested constructor becomes a fresh bnode; a `bytes`
leaf becomes a `cardano:Identifier`-typed sub-bnode with the correct
`leafType`; an `integer` leaf becomes an `OIntLit`; a `list` becomes an
ordered sequence — exact mapping pinned in plan.md). When no blueprint
matches, the existing `hasRawBytes` shape is preserved verbatim.

**FR-005** — When a blueprint matches but `decodeBlueprintData` returns
`Left err`, `emitOutputDatum` emits the existing `hasRawBytes` triple
**plus** a new `cardano:decodeError "<show err>"` literal triple. The
literal's text is `show :: BlueprintDataError -> Text` (e.g.
`BlueprintDataTypeMismatch "bytes"`). The pipeline exits 0; the
executable writes one stderr line per failed decode (FR-014).

When a single datum decode encounters multiple sub-errors (e.g. the
top-level constructor matched but two nested fields failed), the emitter
writes **exactly one** `cardano:decodeError` literal on the Datum subject,
naming the **first** error the decoder encountered (D-001d / A-001 micro-pin).
Subsequent errors at the same Datum surface on stderr only — no second
`decodeError` literal — to keep downstream SPARQL view queries
deterministic (one literal per failed Datum subject).

**FR-006** — The datum-witness emitter
(`Cardano.Tx.Graph.Emit.Witness.projectWitness` datum-witness path) mirrors
FR-004 / FR-005. The datum-witness position is the one that carries the
inline CBOR body when the output references the datum by hash; the same
blueprint-lookup logic applies (the script hash is looked up via the
datum's referencing output).

**FR-007** — Redeemer emission consults the blueprint index keyed by
redeemer purpose + resolved script hash:

- `Spend` purpose → script hash of the resolved input's payment credential.
- `Mint` purpose → policy ID (already a script hash).
- `Cert` / `Reward` / `Propose` / `Vote` purposes → script hash extracted
  from the certificate / withdrawal / proposal / vote witness slot per the
  existing emitter logic.

When the blueprint match returns `Decoded`, the emitter emits
`:<Constructor>_<field>` predicates analogous to FR-004. When the
blueprint match returns `NoBlueprintRegistered`, the existing
`hasRawBytes` shape is preserved. When `DecodeFailed`, the `decodeError`
literal is emitted (FR-005).

**FR-008** — Blueprint-derived predicates are minted into the fixture-
scoped default `:` prefix (Q-001b). Naming is
`:<ConstructorTitle>_<FieldTitle>`. Both title strings come from the
blueprint JSON's `"title"` keys (constructor and field). If `"title"` is
absent on a constructor, the constructor's `index` is used as the title
(`:_<index>_<field>`). If `"title"` is absent on a field, the field's
0-based position is used (`:_<index>_field<n>`). Naming-collision
handling: if two blueprints in the index produce the same predicate name,
the loader returns a **hard error** `DuplicateBlueprintPredicate`
(D-001b / A-001 micro-pin — not a warning; predicate collisions are an
operator-side config bug and must be surfaced at load time, before the
emitter runs). Payload = rules-yaml-path + 1-based source line of the
second declaration + the conflicting predicate name.

**FR-009** — `cardano:decodeError` is added to the canonical kmaps
`transactions.ttl` via a Phase A.4 patch
(`/tmp/epic-046/tx-50/transactions-additions-phase-a4.ttl` drafted in the
implementation phase; PARENT-ACTION surfaced on STATUS.md → parent files
kmaps#58 once the impl phase begins). The `VocabTraceabilitySpec` strict
check picks up the new declaration via the existing vendored canonical-vocab
pin refresh.

**FR-010** — The `VocabTraceabilitySpec` strict check is scoped to CURIEs
in the `cardano:` namespace only. Operator-owned predicates (the new
`:<...>_<...>` set) are checked by a new
`BlueprintPredicateTraceabilitySpec`: every blueprint-minted predicate
emitted in any fixture's `expected.ttl` corresponds to a `(constructor,
field)` pair declared in the loaded blueprint index for that fixture's
`rules.yaml`. The check is set-equality; the canonical-vocab pin is not
involved.

**FR-011** — New `RulesLoadError` variants land alongside the existing
ones to cover blueprint-load failures: `BlueprintFileMissing`,
`BlueprintParseError`, `AbsoluteBlueprintPath`, `HttpsBlueprintPath`,
`DuplicateBlueprintPredicate`. A new `RulesLoadWarning` variant
`DuplicateBlueprintForScript` covers the first-wins case pinned by
Edge Case 5 / D-001f / A-001 (operator-side dup blueprint
registration against the same script — non-fatal, second declaration
dropped, warning surfaced on stderr; mirrors the existing
`DuplicateEntityAcrossFiles` shape). Each carries the rules.yaml file
path + 1-based source line of the offending `- script:` key + the
offending value. `renderRulesLoadError` and `renderRulesLoadWarning`
render one stderr line per variant matching the existing format.

**FR-012** — Three new test fixtures cover the three paths in User Stories
1, 2, 3. Existing fixture 01 stays frozen (its `expected.ttl` is the
post-#77 byte-diff baseline). Pinned slugs (D-001f / A-001 micro-pin):

- `test/fixtures/rewrite-redesign/11-blueprint-typed/` — happy path:
  SwapOrder datum body sourced from the operator-paste CBOR (or a
  stripped-down equivalent); `rules.yaml` declares the blueprint;
  `expected.ttl` shows `:SwapOrder_recipient _:recipient1 .` typed triples.
- `test/fixtures/rewrite-redesign/12-blueprint-passthrough/` — no-blueprint
  path: same datum shape as fixture 11 but `rules.yaml` carries NO
  `blueprints:` entries. `expected.ttl` shows opaque `hasRawBytes`,
  byte-equal to what #77's emitter would have produced.
- `test/fixtures/rewrite-redesign/13-blueprint-decode-fail/` — decode-failure
  path: fixture 11's tx + a deliberately-wrong-shape blueprint (e.g. expects
  `bytes` where the datum has `integer`). `expected.ttl` carries both
  `cardano:hasRawBytes` and `cardano:decodeError "<reason>"`;
  `expected.txt` carries the expected stderr warning line.

Per-fixture deliverables:

- `rules.yaml` — declares any `blueprints:` entries the fixture exercises.
- `blueprints/*.cip57.json` — the CIP-57 blueprint JSON (or a path to a
  shared blueprint under `test/fixtures/rewrite-redesign/blueprints/`).
- `expected.ttl` — the byte-diff golden for the typed / passthrough /
  decode-failure shape.
- `expected.txt` (decode-failure fixture only) — the expected stderr line.
- `expected.entities.ttl` — the entity-overlay (unchanged from existing
  pattern).
- `NOTES.md` — provenance + the operator-paste CBOR source if applicable.

**FR-013** — The harness #45 `build-fixture.hs` regeneration script is
extended to drive blueprint-loading without touching the new fixtures'
`expected.ttl` mechanically (i.e. the regen path is byte-stable). The
extension is one new argument-thread step (the rules.yaml path already
flows through; the loader produces the blueprint index transparently).

**FR-014** — The `tx-graph` executable writes one stderr line per
blueprint decode failure (per output / per redeemer). The line format is
`tx-graph: WARN: blueprint decode failed for <position-name> under
script <hash>: <reason>`, where `<position-name>` is `output N`, `datum
witness N`, `redeemer N (purpose=<purpose>)`, or `redeemer for cert N`.
The pipeline exit code stays 0 (Q-001d).

**FR-015** — `docs/assets/asciinema/scripts/tx-graph.sh` re-records the cast
once the typed-emission lands, demonstrating a blueprint-decoded datum on
the operator-paste fixture (or fixture 11, whichever ends up carrying the
real SwapOrder per Q-001f). The MkDocs preview embed continues to render
the cast.

**FR-016** — `CHANGELOG.md` carries a single entry under the next-release
cut documenting the typed-emission feature, the rules.yaml schema
extension (no breaking change — the `datum:` field shape is unchanged,
only its loading semantics gain a side effect), the new `RulesLoadError`
variants, and the new `cardano:decodeError` term.

**FR-017** — No new CLI flag enters the `tx-graph` grammar (Q-001g). The
existing `--rules <path>` flag is the single blueprint-input surface.

**FR-018** — Backward compatibility: a rules.yaml that does NOT declare a
`blueprints:` section produces byte-equal `expected.ttl` against every
existing fixture's golden. The existing 11 fixtures stay frozen.

### Key Entities

- **Blueprint index** — `[(ScriptHash, Blueprint, Text)]` triple produced
  by the rules loader; one entry per `blueprints:` list entry; the
  `ScriptHash` key is the bytes of the referenced script entity's
  `PaymentScript` identifier; the `Blueprint` is the parsed CIP-57 record;
  the `Text` is the blueprint title for diagnostic + predicate naming.
- **`BlueprintDecodeResult`** — three-way ADT returned by the new
  `decodeDatumForOutput` / `decodeRedeemerForPurpose` functions:
  `NoBlueprintRegistered`, `Decoded OpenValue Blueprint`, `DecodeFailed
  BlueprintDataError`.
- **Blueprint-derived predicate** — an IRI of the form
  `:<ConstructorTitle>_<FieldTitle>` declared in the fixture-scoped default
  namespace; minted dynamically per blueprint load.
- **`cardano:decodeError`** — new canonical literal predicate; carries a
  string describing the `BlueprintDataError` variant that fired.

## Success Criteria *(mandatory)*

### Measurable Outcomes

**SC-001** — All 14 fixtures (11 existing + 3 new — Q-001f) pass byte-diff
against `expected.ttl`. The 11 existing fixtures remain bit-identical to
their post-#77 goldens (FR-018).

**SC-002** — The SPARQL query in User Story 1 returns exactly one row on
the typed fixture. The recipient credential bytes match the body emitter's
independently-emitted output address credential bytes for the same
position (the cross-bnode join that #49 later promotes to `owl:sameAs`).

**SC-003** — The no-blueprint fixture's `expected.ttl` matches the
post-#77 opaque shape byte-for-byte; no `:_<>` predicates appear; no
`decodeError` literal appears; no stderr warning is emitted.

**SC-004** — The decode-failure fixture's `expected.ttl` contains both
`cardano:hasRawBytes` and `cardano:decodeError`. The executable's exit
code is 0. The stderr warning line matches `expected.txt`.

**SC-005** — `VocabTraceabilitySpec` (cardano-namespace strict check)
stays at 33/33 GREEN — extended to 34/34 with the addition of
`cardano:decodeError`.

**SC-006** — `BlueprintPredicateTraceabilitySpec` (new, FR-010) returns
zero divergences: every blueprint-minted predicate emitted across all
fixtures has a matching `(constructor, field)` declaration in that
fixture's loaded blueprint index.

**SC-007** — The asciinema cast in `docs/assets/asciinema/tx-graph.cast`
demonstrates a blueprint-decoded datum on the operator-paste fixture.
The MkDocs preview at `MKDOCS_SITE_URL` renders it correctly.

**SC-008** — `gate.sh` stays green on every implementation commit; the
final `chore(050): drop gate.sh` flips the PR to ready-for-review.

**SC-009** — `cabal check` stays clean across the new module
`Cardano.Tx.Graph.Emit.Blueprint`. Haddock builds without warnings.

## Deliverables — surface enumeration

Every release / packaging / docs surface tx-graph already lives on must be
exercised by this PR (resolve-ticket vertical-deliverables rule). Discovery
via `git grep -l 'tx-graph' .github/ flake.nix nix/ docs/ README.md
CHANGELOG.md`:

1. **Library** (`src/Cardano/Tx/Graph/Emit/Blueprint.hs` — new;
   `src/Cardano/Tx/Graph/Emit/Project.hs` — extended seam at
   `emitOutputDatum`; `src/Cardano/Tx/Graph/Emit/Witness.hs` — extended seam
   at the datum-witness path; `src/Cardano/Tx/Graph/Emit.hs` — top-level
   `emit` signature; `src/Cardano/Tx/Graph/Rules/Load.hs` +
   `src/Cardano/Tx/Graph/Rules/Load/Types.hs` +
   `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs` — blueprint loading +
   new error variants; `cardano-tx-tools.cabal` — wires the new module).
2. **Tests** (`test/Cardano/Tx/Graph/Emit/BlueprintSpec.hs` — new unit
   spec; `test/Cardano/Tx/Graph/Emit/BlueprintPredicateTraceabilitySpec.hs`
   — new FR-010 check; `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` —
   extended to cover the new fixtures).
3. **Fixtures** (`test/fixtures/rewrite-redesign/11-*/` +
   `12-*/` + `13-*/` — see Q-001f; `test/fixtures/rewrite-redesign/blueprints/`
   — possibly extended with a third blueprint JSON for the decode-failure
   path).
4. **Linux release pipeline** (`.github/workflows/release.yml`): no
   per-PR change — the tx-graph matrix entry already in place.
5. **Darwin release pipeline** (`.github/workflows/darwin-release.yml`):
   no per-PR change.
6. **Darwin dev-Homebrew workflow**
   (`.github/workflows/darwin-dev-homebrew.yml`): the usage-grep
   validation string (currently `"operator-entity overlay + body emitter"`)
   may need a refresh once the help text changes. Update in-PR if so.
7. **MkDocs deploy workflow** (`.github/workflows/deploy-docs.yml`):
   verify the refreshed cast renders on the preview URL.
8. **Nix executable + check**: `flake.nix` + `nix/checks.nix` — no
   structural change expected.
9. **Docs page** (`docs/tx-graph.md`): refresh the `--help` excerpt + add a
   short section on blueprint decoding (one paragraph + one Turtle
   example).
10. **Asciinema cast** (`docs/assets/asciinema/tx-graph.cast` +
    `docs/assets/asciinema/scripts/tx-graph.sh`): re-record per FR-015 /
    SC-007.
11. **Homebrew taps** (`lambdasistemi/homebrew-tap`): no per-PR change.
12. **README** (`README.md`): one-paragraph mention of blueprint decoding
    in the tx-graph section; one extra CLI example demonstrating a
    blueprint-typed datum output.
13. **CHANGELOG** (`CHANGELOG.md`): one entry per FR-016.
14. **Canonical-vocab pin** (`test/fixtures/canonical-vocab/transactions.ttl`
    + `test/fixtures/canonical-vocab/PINNED.md`): refresh once the kmaps
    Phase A.4 patch (FR-009) merges. Drafted in
    `chore(050): refresh canonical-vocab pin to kmaps@<sha>`.

## Assumptions

- The post-#77 internal IR (`Cardano.Tx.Graph.Emit.Triple.Object`) supports
  any new constructors needed for blueprint-decoded leaves (likely
  `OBytesLit` or reuse of `OBnode` + `cardano:Identifier`-typed sub-bnode).
  Pinned in plan.md once Q-001 lands.
- The post-#77 walker reaches every datum / redeemer leaf that #50 needs to
  decorate — i.e. the walker's *reach* is complete, only the *emission* at
  each datum/redeemer leaf grows new typed triples conditional on the
  blueprint index. Validated by inspection of `emitOutputDatum`
  (Project.hs:1573) and the datum-witness path (Witness.hs).
- The harness #45 `build-fixture.hs` regen script can drive the
  blueprint-extended loader without per-fixture builder changes (the
  rules.yaml path already threads through; the new loader output is a
  superset of the old).
- The kmaps repo's Phase A.4 patch (FR-009 adding `cardano:decodeError`)
  lands in time for the canonical-vocab pin refresh — flagged as a
  PARENT-ACTION on STATUS.md once the impl phase begins. Worst case, the
  pin refresh blocks SC-005's extension to 34/34 until kmaps#58 (the
  proposed kmaps PR) merges.
- The existing `Cardano.Tx.Blueprint` decoder is sufficient — no decoder
  bug-fixes or schema extensions land in #50 (out of scope, per ticket).
- The blueprint JSON file path resolution policy (Q-001a) follows the
  existing `owl:imports` policy: relative to the rules.yaml directory;
  absolute paths + `file://` + `http(s)://` URIs are rejected.

## Out of Scope

- **SHACL shapes for operator-extensible decode** — Phase C, separate
  ticket.
- **New CIP-57 parser features** — the existing
  `Cardano.Tx.Blueprint.parseBlueprintJSON` is taken as sufficient. Bugs
  surfaced during fixture work are filed as separate tickets and patched
  in-place only if they block the acceptance.
- **Reasoner integration / `owl:sameAs` derivation** — #49.
- **OWL annotations** (`rdfs:range`, `owl:ObjectProperty`) for the new
  predicates — out of #50 (would belong to #49 or to the SHACL phase #51
  extension).
- **SPARQL view library** — #51.
- **Diff-as-view (RDF symmetric-difference mode)** — #52.
- **Executable consolidation** — #53.
- **Migration docs + deprecation timeline** — #54.
- **Non-Spend redeemer purposes** beyond what the post-#77 emitter
  already reaches (Mint, Cert, Reward, Propose, Vote). Each gets
  blueprint-decoding via FR-007; coverage scales with whichever fixtures
  exercise them. No fresh certificate / proposal varieties enter the
  fixture set as part of #50.

## Glossary

- **CIP-57 blueprint** — Cardano Improvement Proposal 57, the JSON
  schema for declaring Plutus validator interfaces (datum, redeemer,
  parameters) by their constructor + field shape. The existing
  `Cardano.Tx.Blueprint` module parses a subset sufficient for typed
  decoding.
- **OpenValue** — the typed in-memory AST produced by `decodeBlueprintData`
  (defined in `Cardano.Tx.Diff`). Carries `OpenInteger`, `OpenBytes`,
  `OpenObject (Map Text OpenValue)`, `OpenArray [OpenValue]`.
- **Blueprint-derived predicate** — an IRI of the form
  `:<ConstructorTitle>_<FieldTitle>` (see FR-008) declared in the
  fixture-scoped default namespace.
- **Blueprint index** — see Key Entities.
- **Typed datum / redeemer** — a datum or redeemer whose CBOR payload has
  been decoded via a registered blueprint into an `OpenValue` AST whose
  fields are then emitted as RDF predicates.

## Followup (orchestrator-owned, not this PR)

- **kmaps Phase A.4 patch** (FR-009): add `cardano:decodeError` to
  canonical `transactions.ttl`. PARENT-ACTION; parent files kmaps#58 once
  the impl phase surfaces the patch draft.
- **#49 (EYE reasoner)** unblocks when #50 lands. Acceptance row 4 in
  ticket #50 ("the combination of blueprint-named predicates + entity
  rules + reasoner produces `owl:sameAs` deductions on blueprint-typed
  leaves") becomes #49's responsibility to test.
- **#51 (SPARQL views)** can now author views over typed datum/redeemer
  shapes — `swap-flow.rq`, `mpfs-fact-flow.rq`, etc. Out of #50's scope.
- **Operator docs**: longer-form tutorial on authoring CIP-57 blueprints
  for an in-house validator. Deferred until at least one real operator
  exercises the surface; flagged as a #51-or-later follow-up.

## References

- Ticket: <https://github.com/lambdasistemi/cardano-tx-tools/issues/50>
- Epic: <https://github.com/lambdasistemi/cardano-tx-tools/issues/46>
- Predecessor PR (Conway semantic completeness): <https://github.com/lambdasistemi/cardano-tx-tools/pull/77>
- Predecessor PR (body emitter MVP): <https://github.com/lambdasistemi/cardano-tx-tools/pull/60>
- CIP-57: <https://cips.cardano.org/cips/cip57/>
- Q-001 (this PR's consolidated design questions):
  `/tmp/epic-046/tx-50/questions/Q-001-design-decisions.md`
- Constitution: `.specify/memory/constitution.md`
- Existing decoder: `src/Cardano/Tx/Blueprint.hs:228`
- Existing datum-emission seam: `src/Cardano/Tx/Graph/Emit/Project.hs:1573`
- Existing rules-loader blueprint schema: `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs:296-352`
- Existing fixture with blueprint reference:
  `test/fixtures/rewrite-redesign/01-amaru-treasury-swap/rules.yaml`

# Feature Specification: Rules loader — Turtle + YAML sugar + `owl:imports` composition

**Feature Branch**: `48-rules-loader`
**Created**: 2026-05-19
**Status**: Draft
**Input**: `Cardano.Tx.Graph.Rules.Load` — load operator-authored rule files in two
forms (canonical Turtle; YAML sugar that compiles to equivalent Turtle), compose
them via `owl:imports`/`imports:`, detect cycles, validate `cardano:Entity`
declarations, expose the loader to `tx-graph --rules <file>`. Wave 2 lander of
epic #46 after the #47 deferral re-sequencing — runs ahead of the body emitter
(#58) so the operator-entity overlay exists on disk before #58 reconstitutes the
joint graph.

## Background — why this is the next Wave-2 lander

The PR #56 / spec
[`specs/047-emitter-mvp-deferred/spec.md`](../047-emitter-mvp-deferred/spec.md)
recorded that the originally-scoped #47 body emitter cannot land cleanly while
the operator-entity overlay (entity triples derived from `rules.yaml`) is absent
from disk: every fixture's `expected.ttl` interleaves rules-derived entity
triples with body triples whose blank nodes name those entities (`_:tx
cardano:hasOutput _:treasuryOutput`, `_:treasuryComplianceCredPayment
cardano:hasIdentifier _:treasuryComplianceId`). The chosen re-sequencing is to
ship #48 **first** — a self-contained loader from `rules.yaml`/`rules.ttl` to a
deterministic entity-overlay Turtle — and then to land the body emitter as a
follow-up (#58) that takes the on-disk entity overlay as a peer input and
produces the joint graph.

The deferral makes #48's contract concrete: the loader must produce a Turtle
byte stream that, byte-for-byte, equals a new per-fixture asset
`test/fixtures/rewrite-redesign/<NN>/expected.entities.ttl` — the
operator-declared-entities slice of `expected.ttl`, rewritten with rules-derived
blank-node names so #58 can reference them in one pass.

## Clarifications

### Session 2026-05-19

- Q: What format is the canonical input — Turtle, YAML, or both?
  → A: Both. Turtle is canonical; YAML is sugar that compiles to equivalent
    Turtle and dispatches to the same Turtle code path. The two formats are
    distinguished by file extension (`.ttl` vs `.yaml`/`.yml`).
- Q: How is the operator-entity overlay's blank-node naming chosen?
  → A: Algorithmically derived from rules.yaml content. The carve-out
    `expected.entities.ttl` is *regenerated* against the loader's deterministic
    naming scheme — not a byte-faithful slice of the existing `expected.ttl`
    (which carries hand-tuned artisan names). The future #58 emitter references
    the new names directly and produces a fresh joint `expected.ttl`. The
    existing `expected.ttl` files become reference documents for #58 (the body
    layout is the contract — the bnode names are not).
- Q: What does the import graph look like — a tree, a DAG, or both?
  → A: A DAG. Multiple files may import the same file (diamond imports). A
    cycle is an error.
- Q: How are imports resolved on disk?
  → A: Relative to the importing file's directory. Absolute paths are forbidden
    (they hurt reproducibility); URIs of the form
    `<https://lambdasistemi.github.io/.../...ttl>` are *not* fetched in this PR
    (offline default per the constitution). An import literal must be a
    relative file-system path expressed as an IRI literal that resolves on
    disk.
- Q: What happens when two imported files declare different entities with the
    same URI? (Issue #48 acceptance bullet 3.)
  → A: The loader emits a warning naming both files; loading continues with the
    *first* declaration kept and the second's identifier triples **NOT**
    merged in (the loader does not attempt additive-vs-conflicting inference
    — see US6). Warnings go to `stderr` when the loader is invoked via
    `tx-graph --rules`; the library API returns them as part of the result
    so callers can choose their reporting channel.
- Q: What happens when an entity in a rules file declares zero identifiers?
  → A: Hard error `EntityZeroIdentifiers <uri>`. The constitution forbids silent
    schema drift, and a zero-identifier `cardano:Entity` is meaningless — the
    OWL hasKey contract is `(leafType, bytesHex)`, so an entity with no
    identifiers cannot participate in cross-leaf identity at all.
- Q: What is the executable surface in this PR?
  → A: `tx-graph --rules <file>` is wired and produces the operator-entity
    overlay on stdout (the body emitter is followup #58). The executable's
    `--out` and `--utxo` flags are deferred to #58. This PR ships *just* the
    rules-loading half of the executable so the cross-PR contract is anchored
    end-to-end.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Operator authors `rules.yaml`, loader produces the entity overlay (Priority: P1)

The operator writes a `rules.yaml` file declaring named entities, optionally
with `from-address`/`script`/`asset` shapes, and optional `blueprints:` and
`collapse:` sections. The loader compiles the file to an in-memory triple set,
serializes it to Turtle, and the produced bytes equal
`test/fixtures/rewrite-redesign/<NN>/expected.entities.ttl` byte-for-byte for
all 11 checked-in fixtures.

**Why this priority**: P1 because every Wave-2/3 ticket (#58 body emitter, #49
reasoner, #50 blueprint, #51 views) depends on this overlay being producible
from operator authoring. Without it, the deferred #47 emitter has nothing to
compose against, and the epic acceptance (epic #46's SC-005, byte-identical
reproducibility) remains anchored on a future PR's word rather than on-disk
evidence.

**Independent Test**: For each of the 11 rewrite-redesign fixtures, run the
loader on `rules.yaml`, capture stdout (or library output), byte-compare against
`expected.entities.ttl`. All 11 byte-equal → P1 passes. No body emitter needed
to test this story.

**Acceptance Scenarios**:

1. **Given** `test/fixtures/rewrite-redesign/02-alice-bob-ada/rules.yaml` (the
   simplest fixture; `alice` and `bob` entities with `from-address` sugar),
   **When** the loader compiles the file, **Then** the produced Turtle
   byte-equals `test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.entities.ttl`,
   which contains the `:alice`, `:bob`, `_:alice<role>`, `_:bob<role>` triples
   from lines 5–33 of the existing `expected.ttl` rewritten under the loader's
   deterministic naming scheme.
2. **Given** `test/fixtures/rewrite-redesign/01-amaru-treasury-swap/rules.yaml`
   (load-bearing P1 fixture; 5 entities including a shared-identity case
   between `amaru.swap-order` and `amaru.swap.v2`), **When** the loader compiles
   the file, **Then** the produced Turtle byte-equals
   `expected.entities.ttl` for that fixture, with the (PaymentScript,
   `fa6a58bb...`) identifier shared by exactly one blank-node name across both
   entities.
3. **Given** all 11 fixtures, **When** `RulesLoadGoldenSpec` runs under
   `nix develop --quiet -c just unit`, **Then** all 11 byte-diff items pass and
   `./gate.sh` exits 0.

---

### User Story 2 — Operator authors a canonical Turtle rules file (Priority: P2)

The operator writes a `rules.ttl` file directly using the same vocab
(`cardano:Entity`, `cardano:hasIdentifier`, `cardano:Identifier`,
`cardano:leafType`, `cardano:bytesHex`, `rdfs:label`), without going through the
YAML sugar. The loader parses the Turtle, validates entity shapes, and produces
the same triple set as the YAML path would (when authored to match).

**Why this priority**: P2 because YAML sugar is the operator's everyday input
(closes the P1 byte-diff), but canonical Turtle is the format the loader emits
and the format imports compose in. The two surfaces must be co-equal so that
authoring decisions and downstream tooling can pivot between them without
re-authoring.

**Independent Test**: Author a small hand-written `.ttl` rules file (single
entity, one identifier). Run the loader. Confirm the in-memory triple set is
identical to what the equivalent YAML one-liner produces. No fixture needed —
unit-level.

**Acceptance Scenarios**:

1. **Given** a `.ttl` rules file declaring one `cardano:Entity` with one
   `cardano:hasIdentifier`, **When** the loader parses it, **Then** the
   in-memory triple set contains exactly the entity, label, identifier, and
   leafType/bytesHex triples, and no extras.
2. **Given** the same content authored as YAML and as Turtle, **When** both
   files are loaded, **Then** both produce byte-equal Turtle output through the
   loader's serializer.

---

### User Story 3 — Operator composes rules across files via `owl:imports` (Priority: P2)

A `team.ttl` file declares team-level entities and `owl:imports`-es
`shared/usdm.ttl`. The shared file declares the `usdm` asset entity. The loader
reads `team.ttl`, follows the import, and the resulting graph contains the
union of triples from both files. The same composition is expressible in YAML
sugar via an `imports: [shared/usdm.yaml]` top-level key, where each imported
file may itself be Turtle or YAML.

**Why this priority**: P2 because composition is the lever for keeping operator
files small and shareable. The MVP fixtures all author single-file rules, so
the byte-diff acceptance does not need composition to pass — but #58 and the
downstream waves are designed around shared overlays.

**Independent Test**: A two-file Turtle pair (parent imports child); a two-file
YAML pair; one mixed pair (YAML imports Turtle). All three load to the same
in-memory triple set as a single-file authoring of the merged content.

**Acceptance Scenarios**:

1. **Given** `parent.ttl` containing `<> owl:imports <child.ttl> .` and
   `child.ttl` declaring `:usdm a cardano:Entity ; rdfs:label "usdm" ; ...`,
   **When** the loader runs on `parent.ttl`, **Then** the resulting triple set
   contains `:usdm`'s triples and any triples authored in `parent.ttl`.
2. **Given** a diamond import (parent imports A and B; both A and B import the
   same C), **When** the loader runs on parent, **Then** C is loaded exactly
   once and the resulting graph contains its triples once.
3. **Given** a YAML file with `imports: [./shared.ttl]` plus its own
   `entities:` list, **When** the loader runs on it, **Then** the resulting
   graph is the union of the YAML-compiled entities and the Turtle import.

---

### User Story 4 — Loader detects import cycles and reports the cycle (Priority: P2)

A `a.ttl` imports `b.ttl` imports `a.ttl`. The loader fails with a structured
error naming the cycle path `a.ttl → b.ttl → a.ttl`. The error type carries the
list of files so the executable's stderr and the library callers can render it
consistently.

**Why this priority**: P2 because cycles are the most common composition
failure once `imports:` is used in anger. The error must be structured (not a
free-form string) so the future `tx-graph` UI and any IDE integration can render
it as a hyperlinked path.

**Acceptance Scenarios**:

1. **Given** the two-file cycle above, **When** the loader runs on `a.ttl`,
   **Then** it fails with `RulesImportCycle ["a.ttl","b.ttl","a.ttl"]`, no
   triples are returned, and the executable exits non-zero.
2. **Given** a self-import (a.ttl imports a.ttl), **When** the loader runs,
   **Then** it fails with `RulesImportCycle ["a.ttl","a.ttl"]` — the degenerate
   one-step cycle is still structured.

---

### User Story 5 — Loader detects zero-identifier entities and parser-level errors (Priority: P2)

The operator typos a `rules.yaml` and forgets the `from-address` /
`script` / `asset` field on an entity. The loader fails with
`EntityZeroIdentifiers <uri>` naming the offending entity. A malformed Turtle
file (unterminated string, missing `.`, etc.) or a malformed YAML file fails
with a parser error carrying the file path and line number.

**Why this priority**: P2 because these are the everyday operator typos. The
structured shape lets `tx-graph` (and a future LSP) point at the offending
line; an opaque string error forces the operator to read raw Turtle output.

**Acceptance Scenarios**:

1. **Given** a YAML rules file where one entity has no `from-address`, no
   `script`, and no `asset`, **When** the loader runs, **Then** it fails with
   `EntityZeroIdentifiers ":<entitySlug>"`, naming the entity's compiled URI.
2. **Given** a malformed Turtle file (unterminated literal on line 7),
   **When** the loader runs, **Then** it fails with a parser error containing
   the file path and line number 7.
3. **Given** a malformed YAML file (tab indentation on line 4), **When** the
   loader runs, **Then** it fails with a parser error containing the file path
   and line number 4.

---

### User Story 6 — Two imported files declare the same entity URI; loader warns naming both files (Priority: P3)

Two imported files both declare `:usdm a cardano:Entity` with different
identifier sets. The loader emits a warning naming both source files; the
*first*-loaded declaration is kept and the second's identifier triples are
*not* merged in (silent merging is the silent-drift trap the constitution
forbids).

**Why this priority**: P3 because cross-file duplication is a real authoring
hazard once `imports:` is used at scale, but the merged-graph behavior is
load-bearing for downstream tooling (#49 reasoner relies on a single canonical
declaration per entity).

**Acceptance Scenarios**:

1. **Given** two imported files both declaring `:usdm` with different
   identifier hashes, **When** the loader runs, **Then** the result carries one
   warning naming both files and the produced graph contains only the first
   file's `:usdm` triples.
2. **Given** the same `<entity-uri>` declared once with one identifier and a
   second time *adding* a second identifier (a non-conflicting additive
   shape), **When** the loader runs, **Then** the warning is still emitted —
   the loader does not attempt to infer additive vs conflicting intent; it
   names the duplication and lets the operator deduplicate.

---

### User Story 7 — `tx-graph --rules <file>` wiring (Priority: P2)

The `tx-graph` executable accepts a `--rules <file>` flag pointing to either a
Turtle or YAML rules file. On success, it writes the operator-entity overlay to
stdout. On failure, it exits non-zero and writes the structured error to
stderr.

**Why this priority**: P2 because the executable is the operator's surface for
this PR — it's how a reviewer confirms the cross-PR contract end-to-end
(`tx-graph --rules <fixture>/rules.yaml > /tmp/out.ttl && diff /tmp/out.ttl
<fixture>/expected.entities.ttl` exits 0). The body-emitter flags (`--utxo`,
`--out`, `--tx`) are deferred to #58.

**Independent Test**: Run `tx-graph --rules
test/fixtures/rewrite-redesign/02-alice-bob-ada/rules.yaml > /tmp/out.ttl`,
then `diff /tmp/out.ttl
test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.entities.ttl`. Exit 0.

**Acceptance Scenarios**:

1. **Given** a valid rules file path, **When** `tx-graph --rules <path>` runs,
   **Then** it writes the overlay Turtle to stdout and exits 0.
2. **Given** an invalid rules file (cycle, zero-identifier, parser error),
   **When** the same command runs, **Then** it writes the structured error to
   stderr and exits non-zero.
3. **Given** a missing `--rules` argument, **When** `tx-graph` runs, **Then**
   it shows usage and exits non-zero (the body-emitter flags are deferred but
   `--rules` is required for this PR's surface).

---

### Edge Cases

- **`rules.yaml` without any `entities:` key**: succeeds, produces an empty
  overlay (zero triples). The kmaps Phase A prefix declarations *are* still
  emitted (so the file is a valid Turtle document on disk). Justification:
  `imports:` may compose entities from other files; emitting only the header is
  the correct empty-but-valid output.
- **`from-address: <bech32>` with invalid bech32**: parser error with file +
  line + bech32 string echo.
- **`asset:` with `policy` shorter than 28 bytes or longer**: parser error.
- **`blueprints:` referring to a `script:` name that no entity declared**:
  parser error with the unknown script name. (Loader cannot decode the
  blueprint here — blueprint decoding is #50 — but it must validate that the
  named script entity exists.)
- **`collapse:` rules in a rules file**: pass through to the in-memory triple
  set as-is (the overlay does not emit triples for collapse rules — those are
  consumed by #50/#51). The loader records them in its return value so
  downstream waves can consume without re-parsing. In this PR they are loaded
  and validated; they are NOT serialized into the entity overlay output.
- **Comment lines and whitespace in input**: preserved through parsing but the
  serializer emits a canonical form (one entity per blank line; identifiers
  indented two spaces; trailing newline) so byte-diff is stable.
- **Two entities with the same `name` in the same file**: parser error with
  both line numbers.
- **Entity name containing characters not allowed in a Turtle local-name**
  (e.g., `.`, `-`, ` `, mixed case): the slug algorithm
  (`[^a-z0-9]` → `_`, collapse repeated `_`, trim leading/trailing `_`)
  rewrites the name into a deterministic snake-case form that is a
  valid Turtle PN_LOCAL by construction. The slug is used **both**
  for the entity's IRI local part (`:<slug> a cardano:Entity`) **and**
  for the prefix of every bnode the entity owns
  (`_:<slug>_<roleSuffix>`). The operator's original `name:` value
  is preserved verbatim in the entity's `rdfs:label` triple.
- **Entity name that the slug algorithm reduces to the empty string**
  (e.g., `name: "---"`, `name: ""`, `name: "  "`): rejected with a
  structured `EntityNameSlugEmpty <file> <line> <original-name>`
  error. The slug must produce ≥ 1 character.
- **Entity name whose slug starts with a digit**: also rejected
  (`EntityNameSlugLeadingDigit <file> <line> <original-name>`).
  Turtle PN_LOCAL allows leading digits in the local part of a
  prefixed name, but bnode local parts `_:0foo` are syntactically
  legal yet stylistically ambiguous; rejecting at load time is the
  conservative path.
- **Two entities in the same file slug to the same string**
  (e.g., `name: "usdm-control"` and `name: "usdm.control"` both slug
  to `usdm_control`): rejected with
  `DuplicateEntitySlugInFile <file> <slug> <line1> <line2>`. The
  collision check happens after slugging, before identifier
  derivation, so the operator sees a clear error rather than a
  confusing later "duplicate entity IRI" failure.
- **Absolute path in `imports:`**: rejected with a structured error (per the
  clarification — relative paths only).
- **Recursive identifier**: not possible (an `Identifier` is a leaf with
  `leafType` and `bytesHex`); enforced at parse.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module `Cardano.Tx.Graph.Rules.Load` MUST expose a pure
  loader function consuming a file path and returning either a structured error
  or a result type carrying (a) the in-memory triple set, (b) the operator-entity
  overlay's Turtle serialization, (c) any non-fatal warnings.
- **FR-002**: The loader MUST accept files in two formats — canonical Turtle
  (`.ttl`) and YAML sugar (`.yaml`/`.yml`) — and dispatch by extension. Other
  extensions MUST be rejected with a structured error.
- **FR-003**: The Turtle parser MUST handle the subset of Turtle required by
  the loader: `@prefix` declarations, blank-node syntax `_:name`, IRI
  references, string literals, integer literals, statement terminators
  (`.`/`;`/`,`), and `owl:imports` triples. Out-of-subset constructs (e.g.,
  collections `( ... )`, language tags) MUST produce a structured parser error
  rather than silently dropping the triple.
- **FR-004**: The YAML compiler MUST accept the 044 grammar's `entities:`,
  `blueprints:`, and `collapse:` keys at the top level, plus a new
  `imports:` key whose value is a list of relative paths to Turtle or YAML
  files.
- **FR-005**: The YAML compiler MUST normalize each `entities:` entry into
  one or more `cardano:Identifier` blank nodes according to the entity shape
  (`from-address`, `script`, `asset`). Two entities whose identifier set
  shares an exact (leafType, bytesHex) pair MUST share the same blank-node
  name in the produced Turtle.
- **FR-006**: The loader MUST resolve `owl:imports` (Turtle) and `imports:`
  (YAML) as paths relative to the importing file's directory. Absolute
  paths MUST be rejected with a structured error.
- **FR-007**: The loader MUST follow imports transitively, loading each
  imported file at most once per top-level load (diamond imports merged
  cleanly).
- **FR-008**: The loader MUST detect cycles on the import graph and fail
  with `RulesImportCycle [<path1>, <path2>, ..., <path1>]`.
- **FR-009**: The loader MUST validate that every `cardano:Entity` declaration
  carries at least one `cardano:hasIdentifier`. Zero-identifier entities MUST
  produce `EntityZeroIdentifiers <uri>`.
- **FR-010**: The loader MUST produce parser errors that carry the file
  path and line number for malformed Turtle or YAML input.
- **FR-011**: When two imported files declare the same `cardano:Entity` URI,
  the loader MUST emit a non-fatal warning naming both files; the *first*
  declaration is kept and the second's identifier triples are NOT merged in.
- **FR-012**: The loader's Turtle serializer MUST emit a canonical form:
  Phase A prefix declarations first (kmaps `cardano:` + `rdfs:` + the local
  fixture base, in that order); one entity per blank line; identifiers
  indented two spaces; statement terminators on every non-blank/non-comment
  line; trailing newline.
- **FR-013**: The blank-node and entity-IRI naming scheme MUST be
  deterministic. For an identifier with (leafType, bytesHex), the bnode
  name is derived from the first entity that declares that pair, in
  the file order the loader sees the declaration. Specifically:
  `_:<entitySlug>_<roleSuffix>` where `entitySlug` is the entity's
  slug (lowercased, `[^a-z0-9]` → `_`, collapse repeated `_`, trim
  leading/trailing `_`), and `roleSuffix` is the leafType with
  **only** the first character lowercased (other characters preserved
  verbatim). The **same `entitySlug` is also the entity's IRI local
  part**: an entity declared as `- name: usdm-control` produces both
  `:usdm_control a cardano:Entity ;` *and* the bnode prefix
  `_:usdm_control_<roleSuffix>` for every identifier it owns. The
  operator's original `name:` value is preserved verbatim in the
  entity's `rdfs:label` triple so display tooling can recover the
  authoring form.
  The roleSuffix for every leafType used by the 11 fixtures is fixed
  as follows: `PaymentKey → paymentKey`, `PaymentScript → paymentScript`,
  `StakeKey → stakeKey`, `StakeScript → stakeScript`,
  `AssetClass → assetClass`, `Policy → policy`, `PoolId → poolId`,
  `DRepKey → dRepKey`, `DRepScript → dRepScript`.
- **FR-014**: The `tx-graph` executable MUST accept a `--rules <file>` flag
  and write the operator-entity overlay to stdout. The body-emitter flags
  (`--utxo`, `--out`, `--tx`) are out of scope for this PR.
- **FR-015**: The `tx-graph` executable MUST exit non-zero and write the
  structured error to stderr on any loader failure (parser, cycle,
  zero-identifier, missing file).
- **FR-016**: Every exported function and type in the new
  `Cardano.Tx.Graph.*` modules added by this PR MUST carry a Haddock
  docstring (constitution Principle IV — strict for new code in this
  PR; enforced by reviewer convention since the gate's `cabal haddock`
  step verifies haddock builds cleanly but does not surface
  missing-docstring as a build failure given pre-existing
  undocumented exports in unrelated modules — see [research.md R14](./research.md)
  and the Q-001/A-001 record at
  `/tmp/epic-046/tx-48/subagents/T001a/{questions,answers}/A-001-haddock-missing-docs-not-enforced.md`).
  Strict per-export missing-docstring enforcement across the whole
  codebase is tracked as a follow-up.
- **FR-017**: The loader MUST default to fully offline behaviour per the
  constitution's Default-Offline Semantics: import resolution is filesystem-only
  and never fetches remote IRIs. Future network-resolution capability is
  out of scope.
- **FR-018**: For each of the 11 rewrite-redesign fixtures, the cross-PR
  contract MUST be: running the loader on `rules.yaml` produces output that
  byte-equals `expected.entities.ttl` (a new per-fixture asset authored in
  this PR).

### Key Entities

- **RulesFile**: The on-disk artifact (Turtle or YAML) the operator authors.
  Two extensions, two parsers, one normalized representation.
- **RulesGraph**: The in-memory triple set produced by the loader. Composed of
  prefix declarations, entity declarations, identifier nodes, and any
  `blueprints:`/`collapse:` annotations carried as triples.
- **Entity**: A `cardano:Entity` declaration with a URI (`:slug`), an
  `rdfs:label`, and one or more `cardano:hasIdentifier` references.
- **Identifier**: A `cardano:Identifier` blank node with a `cardano:leafType`
  and a `cardano:bytesHex` literal. The complete set of leafTypes the 11
  fixtures author is `"PaymentKey"`, `"PaymentScript"`, `"StakeKey"`,
  `"StakeScript"`, `"AssetClass"`, `"Policy"`, `"PoolId"`, `"DRepKey"`,
  `"DRepScript"`. `Policy` is the role class that appears alongside
  `PaymentScript` in fixture 04's compound-key entity. `PoolId` /
  `DRepKey` / `DRepScript` appear in fixtures 06 / 07 respectively.
- **ImportGraph**: The DAG induced by `owl:imports`/`imports:` across files.
  Nodes are absolute resolved file paths; edges are import relationships.
- **RulesLoadError**: The structured failure type carrying one of:
  `ParserError <file> <line> <msg>`, `RulesImportCycle [<file>]`,
  `EntityZeroIdentifiers <entity-uri>`, `UnsupportedExtension <path>`,
  `AbsoluteImport <importer> <imported>`, `MissingImport <importer> <imported>`,
  `BlueprintRefsUnknownScript <name>`, `DuplicateEntityInFile <file> <name>
  <line1> <line2>`, `DuplicateEntitySlugInFile <file> <slug> <line1>
  <line2>`, `EntityNameSlugEmpty <file> <line> <original-name>`,
  `EntityNameSlugLeadingDigit <file> <line> <original-name>`,
  `BadBech32 <file> <line> <string>`, `BadPolicyHex <file> <line> <string>`.
- **RulesLoadWarning**: Non-fatal warnings, currently just
  `DuplicateEntityAcrossFiles <uri> <file-kept> <file-dropped>`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For each of the 11 `test/fixtures/rewrite-redesign/<NN>/`
  fixtures, `Cardano.Tx.Graph.Rules.Load.loadRulesFile <fixture>/rules.yaml`
  succeeds and produces output that byte-equals
  `<fixture>/expected.entities.ttl` under `RulesLoadGoldenSpec`.
- **SC-002**: `tx-graph --rules <fixture>/rules.yaml > /tmp/out.ttl && diff
  /tmp/out.ttl <fixture>/expected.entities.ttl` exits 0 for every fixture.
- **SC-003**: Loading a hand-written 2-file Turtle cycle exits with
  `RulesImportCycle` listing both file paths and the entry path repeated at
  the end; the executable exits non-zero.
- **SC-004**: Loading a YAML rules file with one entity missing all of
  `from-address`/`script`/`asset` exits with
  `EntityZeroIdentifiers ":<slug>"`; the executable exits non-zero.
- **SC-005**: A round-trip pair (the same content authored as YAML and as
  Turtle) produces byte-equal output through the loader's serializer.
- **SC-006**: `./gate.sh` (build + unit + cabal-fmt + fourmolu + hlint
  + `cabal check` + `cabal haddock lib:cardano-tx-tools`) is green on
  every commit on this branch; CI mirrors it. The Haddock build
  anchors FR-016 (every exported function and type carries a
  docstring; absent docstrings fail the haddock build).
- **SC-007**: `cabal check` is clean — no warnings, no missing fields.
  This anchors constitution Principle IV (Hackage-Ready Quality). Per
  Q-002 the constitution-compliance sweep happens **inside** this PR
  (slices T001b adding upper bounds + T001c gating `-Werror` behind
  a `werror` cabal flag) rather than as a follow-up — the user
  override on Q-002 invoked the "no pre-existing excuses" rule.

## Assumptions

- The kmaps#53 Phase A vocab IRI
  `https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#`
  is pinned for the loader's prefix declaration. (Merged 2026-05-19 in
  cardano-knowledge-maps; the existing harness already uses this prefix.)
- The 11 rewrite-redesign fixtures' `rules.yaml` files already declare every
  entity needed; this PR does not edit them.
- Operator-authored Turtle uses the same vocab as the emitted form; the loader
  is not asked to translate vocabularies.
- No RDF Haskell library is pulled into the dependency closure. The loader is
  authored as in-house text-level parsing — consistent with the
  [DSL stress-test policy](../../CLAUDE.md) and with
  [`specs/033-rewrite-redesign-harness/research.md` D5](../033-rewrite-redesign-harness/research.md)
  which already rejected `swish`/`rdf4h`/`rapper` for the harness Turtle
  predicate. The full structural parser is bounded by the Turtle subset
  enumerated in FR-003 and is the right size for an in-house implementation
  per the constitution's TDD bisect-safe slice rule.

## Out of Scope

- The body emitter (`Cardano.Tx.Graph.Emit` or its equivalent) — followup
  ticket #58, depends on this PR.
- Reasoner / OWL 2 RL inference over the loaded graph — wave 3, ticket #49.
- SPARQL views over the loaded graph — wave 3, ticket #51.
- Blueprint decoding of `datum` shapes inside rules — wave 3, ticket #50.
  This PR validates that `blueprints:` references reference an existing
  script-typed entity, but does not decode the CIP-57 schema.
- Network-fetched imports (HTTPS / file:// at non-local URIs). Default-offline
  per the constitution.
- Editing the existing `expected.ttl` golden files. They remain as #58's
  reference for the body section; #58 will regenerate them when the joint
  graph is reconstituted.
- Editing the existing `rules/amaru-treasury.yaml` (rewrite rules consumed by
  `Cardano.Tx.Rewrite`). Despite the shared `collapse:` key name, the two are
  *different* DSLs — the rewrite rules belong to `Cardano.Tx.Rewrite`; the
  graph rules belong to `Cardano.Tx.Graph.Rules`.

## Glossary

- **Operator-entity overlay**: The slice of `expected.ttl` containing
  `cardano:Entity` declarations and their identifier blank nodes — the
  portion of the joint graph that is *not* derivable from a Tx + UTxO alone.
- **Carve-out / `expected.entities.ttl`**: A new per-fixture asset authored
  in this PR holding the loader's deterministic-naming-scheme version of the
  operator-entity overlay. Byte-diff target for `RulesLoadGoldenSpec`.
- **Phase A vocab**: The cardano-knowledge-maps#53 OWL 2 RL vocab terms
  pinned to the kmaps `cardano:` namespace.
- **YAML sugar**: The 044 grammar's `entities:` / `blueprints:` / `collapse:`
  top-level keys, extended in this PR with `imports:` for composition.

## Followup (orchestrator-owned, not this PR)

- **#58** (body emitter, replacing the deferred #47 MVP): reconstitutes the
  joint `expected.ttl` from `(Tx, UTxO, EntityOverlay)`. Depends on this PR
  for the EntityOverlay.
- **#49** (reasoner): OWL 2 RL inference over the loaded graph plus the
  emitted body graph.
- **#50** (blueprint): decodes CIP-57 datum schemas inside rules and emits
  the decoded triples into the rules graph (extends FR-005 in a future PR).
- **#51** (cli-tree views): SPARQL projection from the joint graph back to
  the 044 text shape.
- **Epic #46**: Update Wave-2 sequencing once this PR merges.

## References

- Issue: lambdasistemi/cardano-tx-tools#48
- Epic: lambdasistemi/cardano-tx-tools#46
- Deferral context: [`specs/047-emitter-mvp-deferred/spec.md`](../047-emitter-mvp-deferred/spec.md)
- Harness: [`specs/033-rewrite-redesign-harness/spec.md`](../033-rewrite-redesign-harness/spec.md)
- In-house Turtle predicate decision (precedent): [`specs/033-rewrite-redesign-harness/research.md` D5](../033-rewrite-redesign-harness/research.md)
- Vocab: lambdasistemi/cardano-knowledge-maps#53 (merged 2026-05-19)
- 11 fixtures: `test/fixtures/rewrite-redesign/{01..11}-*/`

# Research — Rules loader

## R1 — No new RDF library

**Decision**: Author the loader as an in-house structural parser + serializer.
No new Haskell RDF library (`swish`, `rdf4h`, `rdf-turtle`, etc.) and no
shell-out to `rapper`. The Turtle subset the loader needs is bounded and
small.

**Rationale**:

- **Cost**. Adding `swish` or `rdf4h` pulls a multi-package transitive
  closure into `cardano-tx-tools`'s already-large dep graph. Neither
  library is on Hackage with a current upper bound for GHC 9.12.3; pinning
  either would mean another `source-repository-package` entry.
- **Scope**. The loader's job is bounded by FR-003: `@prefix`
  declarations, blank-node syntax, IRI references, string literals,
  integer literals, statement terminators, and `owl:imports` triples. We
  do not need SPARQL, query, reasoning, or named-graph features that the
  RDF libraries exist to provide.
- **Precedent**. The harness PR (#45) already rejected `swish`/`rdf4h`
  for the same reason; see
  [`specs/033-rewrite-redesign-harness/research.md`
  D5](../033-rewrite-redesign-harness/research.md). The
  `Fixtures.RewriteRedesign.TurtleShim` module proves the in-house path
  works for the structural-check half. This PR extends that path with a
  larger but still bounded subset.
- **Reviewability**. An in-house structural parser is easy to read; a
  library import hides the parsing behaviour behind a multi-page API
  surface that reviewers must understand to gate the byte-diff
  contract.
- **DSL stress-test policy** (per the project's CLAUDE.md): use
  in-house libs first; only file an upstream issue + skip cleanly if a
  needed combinator is missing.

**Alternatives**:

- **`swish`** — rejected — heavy transitive closure; surfaces SPARQL +
  reasoning we do not need.
- **`rdf4h`** — rejected — same closure cost; the Turtle parser is the
  only piece we'd use.
- **`raptor`/`rapper`** — rejected — adds a non-Haskell runtime
  dependency to the dev shell + CI, complicates Nix.
- **`librdf-turtle` C bindings via `inline-c`** — rejected — too heavy
  for the bounded subset.

**Turtle subset the loader supports** (in scope):

- `@prefix <prefix>: <iri> .`
- `@base <iri> .` (silently ignored; not used by the operator-authored
  rules but harmless if present)
- `:<localname>` and `<iri>` reference forms
- `_:<localname>` blank-node references
- String literals `"…"` with `\"` escapes only (no `\u`, no language
  tags, no datatype suffixes — we do not author them and would error if
  encountered)
- Integer literals `123` (only places they appear: `cardano:hasFee` etc.
  — not relevant to the entity overlay, but `cardano:hasFee` will appear
  in the body emitter's #58 surface and we keep the parser
  forward-compatible)
- Statement terminators `.` (end-of-subject), `;` (predicate
  continuation, same subject), `,` (object continuation, same subject +
  predicate)
- Comments `#` to end-of-line
- `owl:imports` triples — parsed structurally like any other triple

**Turtle subset out of scope** (parser rejects with structured error):

- Collections `( … )`
- Blank-node property lists `[ … ]`
- Language tags `@en`, `@de`
- Datatype suffixes `"42"^^xsd:integer`
- Multiline string literals `"""…"""`
- Boolean literals `true`/`false`

These are not authored anywhere in this PR's surface (operator rules
files or the emitted overlay). Rejecting them with a structured error
is safer than silently dropping the triple.

## R2 — Deterministic blank-node naming

**Decision**: `_:<entitySlug>_<roleSuffix>`, where `entitySlug` is the
first entity (in YAML/source order) to produce the `(leafType, bytesHex)`
pair, slugified (lowercased, `[^a-z0-9]` → `_`, collapsed repeated `_`,
trimmed leading/trailing `_`), and `roleSuffix` is the leafType with
only the first character lowercased (other characters preserved
verbatim — see plan.md D2 for the full leafType → roleSuffix table
covering all nine values the 11 fixtures author).

**The same `entitySlug` is also the entity's IRI local part**
(`:<entitySlug> a cardano:Entity ;`) — the slug is applied uniformly
to entity IRIs and to bnode prefixes. The operator's original `name:`
is preserved verbatim in `rdfs:label`. This was resolved as Q-001
Option A (slug-everywhere) post-analyzer; the alternative (Option B,
preserve entity IRI verbatim and slug only the bnode prefix) was
considered and rejected because:

- Two rules (slug + PN_LOCAL passthrough) are harder to maintain than
  one rule (slug everything).
- The text-match between `:usdm_control` and its bnodes
  `_:usdm_control_paymentScript` / `_:usdm_control_policy` is a
  tangible reviewer-readability win that compounds across the 11
  fixtures + future operator rule files.
- The existing artisan `expected.ttl` files use **inconsistent** IRI
  forms (most are slug-shaped already; `:usdm-control` keeps a dash);
  Option A removes the inconsistency by construction.
- `rdfs:label` already carries the operator's original spelling, so
  any display tool can show the authoring form without inferring
  from the IRI.

The Q-file + answer at
`/tmp/epic-046/tx-48/{questions,answers}/A-001-entity-iri-slug-application.md`
holds the durable record.

**Rationale**:

- **Byte-stable**. The carve-out `expected.entities.ttl` files need
  bnode names that are reproducible from inspection of `rules.yaml`
  alone. Source-order + entity-name + leaf-type satisfies that.
- **Reviewer-readable**. A reviewer can read
  `_:amaru_swap_order_paymentScript` and immediately know which entity
  declared the identifier and what role class the bytes represent.
  Hash-derived names (e.g., `_:bnode_a3f9b…`) are byte-stable but
  hostile to review.
- **Shared-identity intuitive**. When two entities reference the same
  (leafType, bytesHex), the first to declare it wins the name. That
  matches the OWL hasKey semantics ("entities are equal iff they
  share an identifier"); the reviewer sees that two entity blocks
  point at the same `_:amaru_swap_order_paymentScript` and infers
  identity sharing.

**Alternatives**:

- **Hash-derived** `_:bnode_<sha1(bytes)[:8]>` — rejected — opaque to
  reviewers; the byte-stable property is preserved but the readability
  cost dominates.
- **Sequential** `_:id1`, `_:id2`, `_:id3`, … — rejected — opaque,
  AND brittle when fixture YAML changes order (a future
  `rules.yaml` edit moving an entity changes every downstream bnode
  index).
- **Slugify-only without role suffix** `_:amaru_swap_order` — rejected
  — fails for entities producing two identifiers from the same name
  (a base address yields PaymentKey + StakeKey under the same entity);
  the suffix is required to disambiguate.
- **Match the existing artisan names** (`_:treasuryComplianceId`,
  `_:swapOrderPaymentId`) — rejected — names would require
  hand-tuning, which kills the deterministic-from-yaml goal *and*
  conflicts with the loader's first-entity-wins rule. The existing
  artisan names are dropped; the carve-outs use the loader's scheme;
  the existing `expected.ttl` files become #58's body-shape reference
  (and #58 will regenerate them in joint form).

## R3 — Canonical Turtle serializer byte shape

**Decision**: Fixed three-prefix header + entity blocks separated by
blank lines + indented `cardano:hasIdentifier _:…` continuation lines
+ identifier declaration blocks (subject-per-line, indented two
spaces) + trailing newline.

**Rationale**:

- **Reviewer alignment**. The existing `expected.ttl` files use this
  exact shape (compare `02-alice-bob-ada/expected.ttl` lines 1–33);
  matching it minimises the reviewer's mental diff between the carve-out
  and the original.
- **Diff-friendly**. A blank line between entity blocks means a `git
  diff` on `expected.entities.ttl` shows one entity's edit cleanly.
- **Byte-stable**. Every formatting choice is deterministic given the
  entity ordering: prefix order is fixed; identifier order follows
  document order; indent is two spaces; statement terminators are
  `.`/`;` per Turtle rules.

**Alternatives**:

- **N-Triples form** (one triple per line, fully qualified IRIs) —
  rejected — verbose; loses the entity-grouped readability that
  matches the existing fixtures.
- **No blank lines, compact form** — rejected — diff-hostile and
  reviewer-hostile.
- **Pretty-printer with line-wrapping at 80 cols** — rejected — adds
  serializer complexity (line-wrap is non-trivial in Turtle because of
  IRI continuation rules) without a byte-stability benefit.

## R4 — `from-address` decomposition uses ledger types

**Decision**: Reuse `Cardano.Tx.Diff.decodeBech32Address` (already
exported) to decode the bech32 address into a
`Cardano.Ledger.Address.Addr`, then case-match on the
`Cardano.Ledger.Credential.Credential` constructor of both the payment
and stake halves to produce `(leafType, bytesHex)` pairs.

**Rationale**:

- **No new deps**. `cardano-ledger-core` (which exports `Addr`,
  `Credential`, `KeyHash`, `ScriptHash`, `originalBytes`) is already
  in the dep tree.
- **Era-aligned**. `decodeBech32Address` already validates
  Conway-compatible address forms and rejects Byron bootstrap
  addresses with a structured error — exactly what the loader needs.
- **Tested elsewhere**. The function is used by `Cardano.Tx.Diff`'s
  CLI and is exercised by the existing test suite; reusing it inherits
  that coverage.

**Alternatives**:

- **Re-implement bech32 decoding inside the loader** — rejected —
  duplicate code path; high-bug-surface for a problem the codebase
  already solved.
- **Use the `cardano-addresses` library** — rejected — adds a new
  dep for a path the codebase already covers.

## R5 — Imports DFS algorithm

**Decision**: Three-state colour DFS (`White`/`Grey`/`Black`),
revisit of a `Grey` node = cycle. Final triples ordered by
reverse-topological visit order (children before parents) so the
"first declaration wins" merge passes parents' overrides through.

**Rationale**:

- **Classic**. Three-colour DFS is the standard cycle-detection
  algorithm; well-understood and easy to review.
- **Cycle path is computable**. When a `Grey` revisit is detected,
  the cycle path is the current DFS stack from the revisited node to
  the top, plus the revisited node again. That's exactly what
  `RulesImportCycle [<path1>, <path2>, ..., <path1>]` carries.

**Alternatives**:

- **Kahn's algorithm** (topological sort with indegree-decrement) —
  rejected — fails to extract the cycle path on detection; only tells
  you a cycle exists, not which one.
- **Iterative deepening** — rejected — pointless for a DAG of
  hand-written imports (depth is bounded by the operator's authoring).

## R6 — `tx-graph` executable name

**Decision**: New executable name `tx-graph`. New stanza in
`cardano-tx-tools.cabal` modelled on the existing `tx-diff` /
`tx-inspect` / `tx-sign` / `tx-validate` stanzas.

**Rationale**:

- **Consistency**. All other tx tools in the repo have a `tx-<verb>`
  name; `tx-graph` fits the family (the verb is "graph", in the sense
  of "produce the graph representation").
- **Forward-compat**. The same binary will host the body emitter
  (#58), the reasoner (#49), the views projector (#51) etc. as
  subcommands or additional flags. Naming the executable after the
  domain (graph) rather than the current PR's scope (rules) avoids
  renaming downstream.
- **Reserved**. A quick grep across the repo and the parent epic
  (#46) shows no other reservation for `tx-graph`.

**Alternatives**:

- **`tx-rules`** — rejected — too narrow; this PR is the rules
  loader but the executable will accumulate non-rules functionality.
- **`tx-rdf`** — rejected — too generic; the binary will not be an
  RDF Swiss-Army knife.
- **Subcommand on an existing binary** (e.g., `tx-diff graph …`) —
  rejected — `tx-diff` is structurally about diffing two transaction
  bodies; the rules/graph surface is a different verb.

## R7 — Carve-out authoring discipline

**Decision**: The 11 `expected.entities.ttl` carve-outs are authored
in the same slice that activates the byte-diff for each fixture. The
author writes them by *running the loader against `rules.yaml` and
capturing the output*, then byte-diffs against the captured file in
subsequent runs (i.e., the loader is its own golden generator). The
*initial* author must reason about whether the output is correct by
reading the YAML and the existing `expected.ttl`'s entity section side
by side.

**Rationale**:

- **No tautology**. The first-run capture means the carve-out
  *records* what the loader does; the subsequent byte-diffs *enforce*
  the recording. If the loader regresses, the byte-diff catches it.
- **No drift**. If the loader is *changed* intentionally (e.g.,
  naming algorithm tweak), the carve-outs are regenerated in the same
  slice; the regeneration is itself a tiny step that doesn't dilute
  bisect-safety.

**Alternatives**:

- **Hand-author the carve-outs without running the loader** —
  rejected — the deterministic-naming algorithm is non-trivial enough
  that hand-authoring would be error-prone for the complex fixtures
  (01, 09, 11).
- **Auto-generate at test time** (snapshot-style frameworks) —
  rejected — Hspec convention in this repo is hand-pinned goldens;
  the harness PR (#45) already enforces that convention. The
  byte-diff *is* a pinned golden, regenerated only by explicit
  developer action.

## R8 — YAML parser uses `aeson` + `yaml` (already in deps)

**Decision**: The YAML compiler decodes the file with
`Data.Yaml.decodeFileEither` into an `Aeson.Value`, then runs an
in-house `Parser` over the JSON-like structure to produce the
`NormalizedFile` intermediate.

**Rationale**:

- **No new deps**. `yaml` is already pulled in by the library
  (`build-depends: yaml`). The YAML loader cannot avoid using it.
- **Errors include file + line**. `Data.Yaml.ParseException` exposes
  `prettyPrintParseException` which produces a multi-line string with
  the offending YAML position. The loader wraps that into a
  `ParserError <file> <line> <msg>` structured error.
- **`Aeson.Value` intermediate**. Decoding to `Value` first (rather
  than directly to `RulesFile`-typed records) keeps the parser code
  decoupled from the YAML library's `FromJSON` typeclass and makes
  the parser easier to unit-test (you can construct `Value`s
  directly).

**Alternatives**:

- **HsYAML** — rejected — pulls in a different YAML parser and
  introduces a YAML-library divergence in the repo.
- **Direct `FromJSON` instance on a `RulesFile` record** — rejected
  — the `entities:` list of sum-type-shaped records (each entity
  picks one of `from-address`/`script`/`asset`/`keys+bytes`/`pool`/`drep`)
  is awkward to model as a single Haskell record; the structural
  parser over `Value` is cleaner.

## R9 — kmaps Phase A vocab IRI

**Decision**: The serializer emits the kmaps Phase A vocab IRI
`<https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#>`
verbatim as the `cardano:` prefix declaration, matching what every
existing `expected.ttl` carries.

**Rationale**:

- **Single source of truth**. The kmaps#53 PR landed 2026-05-19
  pinning this IRI; the harness `TurtleShim` enforces it; this PR's
  serializer matches it.
- **Phase A is sufficient**. The loader needs only the prefix
  binding, not the published axioms; the axioms are #49's surface.

**Alternatives**:

- **Pull a constant from the harness's `TurtleShim`** — rejected —
  the harness module is in `test/`, not `src/`; importing across
  the boundary couples production code to test code. The loader
  duplicates the constant in `Cardano.Tx.Graph.Rules.Load` (one line)
  and a unit test confirms the two stay in sync.
- **Make the prefix configurable** — rejected — over-engineering for
  this PR. The kmaps#53 IRI is *the* contract; a future need for
  prefix configurability would be a separate ticket with its own
  user story.

## R10 — `blueprints:` is loaded-then-validated but NOT serialized

**Decision**: The YAML compiler accepts `blueprints:` entries,
validates that each `script:` reference names an existing
`script`-typed entity (otherwise `BlueprintRefsUnknownScript`), and
stores them in the loader's return value. The Turtle serializer
*does not* emit `blueprints:` as triples in the entity overlay —
those triples belong to #50's surface (blueprint decoder).

**Rationale**:

- **Bounded surface**. This PR's overlay contract is entities +
  identifiers only. Adding blueprint triples here would either
  invent a vocab term (which kmaps#53 has not minted yet) or pull
  in the CIP-57 schema decode (which is #50). Neither belongs in
  this PR.
- **But validate now**. Catching `BlueprintRefsUnknownScript` at
  load time (in this PR) gives the operator an early error; the
  alternative (validate when #50 runs the decoder) defers the error
  by one ticket cycle.

**Alternatives**:

- **Drop `blueprints:` entirely** — rejected — the YAML grammar's
  surface is already shipping in #45's fixtures; the loader must at
  least round-trip them (silently) to be a faithful YAML reader.
  Validating-but-not-emitting is the in-between path.
- **Emit `blueprints:` as private namespace triples** — rejected —
  invents vocab the kmaps does not own; downstream consumers
  (#49, #50) would have to know to ignore them.

## R11 — `collapse:` is loaded but NOT validated and NOT serialized

**Decision**: The YAML compiler accepts `collapse:` entries, stores
them in the loader's return value untouched, and the Turtle
serializer does not emit them. Validation is deferred to #51 (views
ticket) because the validation rules (path syntax, `view:` modes,
nesting) are part of the views' surface.

**Rationale**:

- **Bounded surface**. Same as R10 — collapse semantics belong to
  views.
- **Round-trip though**. The loader's `RulesLoadResult` carries the
  raw `collapse:` list so #51's view runner can read it from the
  same loader call without re-parsing YAML.

**Alternatives**:

- **Validate collapse-rule path syntax now** — rejected — couples
  this PR to #51's path grammar, which is not yet defined.
- **Drop `collapse:` entirely** — rejected — same round-trip
  argument as R10.

## R14 — Strict Haddock-coverage enforcement deferred to a follow-up

**Decision**: T001a wires `nix develop --quiet -c cabal -O0 haddock
lib:cardano-tx-tools` into `gate.sh` so the haddock build itself is
gated (broken `'foo'` references, malformed `@since` tags, broken
`[link]` targets — anything haddock-parser-level — fail the gate
from the next slice onward). The gate does **NOT** enforce strict
per-export coverage (every export carries a docstring). Strict
enforcement is tracked as a follow-up ticket.

**Rationale** (resolved as T001a Q-001 Option A):

- `cabal haddock` does not fail on missing docstrings by default and
  the `werror` cabal flag T001c added does not propagate
  `-Wmissing-documentation` to the haddock build pipeline (the flag
  surfaces only inside the `common warnings` ghc-options, which apply
  to library compilation, not to haddock's coverage check).
- The existing codebase has ~76 pre-existing undocumented exports
  distributed across `Cardano.Tx.Diff` (37% coverage), `Cardano.Tx.Diff.Cli`
  (25%), `Cardano.Tx.Blueprint` (5%), `Cardano.Tx.Build` (81%), plus
  smaller gaps in `Cardano.Tx.Sign.{Envelope,Hex,Vault,Witness}`. Strict
  enforcement (e.g., adding `-Wmissing-documentation` under the
  `werror` flag) would immediately break the gate; closing the gap
  requires writing ~76 substantive docstrings (purpose, parameters,
  return value, side effects) which is editorial content work
  unrelated to the rules loader.
- The Q-002 override on `cabal check` applied to a mechanical fix
  (cabal upper bounds + flag plumbing). Strict Haddock coverage is
  substantive editorial work — the orchestrator should authorize that
  as its own ticket where the author can focus on docstring quality.
- FR-016 *for new code in this PR* (`Cardano.Tx.Graph.Rules.Load`
  and its internal submodules) is still enforced — by review
  convention. Every new export in the rules loader carries a
  docstring. The gate's `cabal haddock` verifies those docstrings
  parse correctly.

**Alternatives**:

- **`--haddock-options="--fail-on-warnings"`** — rejected — would
  fail immediately due to pre-existing haddock warnings (ambiguous
  identifiers, out-of-scope link targets) across the codebase.
- **Add `-Wmissing-documentation` under the `werror` flag** — rejected
  — would fail the build on ~76 pre-existing undocumented exports.
- **Sweep the 76 missing docstrings inside this PR** — rejected as
  scope creep (the rules loader is one feature; docstring sweep is
  another).

The Q-file + answer at
`/tmp/epic-046/tx-48/subagents/T001a/{questions,answers}/A-001-haddock-missing-docs-not-enforced.md`
holds the durable record.

## R13 — Constitution-compliance sweep happens in this PR (not as a follow-up)

**Decision**: T001b (PvP upper bounds across every dep stanza in
`cardano-tx-tools.cabal`) and T001c (`werror` cabal flag per
cardano-node-clients pattern) land **inside #48**, ahead of T001a's
gate extension. SC-007 (`cabal check` clean) is an in-scope
acceptance criterion, not a deferred follow-up.

**Rationale** (resolved as Q-002 Option B under user override):

- The constitution's Principle IV mandates `cabal check` clean at
  all times. The existing repo violates that in two ways
  (missing-upper-bounds across every stanza; unguarded `-Werror`
  in the `warnings` common stanza). The natural orchestrator
  instinct is to defer constitution-compliance work to a separate
  PR. The user override on Q-002 says: don't defer.
- Deferred constitution work tends to pile up forever. Closing it
  inside the PR that surfaced it is the discipline that keeps the
  constitution operational rather than aspirational.
- The dep-bounds sweep + werror flag plumbing are mechanical
  (T001b + T001c can each be one subagent commit). The PR grows by
  ~80 lines of cabal + a flake-side flag wire, not by behaviour.
- T001a's `cabal check` step now has a green path to enforce on
  every subsequent slice; without T001b + T001c, the step would
  trip immediately.

**Alternatives**:

- **Option A — defer SC-007** (my original recommendation) —
  rejected by user override. Pre-existing violations are not a
  free pass to ship more code on top of them.
- **Option C — `cabal check` softening** (grep-and-ignore) —
  rejected as fragile; hides future regressions.

The Q-file + answer at
`/tmp/epic-046/tx-48/{questions,answers}/A-002-defer-cabal-check-sc007.md`
holds the durable record of the override.

## R12 — Diamond imports merge by triple-equality

**Decision**: When a node is `Black` (already visited) and is
imported again from a sibling DFS path, its triples are *not*
re-merged — they're already in the merged triple set. The "merge"
operation on the triple list is *append* during the DFS post-order
visit; duplicate-triple detection happens after the merge by
deduplicating exact triple matches (subject, predicate, object).

**Rationale**:

- **Correctness**. Two paths to the same imported file produce
  identical triples on disk; deduplication by exact equality is the
  right semantics.
- **Cheap**. The fixture corpus has at most a handful of imports;
  even quadratic dedup is fine. A `Data.Set` of `Triple` makes it
  linear-ish.

**Alternatives**:

- **Reject diamond imports** — rejected — too strict; operators
  legitimately want to compose shared overlays.
- **Track provenance per triple** — rejected — extra surface this PR
  doesn't need; deduplication by structural equality is enough.

# Feature Specification: tx-inspect — shared-substrate transaction renderer with two-stage rewriting (collapse + rename)

**Feature Branch**: `032-tx-inspect`
**Created**: 2026-05-18
**Status**: Draft
**Input**: GitHub issue #32 — "A new `tx-inspect` executable that prints a human-readable view of a resolved Conway transaction. The renderer applies a two-stage rewriting pipeline built on the existing diff machinery: (1) Collapse — existing `CollapseRule`s factor repeated structural skeletons into a named shape that exposes only per-instance variable slots; (2) Rename — a new rule kind substitutes leaf identifiers (payment addresses, script hashes) with names from an address book. Stage order is fixed: collapse first, rename second. `tx-inspect` shares both code and language with `tx-diff`."

## Clarifications

### Session 2026-05-18

- Q: What is the exact module name for the new sibling module that defines `RenameRule(s)` and the wrapper `RewriteRules`? → A: `Cardano.Tx.Rewrite`. Sibling of `Cardano.Tx.Diff`. Neutral over stage count — covers both `CollapseRules` (stage 1) and `RenameRules` (stage 2) today, leaves room for a future stage without renaming.
- Q: What top-level YAML shape does a unified rewriting-rules document use, given that existing collapse-only YAML must parse unchanged? → A: A top-level object carrying optional `collapse:` and `rename:` keys (alongside the existing optional `version:` and `views:` keys already accepted by `parseCollapseRulesYaml`). The existing parser already objectified the document — `{ version?, views?, collapse?: [...] }` — so the rename section is simply an additional optional key on the same object. Either of `collapse:` and `rename:` may be omitted; a missing section means "no rules for that stage". Stage order is enforced by the engine and is independent of the order of keys in the document. *(Correction over the original answer in this session: an earlier draft of this clarification described a "legacy bare-list" form that does not exist — every existing collapse-rules YAML is already an object. Code inspection of `parseCollapseRulesYaml` in `src/Cardano/Tx/Diff.hs` confirms.)*
- Q: What shape does a single `RenameRule` entry take in the `rename:` section? → A: A kind-tagged record: `{ kind: address | script, key: <bech32-or-hex>, name: <string> }`. `kind` discriminates payment-address vs script-hash matches; `key` is the canonical text form (bech32 for addresses, hex for script hashes); `name` is the display string. New kinds in follow-up tickets (stake-address, pool-id, DRep, asset policy, asset name) extend the `kind` enum without changing the entry shape.
- Q: What does a `kind: address` rename rule match against in a transaction's payment-bearing fields (body inputs after resolution, body outputs, withdrawals, certificates)? → A: Both, with a syntactic distinction on the rule. An address rule carries an additional `match:` field — `match: full` matches the full bech32 address exactly (payment credential + stake credential together); `match: payment` matches on the payment credential only, ignoring the stake credential. A missing `match:` defaults to `payment` (the dominant treasury-work case: one rule covers every stake variant of the same payment script). Either form accepts a bech32 string in `key:` as the canonical user-pasteable input form; the loader extracts the payment credential when `match: payment`.

### Planning-phase correction 2026-05-18 (S1 dispatch)

Code inspection of `src/Cardano/Tx/Diff.hs` (during S1 planning) showed that the diff walker uses `ConwayDiffValue`, not `OpenValue`. `OpenValue` is the user-data substrate (datums / redeemers / blueprint-decoded plutus data) and is one of `ConwayDiffValue`'s constructors (`ConwayOpenValue OpenValue`). The full Conway transaction is never projected to `OpenValue`. Correction to FR-008:

The "same code path" the spec demands is the projection + `RenderTrie` / `renderForest` / `renderJsonValue` primitives — not a single function name. Both `tx-diff`'s diff renderer and `tx-inspect`'s single-tx renderer call into the same `conwayDiffProjection` (and recursively `openValueProjection` for OpenValue subtrees), and both feed the same render primitives. The top-level entry tx-inspect's `Main.hs` calls is `renderConwayTxHuman :: HumanRenderOptions -> TxDiffOptions -> ConwayTx -> Text` (new in S1). `renderOpenValueHuman :: HumanRenderOptions -> OpenValue -> Text` is also added as a primitive — it renders an OpenValue subtree directly, which the rename layer (S3) needs when it walks datums. No `ConwayTx → OpenValue` converter is introduced (Aeson → OpenValue would be lossy across `Null`/`Bool`/non-integer `Number` leaves).

The rename layer's site list (payment addresses + script hashes per FR-009) walks `ConwayDiffValue`, not `OpenValue` — the addresses + script hashes are body/witness/ref-script leaves, not datum leaves. Rename application design is deferred to S3 planning. Existing FR-008 text below remains correct in spirit (one shared substrate; no forked walker); only the function-name was wrong.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Treasury reviewer inspects an Amaru swap transaction with both stages on (Priority: P1)

A treasury reviewer holds a CBOR-encoded Conway transaction representing one of the Amaru treasury **swap** transactions. They want to read it as a structured, named report rather than a wall of hashes and positional fields. They run:

```bash
tx-inspect tx.cbor --rules rules/amaru-treasury.yaml
```

Each swap output appears collapsed into a named `Swap` shape whose counterparty, asset, and script slots show their address-book names instead of raw hashes. The rest of the transaction renders structurally, with any Amaru-treasury identifier appearing under its address-book name and any unknown identifier rendering verbatim.

**Why this priority**: This is the load-bearing operator command — the existence of `tx-inspect` as a fifth shipped CLI. Issue #32 names this the paramount user story explicitly. It also gates the predicate DSL in #15: once every salient leaf has a name, predicates like `o.counterparty == "genius_yield_pool"` become expressible.

**Independent Test**: Render a representative Amaru treasury swap transaction with `rules/amaru-treasury.yaml` (collapse + rename) and verify the golden output: each swap output appears as the named `Swap` shape, and every Amaru-treasury identifier inside the exposed slots appears under its book name.

**Acceptance Scenarios**:

1. **Given** an Amaru treasury swap CBOR transaction and a rewriting-rules YAML containing both collapse and rename rules for the Amaru treasury surface, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the human-readable output shows each swap output as the named `Swap` shape and every Amaru-treasury identifier as its book name in the exposed slots; unknown identifiers render verbatim; exit code is 0.

---

### User Story 2 — Collapse-only rendering (Priority: P2)

A reviewer with only a collapse-rules YAML (no rename section) — for example, the same rules file an existing `tx-diff` invocation already uses — runs `tx-inspect` on the same Amaru treasury swap CBOR transaction. The output collapses each swap output into the named `Swap` shape, but raw hashes remain verbatim inside the exposed slots. No rename substitution occurs.

**Why this priority**: P2 because the collapse-only path proves the migration is **additive** — existing collapse-only YAML files keep working with no rename section required. This is the backwards-compatibility story for the unified rewriting-rules language and the migration safety net for every consumer that already feeds a collapse-rules YAML to `tx-diff`.

**Independent Test**: Render the same swap transaction with a rules file containing only collapse rules; assert the golden output collapses swap outputs to the named `Swap` shape and that every raw hash in the exposed slots is rendered verbatim.

**Acceptance Scenarios**:

1. **Given** an Amaru treasury swap CBOR transaction and a rewriting-rules YAML containing **only collapse rules**, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** each swap output appears as the named `Swap` shape and every identifier in the exposed slots appears as its raw hash (no rename substitution); exit code is 0.
2. **Given** an existing collapse-only YAML file already used by `tx-diff` today, **When** that same file is fed unchanged to `tx-inspect`, **Then** parsing succeeds and the rendered output is identical to what `tx-diff` would produce for one side of the diff against the same transaction.

---

### User Story 3 — Rename-only rendering (Priority: P2)

A reviewer with only a rename-rules YAML (no collapse section) runs `tx-inspect` on the same Amaru treasury swap CBOR transaction. The structural shape of the transaction renders uncollapsed (every output, witness, certificate, withdrawal appears as its full structural tree), but every Amaru-treasury identifier — payment addresses in body inputs (after resolution), body outputs, withdrawals, certificates, and script hashes in the body, witness set, and reference scripts — appears under its address-book name. Unknown identifiers render verbatim.

**Why this priority**: P2 alongside collapse-only. Together with User Story 2, the two prove the two stages are **independently exercisable** — neither stage requires the other to produce useful output, and the engine enforces stage order without requiring both stages to be present.

**Independent Test**: Render the same swap transaction with a rules file containing only rename rules; assert the golden output renders the transaction structurally uncollapsed but with every Amaru-treasury identifier appearing as its book name.

**Acceptance Scenarios**:

1. **Given** an Amaru treasury swap CBOR transaction and a rewriting-rules YAML containing **only rename rules**, **When** the reviewer runs `tx-inspect <tx> --rules <yaml>`, **Then** the transaction renders structurally uncollapsed, every Amaru-treasury identifier appears as its book name, unknown identifiers render verbatim, and exit code is 0.

---

### User Story 4 — Shared substrate proven by `tx-diff` on two swap transactions (Priority: P2)

The same `rules/amaru-treasury.yaml` is fed to `tx-diff` over two Amaru treasury swap transactions. The collapse + rename pipeline applies identically to both sides of the diff. The shared-substrate property holds in code (no forked walker, no copy-pasted render functions) and in language (one YAML file feeds both tools).

**Why this priority**: P2 because the **shared substrate** is what unblocks predicate DSL #15 and what justifies the additive refactor cost. If the two tools had to maintain separate copies of either the renderer or the YAML language, the design has failed. This story is what fails loudly if a later edit forks the substrate.

**Independent Test**: Run `tx-diff <tx-a> <tx-b> --rules rules/amaru-treasury.yaml` against two Amaru treasury swap transactions; assert each side of the diff renders identically to the corresponding `tx-inspect <tx> --rules rules/amaru-treasury.yaml` output.

**Acceptance Scenarios**:

1. **Given** two Amaru treasury swap CBOR transactions and `rules/amaru-treasury.yaml`, **When** the reviewer runs `tx-diff <tx-a> <tx-b> --rules <yaml>`, **Then** each side of the diff applies collapse + rename identically and produces output that matches `tx-inspect <tx> --rules <yaml>` for the corresponding transaction.

---

### Edge Cases

- **Unknown identifier under rename**: A leaf identifier (payment address or script hash) is not present in any rename rule. The renderer must emit the raw hash verbatim — rename is best-effort, never a failure, and never silently drops information.
- **Address rule with `match: payment` against a base address whose stake credential differs**: The matcher MUST match (only the payment credential is compared), so the same payment-script address renders under the same name regardless of its stake credential. The acceptance scenarios cover this with the Amaru treasury swap, whose payment script is paired with multiple stake credentials in real fixtures.
- **Collapse-only YAML fed to `tx-inspect`**: A rules file with no rename section parses unchanged and renders with collapse applied, raw hashes verbatim in the exposed slots.
- **Rename-only YAML fed to `tx-inspect`**: A rules file with no collapse section parses unchanged and renders structurally uncollapsed with rename applied to leaves.
- **Empty rules YAML fed to `tx-inspect`**: A well-formed but empty rules file renders the transaction with no rewriting applied (equivalent to the current bare-renderer output of one side of `tx-diff`).
- **Unresolved input under rename**: A body input whose UTxO did not resolve has no `.resolved.address` to rename. The renderer must still emit the input structurally (unresolved marker, raw txin reference) and not crash.
- **`--version` and `--help`**: `tx-inspect --version` prints `tx-inspect <semver>` and exits 0; `tx-inspect --help` prints usage. Both work via the existing `github-release-check` `withCli` helper, matching the other four executables.
- **Stale-cache upgrade banner**: A run of `tx-inspect` with a contrived stale-version cache prints the upgrade banner on stderr after the action returns, matching the per-exe behavior already shipped by the other four CLIs. Setting `TX_INSPECT_NO_UPDATE_CHECK=1` suppresses the check (no GitHub network hit, no banner).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A new executable `tx-inspect` MUST exist under `app/tx-inspect/Main.hs`, wired into `cardano-tx-tools.cabal`, the flake's `apps` output, the justfile, and the release flow, matching the four executables already shipped (`tx-validate`, `tx-diff`, `tx-sign`, `cardano-tx-generator`).
- **FR-002**: `tx-inspect` MUST accept a Conway transaction in the same input forms `tx-validate` accepts today — a CBOR file path positional and/or hex input via stdin or `--in`.
- **FR-003**: `tx-inspect` MUST resolve transaction-input UTxOs via the existing `Cardano.Tx.Diff.Resolver` chain (`Cardano.Tx.Diff.Resolver.Web2`, `Cardano.Tx.Diff.Resolver.N2C`) using the same `--n2c-socket-path` / `--web2-…` flag surface `tx-diff` already exposes.
- **FR-004**: A new sibling module `Cardano.Tx.Rewrite` MUST define the two-stage rewriting types: the existing `CollapseRule(s)` MUST be reused unchanged for stage 1; a new `RenameRule` and `RenameRules` MUST be defined for stage 2; a wrapper type `RewriteRules` carrying both stages MUST be defined for the unified document.
- **FR-005**: The refactor introducing `RenameRule(s)` and the wrapper MUST be additive only: no rename or API change to `CollapseRule(s)`, `OpenValue`, `DiffPath`, or `HumanRenderOptions`. Every existing call site MUST continue to compile and behave unchanged.
- **FR-006**: The engine MUST enforce stage order — collapse runs first, rename runs after on the leaves that collapse has surfaced — independently of the order rules appear in the YAML file. Stage order MUST NOT be configurable from the YAML.
- **FR-007**: `tx-inspect --rules PATH` MUST load a unified rewriting-rules YAML document. The document is the same top-level object that `parseCollapseRulesYaml` already accepts — `{ version?, views?, collapse?: [CollapseRule] }` — extended with an additional optional `rename:` key carrying a list of `RenameRule` entries. Existing collapse-only YAML files MUST parse unchanged (the new loader does not change the meaning of `version`, `views`, or `collapse`; adding `rename:` is strictly additive). Either `collapse:` or `rename:` may be omitted; a missing or empty section means "no rules for that stage". The order of the `collapse:` / `rename:` keys in the document MUST NOT affect rendering — stage order is engine-enforced, not document-order-driven.
- **FR-008**: The renderer used by `tx-inspect` MUST be the **same code path** as one side of `tx-diff`'s human renderer. The shared core MUST be extracted into the new module (or a sibling) and consumed by both `app/tx-inspect/Main.hs` and `app/tx-diff/Main.hs`. There MUST be no forked `OpenValue` walker and no copy-pasted render functions.
- **FR-009**: Rename rules MUST apply to **payment addresses** at every site they appear in a Conway transaction — body inputs after resolution, body outputs, withdrawals, and certificates — and to **script hashes** at every site they appear — body, witness set, and reference scripts. For `kind: address` rules, the `match:` field selects the granularity (`full` matches the entire bech32 address byte-for-byte; `payment` matches the payment credential only and ignores the stake credential). Missing `match:` defaults to `payment`. For `kind: script` rules the match is always exact on the hex script hash.
- **FR-010**: Substitution MUST be best-effort: identifiers not present in any rename rule MUST render verbatim. An unknown identifier MUST NOT cause `tx-inspect` to fail, error, or omit the surrounding structural element.
- **FR-011**: A checked-in file `rules/amaru-treasury.yaml` MUST cover both stages for the Amaru treasury swap fixtures: at least one collapse rule for the swap output shape, and rename rules for every Amaru-treasury identifier used in the checked-in fixtures.
- **FR-012**: A unit/golden test (Golden #1, **pure collapse**) MUST drive `tx-inspect` on a real Amaru treasury swap transaction with a rewriting-rules file containing **only collapse rules** and assert the golden output where each swap output appears as the named `Swap` shape and raw hashes remain verbatim in the exposed slots.
- **FR-013**: A unit/golden test (Golden #2, **pure rename**) MUST drive `tx-inspect` on the same transaction with a rewriting-rules file containing **only rename rules** and assert the golden output where every Amaru-treasury identifier appears as its book name but the transaction structure is rendered uncollapsed.
- **FR-014**: A unit/golden test (Golden #3, **both stages**) MUST drive `tx-inspect` on the same transaction with `rules/amaru-treasury.yaml` (collapse + rename) and assert the golden output where the swap outputs appear as the named `Swap` shape and every Amaru hash inside the exposed slots appears as its book name. The same output MUST be reproduced by `tx-diff` with the same rules file across two such transactions, proving language sharing.
- **FR-015**: `docs/tx-inspect.md` MUST document the executable: input forms, `--rules` flag, resolver flags, output shape, exit codes, and the two-stage pipeline. The rename rule kind and the two-stage pipeline MUST be documented as a new section in the existing rewriting-rules grammar doc (the doc that currently documents `CollapseRule`'s YAML grammar), **not** in a separate file.
- **FR-016**: `tx-inspect --version` and `tx-inspect --help` MUST work via the existing `github-release-check` `withCli` helper, matching the other four executables. `--version` MUST print `tx-inspect <semver>` (single line, exit 0). `TX_INSPECT_NO_UPDATE_CHECK=1` MUST suppress the upgrade banner check.
- **FR-017**: `tx-inspect` MUST be wired into the release pipeline (cabal-release / Docker / AppImage / Homebrew tap, as appropriate to the existing release flow) so a normal release ships `tx-inspect` alongside the other four CLIs.

### Key Entities *(include if feature involves data)*

- **`CollapseRule`** *(existing)* — A rule that recognises a repeated structural skeleton in an `OpenValue` tree and replaces it with a named shape exposing only per-instance variable slots. Reused unchanged for stage 1; not renamed or modified by this feature.
- **`CollapseRules`** *(existing)* — Ordered collection of `CollapseRule` values loaded from a YAML document. Reused unchanged.
- **`RenameRule`** *(new)* — A rule that maps a leaf identifier (payment address or script hash) to a human-readable name from an address book. Shape: `{ kind: address | script, key: <bech32-for-address | hex-for-script>, name: <string>, match?: full | payment }`. `match:` is meaningful for `kind: address` only (defaults to `payment`); for `kind: script` the match is always exact on the hex script hash. Substitution is best-effort; an unknown identifier renders verbatim.
- **`RenameRules`** *(new)* — Collection of `RenameRule` values loaded from the `rename:` section of a unified rewriting-rules YAML document.
- **`RewriteRules`** *(new)* — Wrapper carrying both `CollapseRules` (stage 1) and `RenameRules` (stage 2). Loaded from a single unified YAML document. Stage order is enforced by the engine, not by the document.
- **`OpenValue`** *(existing)* — The open tree built by blueprint decoding; the universe both stages operate over. Not modified by this feature.
- **`DiffPath`** *(existing)* — Dot-separated path used by collapse rules and (transitively) by rename rules to locate leaves. Not modified.
- **`HumanRenderOptions`** *(existing)* — Renderer configuration consumed by the shared render core. Not modified.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A treasury reviewer reading an Amaru treasury swap transaction with `tx-inspect <tx> --rules rules/amaru-treasury.yaml` sees zero raw payment-address hashes and zero raw script hashes inside the exposed swap-output slots; every such identifier appears under its address-book name.
- **SC-002**: Every collapse-only rules YAML file that parses today via `parseCollapseRulesYaml` continues to parse and render identically under `tx-inspect`'s new loader (zero parsing regressions).
- **SC-003**: The renderer code path is shared verifiably: the diff between the bytes written by `tx-inspect <tx> --rules <yaml>` and one side of `tx-diff <tx-a> <tx-b> --rules <yaml>` (for the matching side) is empty for the three Amaru treasury swap golden fixtures.
- **SC-004**: The two-stage pipeline is enforced by the engine: a rules file whose `rename:` key appears before `collapse:` renders identically to a file with the reverse key order. Stage order is invariant under YAML document order.
- **SC-005**: `tx-inspect --version` returns `tx-inspect <semver>` on a single stdout line, exit 0, with the version pulled from the same `Paths_cardano_tx_tools.version` that the upgrade-banner check uses — matching the other four CLIs verbatim.
- **SC-006**: An unknown identifier inside a transaction produces verbatim hash output and a successful `tx-inspect` run (exit 0). Rename never causes a failure or a missing structural element.
- **SC-007**: The new executable ships through the existing release flow with no manual release-pipeline edits beyond the additive wiring described in FR-017.

## Assumptions

- The representative Amaru treasury swap CBOR fixture(s) will be fetched on-chain via the existing `amaru-treasury-tx` inspect path and checked into `test/fixtures/`, alongside the resolved-UTxO data needed by the resolver chain. The exact fixture count, file naming, and resolved-UTxO storage shape is a planning decision, not a spec decision.
- The "address book" is **not** a separate file format. It is a section (or rule-tag) inside the unified rewriting-rules YAML, owned by the same file format that already carries collapse rules today.
- The Amaru-treasury rename rules cover at minimum: the script hashes for the swap validator(s), the payment addresses of the treasury party, and the payment addresses of the counterparties named in the checked-in fixtures.
- The shared-substrate refactor (extracting the `tx-diff` human-render path into the new module / sibling) is additive: every existing `tx-diff` invocation produces byte-identical output before and after the refactor when no rename section is present.
- `tx-inspect`'s resolver flag surface mirrors `tx-diff`'s exactly (`--n2c-socket-path`, the `--web2-…` flags currently in `Cardano.Tx.Diff.Cli`). No new resolver kind is introduced by this feature.
- Single `--rules` file per invocation; merging multiple rules files is out of scope (see Out-of-Scope below).

## Out of Scope

The following are explicitly **not** delivered by this feature and remain available as separate follow-up tickets:

- A separate address-book file format. The book is rename rules inside the unified rewriting-rules YAML.
- Stage reordering, conditional stages, or rule pipelines beyond collapse → rename. Future stages (e.g. derive, summarise) are separate tickets.
- Rename rules for stake addresses, pool IDs, DRep IDs, asset policy IDs, asset names — follow-up tickets, one identifier family per ticket.
- URL-fetched / remote / signed rewriting-rules files — file path only.
- CLI subcommands for editing / merging rewriting-rules files.
- Substituting names inside `tx-sign` or `cardano-tx-generator` output — separate tickets per consumer.
- Renaming or refactoring the existing `CollapseRule` / `CollapseRules` types. Additive only.
- The invariant / predicate language itself (#15).
- Conflict resolution when two rename rules map the same identifier to different names — single `--rules` file per invocation here.

## Command Recovery

Per the resolve-ticket command-recovery rule, this feature ships the operator command and a smoke/proof for the same command path. The operator command is:

```bash
tx-inspect <tx-input> --rules <path> [--n2c-socket-path <socket> | --web2-… <args>]
```

The smoke proof for the command (the golden tests in FR-012/13/14, plus the `--version` / `--help` exit-code checks) invokes the same `tx-inspect` executable end-to-end through the same `main`. There is no test-only renderer entry point: golden tests drive the production command path.

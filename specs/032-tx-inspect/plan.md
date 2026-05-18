# Implementation Plan: tx-inspect — shared-substrate transaction renderer with two-stage rewriting

**Branch**: `032-tx-inspect` | **Date**: 2026-05-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/032-tx-inspect/spec.md`

## Summary

Add a fifth shipped CLI, `tx-inspect`, that prints a human-readable view of a single resolved Conway transaction by feeding it through the same render core that `tx-diff` already uses for one side of its diff output. A new sibling module `Cardano.Tx.Rewrite` defines the two-stage rewriting types — `RewriteRules = { collapse :: CollapseRules, rename :: RenameRules }` — and the unified YAML loader. The existing `CollapseRule(s)` machinery is reused unchanged (stage 1); a new `RenameRule` data type (kind-tagged: `address | script` with `match: full | payment` on address rules) is added (stage 2). Stage order — collapse first, rename second — is enforced by the engine, not by document order. A checked-in `rules/amaru-treasury.yaml` covers both stages for the Amaru treasury swap fixtures, which are the load-bearing acceptance target.

The work lands as **six bisect-safe vertical slices** (S1–S6) plus the final orchestrator `chore: drop gate.sh` (S7). Each slice is one subagent run = one commit. Order is end-to-end smallest-feature-first: S1 ships the executable with the bare render path (empty rules → verbatim render), S2 plumbs collapse through it, S3 adds rename, S4 adds the Amaru fixtures + shared-substrate cross-check, S5 documents, S6 wires release.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (existing pin, constitution Operational Constraints).
**Primary Dependencies**: Existing `cardano-tx-tools` library deps. The new module `Cardano.Tx.Rewrite` lives in the same library and uses the same deps `Cardano.Tx.Diff` already pulls in (`aeson`, `yaml`, `bech32`, `cardano-ledger-*`, `text`, `bytestring`). No new direct dep is introduced.
**Storage**: None at runtime. Test fixtures on disk under `test/fixtures/amaru-treasury-swap/`.
**Testing**: existing `unit-tests` test-suite (golden tests under `test/Cardano/Tx/InspectSpec.hs`); per-slice live-boundary smoke in `gate.sh` (`cabal run -v0 -O0 tx-inspect …`).
**Target Platform**: Linux/Darwin via `haskell.nix`.
**Project Type**: Haskell library + five shipped executables (post-feature).
**Performance Goals**: N/A. Render of a single tx is bounded by the existing `OpenValue` walker; no new hot path.
**Constraints**: strictly additive at every existing public surface (`CollapseRule(s)`, `OpenValue`, `DiffPath`, `HumanRenderOptions`, `parseCollapseRulesYaml`, `renderDiffNodeHuman[With]`); `tx-diff` produces byte-identical output before and after the shared-core extraction when no `rename:` section is present.
**Scale/Scope**: 1 new module (`Cardano.Tx.Rewrite`, ~300 LOC), 1 new executable (`app/tx-inspect/Main.hs`, ~150 LOC), 1 new spec module + golden helpers (~300 LOC), 1 new rules YAML (`rules/amaru-treasury.yaml`, ~50 LOC), 2 new fixture transactions + resolved-UTxO files, 1 new docs page + 1 new section in the existing rewriting-rules grammar doc. Net diff probably 1500–2000 LOC including golden files.

## Constitution Check

The constitution's seven core principles apply. Walked one by one:

- **I. One-Way Dependency On Node-Clients** — No new `cardano-node-clients` import is introduced. `tx-inspect` reuses `Cardano.Tx.Diff.Resolver.N2C` which already lives in the `n2c-resolver` sublibrary. No reverse arrow created. **Pass.**
- **II. Module Namespace Discipline** — The new module is `Cardano.Tx.Rewrite`, under `Cardano.Tx.*`. No `Cardano.Node.Client.*` introduced. **Pass.**
- **III. Conway-Only Era** — `tx-inspect` accepts Conway transactions only (same decoder chain as `tx-diff`). **Pass.**
- **IV. Hackage-Ready Quality** — Every new export carries Haddock; module headers use the canonical `{- | Module … -}` form; `cabal check` is in `just ci`. `README.md`/`CHANGELOG.md` already in `extra-doc-files`; new `docs/tx-inspect.md` is a docs-only file, not packaged. **Pass.**
- **V. Strict Warnings, No `-Werror` Escape Hatches** — The new module + executable build under `-Wall -Werror -Wunused-imports -Wmissing-export-lists -Wname-shadowing -Wredundant-constraints` (gated behind the existing `werror` flag). **Pass.**
- **VI. Default-Offline Semantics** — `tx-inspect` defaults to fully offline mode (no resolver chain is invoked unless `--n2c-socket-path` or `--web2-…` is supplied). Golden tests run against a static-file `Resolver` (test-only, lives in `test/`); no network access. **Pass.**
- **VII. TDD With Vertical Bisect-Safe Commits** — Six slices below are each RED+GREEN-folded; each commit on the branch compiles, tests green, and ships the per-slice live-boundary smoke. Constitution-Compliant. **Pass.**

**Operational Constraints**:
- GHC 9.12.3 via `haskell.nix` — unchanged.
- `nix flake check --no-eval-cache` local gate — extended by per-slice smoke in `gate.sh`.
- Lint stack (fourmolu, hlint, cabal-fmt) — already in `gate.sh` per S0 (`chore: add gate.sh`).
- Released binaries that perform HTTPS bundle a CA store — `tx-inspect` does not perform HTTPS itself; the web2 resolver path is shared with `tx-diff` and already CA-bundled via the existing `makeWrapper` in the release flake.

**Resolver Architecture** — `tx-inspect` reuses `Cardano.Tx.Diff.Resolver`'s `Resolver`-record-of-functions chain unchanged. No new resolver kind is introduced. Golden tests use a test-only `staticResolver` that loads `utxo.json` (the same JSON shape `cardano-cli query utxo --output-json` emits) — this is a test helper under `test/`, not part of the production resolver chain.

**No exceptions tracked.** Complexity Tracking table at the bottom is empty.

## Project Structure

### Documentation (this feature)

```text
specs/032-tx-inspect/
|-- plan.md                         # this file
|-- spec.md                         # P1/P2 user stories, FR-001..FR-017
|-- research.md                     # Phase 0 output (research decisions)
|-- data-model.md                   # Phase 1 output (RenameRule + RewriteRules)
|-- quickstart.md                   # Phase 1 output (operator-facing quick path)
|-- contracts/                      # Phase 1 output (rules-yaml-grammar.md)
|-- checklists/
|   `-- requirements.md             # spec quality checklist
`-- tasks.md                        # /speckit.tasks output (next phase)
```

### Source code (repository root)

```text
src/Cardano/Tx/
  Rewrite.hs                        # NEW — RewriteRules, RenameRule(s), parseRewriteRulesYaml,
                                    #       applyRewriteRules (collapse → rename), Haddock
  Diff.hs                           # EDITED — minimal additive changes only (CORRECTED 2026-05-18 per R1):
                                    #   * `parseCollapseRulesYaml` reused unchanged (no edit)
                                    #   * NEW `renderConwayTxHuman :: HumanRenderOptions ->
                                    #     TxDiffOptions -> ConwayTx -> Text` — the top-level
                                    #     entry tx-inspect's Main calls. Walks `conwayDiffProjection`
                                    #     into a `RenderTrie` reusing the existing render
                                    #     primitives. The diff renderer is NOT touched
                                    #     (tx-diff goldens trivially byte-identical).
                                    #   * NEW `renderOpenValueHuman[With] :: HumanRenderOptions
                                    #     -> OpenValue -> Text` — a primitive that renders an
                                    #     OpenValue subtree directly. Reuses the same render
                                    #     primitives. The rename layer in S3 uses it for
                                    #     datum subtrees.
                                    #   * `HumanRenderOptions` gains `humanRenameRules ::
                                    #     Maybe RenameRules` field (additive; defaults to
                                    #     Nothing in `defaultHumanRenderOptions`). Pre-existing
                                    #     consumers compile unchanged because the field has a
                                    #     default in record-update syntax. No application
                                    #     code in S1 — S3 wires the rename layer into render.
app/tx-inspect/Main.hs              # NEW — withCli + versionOption, --rules loader,
                                    #       resolver chain, renderOpenValueHuman, exit 0
test/Cardano/Tx/
  InspectSpec.hs                    # NEW — golden tests for tx-inspect (S1 baseline + S2/S3/S4)
  Rewrite/
    LoadSpec.hs                     # NEW — `parseRewriteRulesYaml` parsing tests:
                                    #       legacy collapse-only object unchanged,
                                    #       rename:-only object, both sections, key order
                                    #       invariance, malformed input.
    ApplySpec.hs                    # NEW — pure-function tests for `applyRewriteRules`:
                                    #       collapse-then-rename order, unknown identifier
                                    #       verbatim, `match: payment` vs `match: full`.
test/StaticResolver.hs              # NEW (test-only) — `staticResolver :: FilePath ->
                                    #       IO Resolver` that loads cardano-cli utxo.json
                                    #       and returns the resolved subset of asked-for
                                    #       inputs. Used by InspectSpec; not exported.
test/fixtures/amaru-treasury-swap/  # NEW directory
  swap-1.cbor.hex                   # the operator-facing Amaru treasury swap tx (S4)
  swap-1.utxo.json                  # resolved inputs for swap-1 (cardano-cli format)
  swap-1.source.md                  # provenance: tx hash, block, fetch command
  swap-2.cbor.hex                   # second swap tx for the tx-diff cross-check (S4)
  swap-2.utxo.json
  swap-2.source.md
test/fixtures/amaru-treasury-swap/golden/
  swap-1.verbatim.txt               # S1 baseline (empty rules)
  swap-1.collapse-only.txt          # S2 golden (collapse, no rename)
  swap-1.rename-only.txt            # S3 golden (rename, no collapse)
  swap-1.both.txt                   # S4 golden (collapse + rename)
  swap-1.both.from-tx-diff.txt      # S4 cross-check side of tx-diff swap-1 vs swap-2

rules/
  amaru-treasury.yaml               # NEW — checked-in collapse + rename rules for the
                                    #       Amaru treasury swap (S4)

cardano-tx-tools.cabal              # EDITED:
                                    #   * library: exposed-modules += Cardano.Tx.Rewrite
                                    #   * library: build-depends += `bech32` if not already
                                    #     (already present per grep — no change)
                                    #   * NEW `executable tx-inspect` stanza, mirrors tx-diff
                                    #   * unit-tests: other-modules += Cardano.Tx.InspectSpec,
                                    #     Cardano.Tx.Rewrite.LoadSpec,
                                    #     Cardano.Tx.Rewrite.ApplySpec, StaticResolver

flake.nix                           # EDITED — `apps` output gains `tx-inspect`; release
                                    #          pipeline already iterates over `apps`.
justfile                            # EDITED — gains `smoke-inspect` recipe (mirrors
                                    #          `smoke-sign`); `ci` invokes it.
docs/tx-inspect.md                  # NEW — operator-facing docs page
docs/rewriting-rules.md             # EDITED — adds the `rename:` section (FR-015 requires
                                    #          it to be a new section in the existing
                                    #          grammar doc, not a separate file).
                                    #          [If this doc does not yet exist as a single
                                    #          file, S5 creates it AND lifts the existing
                                    #          collapse grammar content from wherever it
                                    #          currently lives — verified in S5's research.]
mkdocs.yml                          # EDITED — `tx-inspect.md` added to the nav.
gate.sh                             # extended per slice; dropped in final commit.
```

**Structure Decision**: stay with the existing single-library-plus-N-executables layout. The new module `Cardano.Tx.Rewrite` is a sibling of `Cardano.Tx.Diff` under the same library — confirmed by the Q1 clarification — and not a new sublibrary. The test-only `StaticResolver` lives under `test/` (alongside the spec files) and is wired into the existing `unit-tests` test-suite, not exposed as a library — keeping the production resolver chain unchanged.

## Orchestrator vs Subagent Ownership

| Asset | Owner |
|---|---|
| `spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/*`, `tasks.md`, `checklists/*` | **Orchestrator** |
| `gate.sh` (initial create; per-slice extension by subagent in their owned slice — explicit authorisation in each brief; final drop) | **Orchestrator** initial + final; **subagent per-slice extension** |
| `cardano-tx-tools.cabal` library exposed-modules + new `executable tx-inspect` stanza | **Subagent** of S1 |
| `cardano-tx-tools.cabal` unit-tests `other-modules` additions | **Subagent** of the slice introducing each spec file |
| `src/Cardano/Tx/Rewrite.hs` | **Subagent** of S1 (initial type + parser stub); extended by S2 (collapse application), S3 (rename application) |
| `src/Cardano/Tx/Diff.hs` (per-side render extraction, `humanRenameRules` field) | **Subagent** of S1 |
| `app/tx-inspect/Main.hs` | **Subagent** of S1; extended by S3 (rename flag plumbing if any), S4 (no edit expected) |
| `test/Cardano/Tx/InspectSpec.hs` | **Subagent** of S1 (baseline); extended per slice |
| `test/Cardano/Tx/Rewrite/LoadSpec.hs` | **Subagent** of S1 (legacy compat); extended by S3 (rename parsing) |
| `test/Cardano/Tx/Rewrite/ApplySpec.hs` | **Subagent** of S2 (collapse application); extended by S3 (rename) |
| `test/StaticResolver.hs` | **Subagent** of S1 |
| `test/fixtures/amaru-treasury-swap/*` | **Subagent** of S4 (fixture acquisition is part of the slice; see S4 brief for the fetch recipe) |
| `rules/amaru-treasury.yaml` | **Subagent** of S4 |
| `flake.nix` (apps += tx-inspect) | **Subagent** of S1 |
| `justfile` (smoke-inspect, ci wiring) | **Subagent** of S1 |
| `docs/tx-inspect.md`, `docs/rewriting-rules.md` (rename section), `mkdocs.yml` | **Subagent** of S5 |
| Release-pipeline wiring (Homebrew tap, AppImage, DEB/RPM, Docker) per FR-017 | **Subagent** of S6 |
| PR body, issue closing, post-merge cleanup | **Orchestrator** |

## Vertical Commit Slices

Six implementation slices in dependency order. Each = one subagent run = one bisect-safe commit. Plus S7 = orchestrator final drop of `gate.sh`.

### S1 — `tx-inspect` baseline: bare executable + render-core extraction

**Subject**: `feat(032): tx-inspect baseline — wire executable, extract per-side renderer, parse RewriteRules`

**Acceptance**: A user can run `tx-inspect <tx.cbor.hex> --rules empty.yaml` against the swap-1 fixture (resolved via the test-only `staticResolver`) and observe a verbatim render of the OpenValue tree — no collapse, no rename. `tx-diff` output is byte-identical to the pre-slice version on existing fixtures (proves the per-side render extraction is byte-stable).

**Files (subagent-owned)**:
- `src/Cardano/Tx/Rewrite.hs` — `RewriteRules`, `RenameRule(s)` (types + Haddock only; no application logic yet), `parseRewriteRulesYaml` (FromJSON instance: object with optional `version`, `views`, `collapse`, `rename`; legacy `parseCollapseRulesYaml` continues to work unchanged).
- `src/Cardano/Tx/Diff.hs` — extract `renderOpenValueHuman :: HumanRenderOptions -> OpenValue -> String` (or whatever the existing one-side render signature is) from the body of `renderDiffNodeHuman[With]`; delegate per-side from the diff renderer to the new function; add `humanRenameRules :: Maybe RenameRules` field to `HumanRenderOptions` with `Nothing` default (no application yet — added now so S3 has somewhere to plug into without churning the record again). Re-export `renderOpenValueHuman[With]` and the new `humanRenameRules` field.
- `app/tx-inspect/Main.hs` — `withCli` + `versionOption` (mirror `app/tx-diff/Main.hs`), `--rules PATH` flag (optional; absent = empty rules), `--n2c-socket-path` + `--web2-…` flags (lift from `Cardano.Tx.Diff.Cli`), resolver chain, `decodeConwayTxInput`, `renderOpenValueHuman`.
- `cardano-tx-tools.cabal` — library `exposed-modules += Cardano.Tx.Rewrite`; new `executable tx-inspect` stanza (mirror `executable tx-diff` exactly: same `build-depends`, same warning flags, same `werror` flag plumbing, `other-modules: Paths_cardano_tx_tools`).
- `flake.nix` — `apps.tx-inspect` entry added; release pipeline auto-iterates.
- `justfile` — new `smoke-inspect` recipe: builds `exe:tx-inspect`, invokes it on the existing `swap-cancel-issue-8` body (NOT the Amaru swap yet — that fixture lands in S4) with an empty rules YAML and the resolver pointed at the existing `utxo.json`, redirects the output to a tempfile, exits 0. `ci` invokes `smoke-inspect`.
- `test/StaticResolver.hs` — load cardano-cli `utxo.json`, return `Resolver { resolverName = "static", resolveInputs = \askedFor -> pure (Map.restrictKeys loaded askedFor) }`.
- `test/Cardano/Tx/InspectSpec.hs` — S1 baseline: render `swap-cancel-issue-8` body with empty rules YAML, assert the output equals a checked-in golden file (`test/fixtures/mainnet-txbuild/swap-cancel-issue-8/inspect.verbatim.txt`).
- `test/Cardano/Tx/Rewrite/LoadSpec.hs` — assert `parseRewriteRulesYaml` on an existing `{ version: 1, collapse: [...] }` document produces the same `CollapseRules` `parseCollapseRulesYaml` does; assert an empty `{}` parses to empty rules; assert key order between `collapse:` and `rename:` is irrelevant.
- `cardano-tx-tools.cabal` — unit-tests `other-modules += Cardano.Tx.InspectSpec, Cardano.Tx.Rewrite.LoadSpec, StaticResolver`.
- `gate.sh` — extend with `nix develop --quiet -c just smoke-inspect`.

**RED (subagent observes failing before implementation)**:
1. `gate.sh smoke-inspect` line added first → fails because `exe:tx-inspect` does not exist.
2. `InspectSpec` baseline-golden test added first → fails because module `Cardano.Tx.Inspect` does not exist *and* golden file is not yet checked in. Worker writes the spec, runs it once to capture the verbatim output, snapshots it as the golden, then re-runs to assert match.
3. `Rewrite.LoadSpec` legacy-compat test added first → fails because module `Cardano.Tx.Rewrite` does not exist.

**GREEN**:
- `nix develop --quiet -c just build` passes.
- `nix develop --quiet -c just unit` passes (full suite, including the three new specs + the pre-existing tests that exercise tx-diff golden output — byte-stability guaranteed by the per-side render extraction).
- `nix develop --quiet -c just smoke-inspect` passes.
- `nix develop --quiet -c just ci` (fourmolu check + hlint + cabal-fmt -c) passes.
- `./gate.sh` passes end-to-end.

**Live-boundary diagnostic** (per workflow): **yes** — the `tx-inspect` `--version` + the production main path can only be proved by running the built binary. Unit tests over `Cardano.Tx.Rewrite` and `InspectSpec` exercise the loader and the render function in isolation, but the executable's argv handling, `withCli`-wrapped path, and resolver-chain wiring are only proved by running the binary. **`gate.sh smoke-inspect` covers this end-to-end.**

**`tasks.md` IDs (forecast)**: T001–T006.

---

### S2 — Collapse application through `RewriteRules`

**Subject**: `feat(032): apply collapse rules from RewriteRules in tx-inspect`

**Acceptance**: `tx-inspect <tx.cbor.hex> --rules collapse-only.yaml` collapses output shapes per the supplied `CollapseRule`s and renders raw hashes verbatim in the exposed slots.

**Files**:
- `src/Cardano/Tx/Rewrite.hs` — `applyCollapseFromRewriteRules :: RewriteRules -> HumanRenderOptions -> HumanRenderOptions` (sets `humanCollapseRules = Just (collapse rr)`). The plumbing only — the existing `humanCollapseRules` handling in `renderOpenValueHuman` is reused unchanged.
- `app/tx-inspect/Main.hs` — after loading `RewriteRules`, plumb `collapse` into `HumanRenderOptions`.
- `test/Cardano/Tx/InspectSpec.hs` — Golden test #1 (pure collapse) on the existing `swap-cancel-issue-8` body. Specifically: write a small `collapse-only.yaml` next to the fixture that names the swap-cancel order-output shape; assert the render matches a new golden file `inspect.collapse-only.txt`.
- `test/Cardano/Tx/Rewrite/ApplySpec.hs` — pure-function tests: round-trip a hand-crafted `RewriteRules` with collapse rules through `applyCollapseFromRewriteRules` and assert the `humanCollapseRules` field is set as expected; assert empty rules leave `humanCollapseRules` unchanged from the default.
- `cardano-tx-tools.cabal` — unit-tests `other-modules += Cardano.Tx.Rewrite.ApplySpec`.
- `gate.sh` — extend with a `cabal run -v0 -O0 tx-inspect -- --rules test/fixtures/mainnet-txbuild/swap-cancel-issue-8/collapse-only.yaml test/fixtures/mainnet-txbuild/swap-cancel-issue-8/body.cbor.hex` smoke (output checked against the golden bytewise via `diff -q`).

**RED**: smoke `diff -q` against `inspect.collapse-only.txt` fails because rules are not applied yet (S1 ships with `humanCollapseRules = Nothing` from the empty rules object; S2's `applyCollapseFromRewriteRules` is what actually populates it).
**GREEN**: golden + smoke pass.

**Live-boundary diagnostic**: **yes** — the production command path with a non-trivial `--rules PATH` is only proved by the smoke. **`gate.sh` extension covers it.**

**`tasks.md` IDs (forecast)**: T007–T010.

---

### S3 — Rename application: payment addresses + script hashes, with `match: full | payment`

**Subject**: `feat(032): apply rename rules to payment addresses and script hashes in tx-inspect`

**Acceptance**: `tx-inspect <tx.cbor.hex> --rules rename-only.yaml` renders every leaf identifier matched by a `RenameRule` under its book name, leaves unknowns verbatim. Address rules with `match: payment` (the default) match every stake-variant of the same payment script; `match: full` matches the entire bech32 address byte-for-byte.

**Files**:
- `src/Cardano/Tx/Rewrite.hs` — `applyRename :: RenameRules -> OpenValue -> OpenValue`, walking the same `OpenValue` substrate the renderer walks. Site list per FR-009: body inputs (after resolution), body outputs, withdrawals, certificates, body script-hash references, witness-set script-hash references, reference-script hashes. Implementation: a small `Map (Either AddressKey ScriptHash) Text` lookup built once from `RenameRules` at plumbing time. Address `match: payment` extracts the payment credential from the bech32 string at *rule-load* time (in the `FromJSON` instance) and uses that as the lookup key; `match: full` uses the canonical bech32 string. Unknown lookup → leaf renders verbatim.
- `src/Cardano/Tx/Diff.hs` — `renderOpenValueHuman` (extracted in S1) checks `humanRenameRules` and runs `applyRename` on its input `OpenValue` before walking.
- `app/tx-inspect/Main.hs` — after loading `RewriteRules`, plumb `rename` into `HumanRenderOptions`.
- `test/Cardano/Tx/InspectSpec.hs` — Golden test #2 (pure rename). Hand-craft a small `rename-only.yaml` against the `swap-cancel-issue-8` body (whose addresses + script hashes are known and visible in the existing fixture). Assert golden output where every renamed identifier appears as its book name; unknowns verbatim.
- `test/Cardano/Tx/Rewrite/ApplySpec.hs` — pure-function tests: address with `match: payment` against a base address whose stake credential differs still matches (the load-bearing edge case from the spec); unknown identifier renders verbatim; `match: full` against the same address with a different stake credential does NOT match.
- `gate.sh` — extend with a smoke `diff -q` against the new `inspect.rename-only.txt` golden.

**RED**: smoke `diff -q` against `inspect.rename-only.txt` fails because no rename application path is wired yet.
**GREEN**: golden + smoke pass.

**Live-boundary diagnostic**: **yes** — the production command path with a `--rules` file containing a `rename:` section is only proved by the smoke. **`gate.sh` extension covers it.**

**`tasks.md` IDs (forecast)**: T011–T016.

---

### S4 — Amaru treasury swap fixtures + shared-substrate cross-check

**Subject**: `feat(032): add Amaru treasury swap fixtures and shared-substrate golden`

**Acceptance**: `tx-inspect <swap-1.cbor.hex> --rules rules/amaru-treasury.yaml` renders the swap output as the named `Swap` shape with every Amaru-treasury identifier under its book name (P1 user story). `tx-diff <swap-1.cbor.hex> <swap-2.cbor.hex> --rules rules/amaru-treasury.yaml` renders each side identically to the corresponding `tx-inspect` output — the shared substrate is observable byte-for-byte (US4).

**Files**:
- `test/fixtures/amaru-treasury-swap/swap-1.cbor.hex`, `.utxo.json`, `.source.md` — real on-chain Amaru treasury swap transaction. **Fixture acquisition recipe** (in `source.md`, replayable):
  - Use the `amaru-treasury-tx` swap-wizard transcript referenced by the Amaru ops journal for tx hash X (a recent confirmed swap on preview or mainnet — pick one with a tx-diff partner for swap-2);
  - Fetch the body CBOR via `gh api repos/lambdasistemi/amaru-treasury/contents/journal/2026/<dated-recipe>/swap-1.body.cbor` (or via Blockfrost `/txs/{hash}/cbor` if the journal does not carry the body — record the exact fetch in `source.md`);
  - Fetch the resolved UTxOs for the body's inputs via `cardano-cli conway query utxo --tx-in <input> --output-json` and aggregate into `swap-1.utxo.json`.
  - **If the journal recipe lookup fails**, the subagent stops, surfaces the failure to the orchestrator, and the orchestrator selects a different recipe — fixture acquisition cannot be improvised, but the exact tx selection IS allowed to vary per fetch.
- `test/fixtures/amaru-treasury-swap/swap-2.cbor.hex`, `.utxo.json`, `.source.md` — second swap for the cross-check.
- `rules/amaru-treasury.yaml` — `version: 1`, `views: { raw: show }`, `collapse:` rule(s) for the swap output shape, `rename:` rules for the script hashes (swap validator and any reference scripts) and the addresses (treasury party + counterparties named in the two fixtures).
- `test/Cardano/Tx/InspectSpec.hs` — Golden tests #3 (both stages) + #3b (shared substrate). Specifically:
  - `inspect.amaru-swap-1.both.txt` — assert `tx-inspect swap-1 --rules rules/amaru-treasury.yaml` matches.
  - `inspect.amaru-swap-1-vs-2.from-tx-diff.txt` — assert one side of `tx-diff swap-1 swap-2 --rules rules/amaru-treasury.yaml` matches the same `inspect.amaru-swap-1.both.txt` byte-for-byte (FR-014's cross-check).
- `gate.sh` — extend with both smokes: the `tx-inspect` Amaru golden, and the `tx-diff` cross-check.

**RED**: both smokes fail before the fixtures exist (file-not-found). The golden files are captured by the subagent on first run *after* the rules file is in place, and committed alongside; the subagent does NOT capture golden output then claim success — the second run, comparing against the captured file, is the GREEN observation.

**GREEN**: both smokes pass; tx-diff cross-check is byte-identical.

**Live-boundary diagnostic**: **yes** — both the operator command (P1 story) and the shared-substrate property (US4) are only proved by running both binaries. **`gate.sh` extension covers both.**

**`tasks.md` IDs (forecast)**: T017–T021.

---

### S5 — Documentation: `docs/tx-inspect.md` + rename section in the existing grammar doc

**Subject**: `docs(032): document tx-inspect and the rename rule kind`

**Acceptance**: `docs/tx-inspect.md` documents the executable end-to-end (input forms, `--rules`, resolver flags, output shape, exit codes, two-stage pipeline). The existing rewriting-rules grammar doc gains a new section on the `rename:` syntax (including `kind: address | script`, `match: full | payment`). `mkdocs.yml` includes the new page.

**Files**:
- `docs/tx-inspect.md` — new page.
- `docs/rewriting-rules.md` — edited. **Subagent's first task in S5 is to confirm where the existing collapse-rules grammar is documented today**: it may be `docs/rewriting-rules.md`, `docs/tx-diff.md`, or carried inline in `src/Cardano/Tx/Diff.hs` Haddock. Confirmation is via `grep -rn "collapse:" docs/ src/ README.md` plus reading `mkdocs.yml`'s nav. The brief tells the worker to surface the answer in `WIP.md` before editing — the orchestrator confirms the chosen file before the GREEN observation.
- `mkdocs.yml` — nav entry for `tx-inspect.md`.
- `README.md` — `## CLIs` section (or equivalent) gains a `tx-inspect` row.

**RED**: `nix develop --quiet -c just build-docs` (`mkdocs build --strict`) fails before the new page is referenced in nav (strict mode rejects orphan pages); after the nav entry is added but before the page exists, build fails on the missing target.
**GREEN**: `nix develop --quiet -c just build-docs` passes; `nix develop --quiet -c just ci` passes.

**Live-boundary diagnostic**: **no** — docs build is the boundary. `mkdocs build --strict` is the gate.

**`tasks.md` IDs (forecast)**: T022–T024.

---

### S6 — Release pipeline wiring (Homebrew tap, AppImage, DEB/RPM, Docker, release-please)

**Subject**: `chore(032): wire tx-inspect into the release pipeline`

**Acceptance**: A normal release of `cardano-tx-tools` ships `tx-inspect` alongside the four pre-existing CLIs in every distribution channel the other four are shipped in (Homebrew tap, Linux AppImage / `.deb` / `.rpm`, Docker image, release-please version bump).

**Files**:
- `.github/workflows/release*.yaml` — extend matrix or auto-discovery so `tx-inspect` is built and uploaded per channel.
- `release-please*` config (if present) — extend `extra-files` or per-package config for `tx-inspect` paths.
- Docker / nix-deploy bits as applicable (`.github/workflows/publish-images.yaml`).
- Any Homebrew tap formula template the project pushes to (likely `lambdasistemi/homebrew-tap`) — a CHANGELOG-style note that `tx-inspect` is included; the formula auto-discovers the artifacts if the AppImage / brew bottle naming convention is followed.

**Subagent's first task in S6 is to enumerate the existing release workflows** (`grep -nE 'tx-validate|tx-diff|tx-sign|cardano-tx-generator' .github/workflows/*.yaml`) and produce a `WIP.md` entry listing every site that names a CLI; the orchestrator confirms the list is complete before the edit. The slice covers all of them in one commit. Anything that turns out to be auto-discovery rather than explicit naming is captured in the commit body as "no edit required for channel X — already auto-discovered via `apps` output".

**RED**: a dry-run of the release workflow (or `gh workflow run --ref 032-tx-inspect <release-workflow>.yaml` with a tag-equivalent input — TBD by S6's research) fails to upload `tx-inspect` artifacts. **If a dry-run path is impractical**, the RED is the absence of `tx-inspect` from `gh release view v<next>.0.0 --json assets` after a tag is cut — which is post-merge, so S6 documents the post-merge verification step as an operator follow-up in the PR body and `gate.sh` carries an in-repo grep assertion as the local-time RED: `! grep -L 'tx-inspect' .github/workflows/release*.yaml` (every release workflow that names tx-diff must also name tx-inspect after the slice).
**GREEN**: all release workflows that name any of the four existing CLIs also name `tx-inspect`; `nix develop --quiet -c just ci` passes; `nix develop --quiet -c just build-docs` passes.

**Live-boundary diagnostic**: **yes** — the release pipeline is a live boundary that local tests cannot fully cover. The in-repo grep is a partial gate; the conclusive verification is the first post-merge release, which is an **operator follow-up** named in the PR body with `paolino` as the owner and `gh release view` as the verifiable artifact.

**`tasks.md` IDs (forecast)**: T025–T027.

---

### S7 — Drop `gate.sh` (orchestrator chore)

**Subject**: `chore: drop gate.sh (ready for review)`

**Owner**: orchestrator. After finalization audit passes and every `[ ]` in `tasks.md` is `[X] T### (commit: <sha>)`.

## Proof Strategy Summary

| Slice | RED | GREEN | Live-boundary smoke in `gate.sh`? |
|---|---|---|---|
| S1 | new specs added + `gate.sh smoke-inspect` line; both fail until the new module + executable + render extraction exist | full unit + smoke pass; tx-diff golden unchanged (byte-stability of extraction) | yes — `smoke-inspect` (verbatim render against existing fixture) |
| S2 | `inspect.collapse-only.txt` golden + smoke `diff -q`; both fail until `applyCollapseFromRewriteRules` is wired | golden + smoke pass | yes — extended smoke with `--rules collapse-only.yaml` |
| S3 | `inspect.rename-only.txt` golden + smoke `diff -q` + `ApplySpec` `match: payment` edge case; all fail until rename application is wired | golden + smoke + ApplySpec pass | yes — extended smoke with `--rules rename-only.yaml` |
| S4 | `inspect.amaru-swap-1.both.txt` + tx-diff cross-check golden; both fail until fixtures + `rules/amaru-treasury.yaml` are in place | both pass; cross-check is byte-identical | yes — extended smokes for both `tx-inspect` and `tx-diff` on Amaru fixtures |
| S5 | `mkdocs build --strict` fails until nav + new pages line up | `just build-docs` passes | no — docs build is the gate |
| S6 | local grep gate: `! grep -L 'tx-inspect' .github/workflows/release*.yaml`; fails until every workflow names the new exe | grep gate passes; `just ci` passes | partial — local grep is the in-repo gate, first post-merge release is the operator follow-up |
| S7 | n/a (`gate.sh` removal) | finalization audit passes; `gh pr ready` | n/a |

## gate.sh evolution

`gate.sh` grows by one block per slice. The initial S0 commit (`d50e8f5`, `chore: add gate.sh for PR`) ships `build`, `unit`, `cabal-fmt`, `fourmolu -m check`, `hlint`. Each slice extends it as named above; S6 also adds the in-repo grep gate; S7 deletes it.

## Open Questions

The four spec-level clarifications are resolved. The following are **planning-level open questions** the subagent for the named slice surfaces in `WIP.md` and the orchestrator answers before that slice's GREEN observation:

- **S4**: exact tx hash for `swap-1` and `swap-2`. Driven by what is actually fetchable from the Amaru journal at fetch time — the recipe is in the slice brief, the answer is captured in `swap-N.source.md`.
- **S5**: exact location of the existing rewriting-rules grammar doc (may be `docs/rewriting-rules.md`, `docs/tx-diff.md`, or inline Haddock in `Cardano.Tx.Diff`). Slice brief mandates surfacing in `WIP.md` before editing.
- **S6**: complete list of release workflow sites that name a CLI today. Same recipe.

Each of these is captured as the first step of its slice's subagent brief.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *(none)* | — | — |

The plan introduces no new sublibrary, no new top-level namespace, no new direct dependency, no new resolver kind, no new test framework, no schema migration, and no public-API breaking change. Every existing call site compiles unchanged at every slice boundary.

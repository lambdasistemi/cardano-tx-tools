# Implementation Plan: Rewrite-rules redesign — entity-centric identifier model with blueprint-decoded datum rename

**Branch**: `044-rewrite-rules-redesign` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/044-rewrite-rules-redesign/spec.md`

## Summary

Replace the per-leaf-kind `RenameRule` sum + path-extracting collapse engine with an **entity-centric** model: one record `EntityIndex = Map (RoleClass, ByteString) Entity` consumed by a single typed-leaf walker shared by the Conway projection and the existing CIP-57 blueprint decode path (`Cardano.Tx.Blueprint.decodeBlueprintData`). Collapse becomes a structural rule on the typed-leaf tree (no pre-extracted JSON snapshot), gaining `nested:` and per-rule `view: {show, hide-matched, omit}`. The legacy YAML grammar (`kind: address | script`) is preserved as loader sugar that produces entries in the same `EntityIndex`.

Acceptance is anchored by ten golden-test transactions defined in the spec. Those goldens are delivered by **issue #45** (test-fixture harness, separate ticket); this plan delivers the engine + ADT + loader changes that make the goldens pass and does not re-author the fixtures.

The work lands as **seven bisect-safe vertical slices** (S1–S7). Each slice is one subagent run = one commit. Order is end-to-end smallest-feature-first: S1 ships the additive entity types behind the existing API, S2 wires the legacy-sugar bridge so 032 goldens still pass, S3 refactors the projection through the typed-leaf walker and fixes #43 in the process, S4 rebuilds collapse for nested + per-rule view, S5 wires `Cardano.Tx.Blueprint` into the typed-leaf walker so datum subtrees fire rename, S6 collapses asset-class leaves into entity names, S7 documents + deletes caveats + bumps version.

The blueprint scope is dramatically narrower than the spec suggested at write time: `Cardano.Tx.Blueprint` already ships a full CIP-0057 parser and `decodeBlueprintData`, so blueprint integration is wiring, not new infrastructure. See [research.md R3](./research.md#r3-blueprint-decode-already-exists-this-plan-only-wires-it-to-rename).

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (existing pin, constitution Operational Constraints).
**Primary Dependencies**: Existing `cardano-tx-tools` library deps. No new direct dependency. Reuses `Cardano.Tx.Blueprint` (already in the library), `Cardano.Tx.Diff`, `aeson`, `yaml`, `bech32`, `cardano-ledger-*`, `text`, `bytestring`.
**Storage**: None at runtime. Test fixtures on disk under `test/fixtures/rewrite-redesign/` (owned by issue #45).
**Testing**: existing `unit-tests` test-suite. New `Cardano.Tx.RewriteSpec` sub-trees: `EntityIndexSpec`, `LoadSpec` (legacy-sugar + expressive form parity), `WalkerSpec` (typed-leaf walker behaviour incl. #43 fix), `CollapseSpec` (nested + view). Golden tests for the ten user stories are added by issue #45; this PR adds the engine they target. Per-slice live-boundary smoke in `gate.sh` (`cabal run -v0 -O0 tx-inspect …` against a checked-in CBOR fixture).
**Target Platform**: Linux/Darwin via `haskell.nix`.
**Project Type**: Haskell library + five shipped executables (unchanged).
**Performance Goals**: `SC-006` — single-tx render under 500ms for the 33-chunk Amaru swap fixture with blueprint decode + nested collapse + `view: omit`. Loose budget intended only to flag an O(n²) walker accident.
**Constraints**: strictly additive at every existing public surface (`CollapseRule(s)`, `OpenValue`, `DiffPath`, `HumanRenderOptions`, `parseCollapseRulesYaml`, `parseRewriteRulesYaml`, `renderConwayTxHuman`, `renderOpenValueHuman`); `tx-diff` and `tx-inspect` produce byte-identical output on the existing 032 fixtures before and after this PR when fed unchanged YAML. Where the entity-centric loader renders strictly better than the legacy path (an identifier the legacy path missed now shows under an entity name), the golden is re-captured with annotation in the PR description (SC-005).
**Scale/Scope**: 1 new module (`Cardano.Tx.RewriteRules`, ~600 LOC — entity types, role-class enum, index builder, typed-leaf walker, collapse engine rebuild), 1 edited module (`Cardano.Tx.Rewrite`, becomes the user-facing API re-export hub plus the legacy-sugar bridge, +200 LOC), 1 edited module (`Cardano.Tx.Diff`, integration points — typed-leaf classifier hooks, `HumanRenderOptions` carrying `entityIndex` + `blueprintIndex` + nested-collapse-engine handles, +150 LOC; no removed surface), 1 new test sub-tree (`test/Cardano/Tx/RewriteRules/*`, ~500 LOC excluding the goldens issue #45 brings), 1 edited docs page (`docs/rewriting-rules.md`, +200 / −60 LOC), 1 CHANGELOG entry, 1 version bump. Net diff ~1500 LOC, excluding what issue #45 brings.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution's seven core principles apply. Walked one by one:

- **I. One-Way Dependency On Node-Clients** — No new `cardano-node-clients` import. The entity-centric loader is library-internal; nothing in `cardano-node-clients` could need to import it. **Pass.**
- **II. Module Namespace Discipline** — The new module is `Cardano.Tx.RewriteRules`, under `Cardano.Tx.*`. The `Cardano.Tx.Rewrite` user-facing wrapper from 032 is kept (now re-exports the new module's public API plus the legacy-sugar bridge). No `Cardano.Node.Client.*` introduced. **Pass.**
- **III. Conway-Only Era** — Engine targets Conway transactions only (same decoder chain as 032). **Pass.**
- **IV. Hackage-Ready Quality** — Every new export carries Haddock; module headers use the canonical `{- | Module … -}` form; `cabal check` runs in `just ci`. `README.md`/`CHANGELOG.md` already in `extra-doc-files`. **Pass.**
- **V. Strict Warnings, No `-Werror` Escape Hatches** — New module + edits build under `-Wall -Werror -Wunused-imports -Wmissing-export-lists -Wname-shadowing -Wredundant-constraints` (gated behind the existing `werror` flag). **Pass.**
- **VI. Default-Offline Semantics** — No new network surface. Blueprint decode reads on-disk files; the typed-leaf walker is pure. **Pass.**
- **VII. TDD With Vertical Bisect-Safe Commits** — Seven slices below; each commit on the branch compiles, tests green, and ships the per-slice live-boundary smoke. **Pass.**

**Operational Constraints**:
- GHC 9.12.3 via `haskell.nix` — unchanged.
- `nix flake check --no-eval-cache` local gate — extended by per-slice smoke in `gate.sh`.
- Lint stack (fourmolu, hlint, cabal-fmt) — already in `gate.sh`.
- Released binaries with HTTPS bundle a CA store — no change (engine + loader don't touch HTTPS).

**Resolver Architecture** — Unchanged. Reuses `Cardano.Tx.Diff.Resolver` chain as 032 does.

**No exceptions tracked.** Complexity Tracking table at the bottom is empty.

## Project Structure

### Documentation (this feature)

```text
specs/044-rewrite-rules-redesign/
|-- plan.md                         # this file
|-- spec.md                         # ten user stories, FR-001..FR-016
|-- research.md                     # Phase 0 output (R1..R6 decisions)
|-- data-model.md                   # Phase 1 output (Entity, RoleClass, EntityIndex, …)
|-- quickstart.md                   # Phase 1 output (operator-facing quick path)
|-- contracts/
|   |-- rules-yaml-grammar-v2.md    # Phase 1 output (entity grammar, blueprints, view:, nested:)
|   `-- blueprint-loader-contract.md # Phase 1 output (how blueprints attach to scripts)
|-- checklists/
|   `-- requirements.md             # spec quality checklist (already exists)
`-- tasks.md                        # /speckit.tasks output (next phase, NOT created by /speckit.plan)
```

### Source code (repository root)

```text
src/Cardano/Tx/
  RewriteRules.hs                   # NEW — Entity, RoleClass enum, Identifier, EntityIndex,
                                    #       typed-leaf walker (TypedLeaf, classifyLeaf,
                                    #       walkConwayTx, walkBlueprintDecoded), collapse rule
                                    #       (CollapseRule with `nested` and per-rule `view`),
                                    #       collapse engine that walks the typed-leaf tree
                                    #       structurally. Pure: no IO. Property tests target
                                    #       this module directly. Internal — re-exported by
                                    #       Cardano.Tx.Rewrite for downstream consumers.
  Rewrite.hs                        # EDITED — becomes the user-facing API hub:
                                    #   * re-exports the public Entity types and the
                                    #     typed-leaf walker from RewriteRules.
                                    #   * keeps the legacy `parseRewriteRulesYaml`
                                    #     signature; new implementation produces an
                                    #     EntityIndex internally (legacy-sugar bridge for
                                    #     `kind: address | script`).
                                    #   * NEW `loadEntityRules :: ByteString
                                    #     -> Either String EntityIndex` for the new
                                    #     entities-first grammar.
                                    #   * NEW `applyRewriteRules` (replaces stage-1 +
                                    #     stage-2 plumbing helpers from 032; the helpers
                                    #     remain as deprecated re-exports until S7 drops
                                    #     them).
  Diff.hs                           # EDITED — strict additions, no removed surface:
                                    #   * `HumanRenderOptions` gains
                                    #     `humanEntityIndex :: Maybe EntityIndex`,
                                    #     `humanBlueprintIndex :: Maybe BlueprintIndex`,
                                    #     and the existing
                                    #     `humanCollapseRules`/`humanRenameRules` fields
                                    #     remain in place (defaults: Nothing) for
                                    #     consumers wired in 032 that do not yet move to
                                    #     the new index.
                                    #   * `conwayDiffProjection`'s leaf cases call into
                                    #     `RewriteRules.classifyLeaf` so the typed-leaf
                                    #     identity is preserved across the collapse +
                                    #     rename application.
                                    #   * `renderConwayTxHuman` and
                                    #     `renderOpenValueHuman` add the entity-index
                                    #     lookup + the blueprint-decode-on-encounter
                                    #     path; downstream behaviour is gated on the
                                    #     new fields being `Just`. When both old and
                                    #     new fields are present the new index wins
                                    #     (loaded by the legacy-sugar bridge S2).
  Blueprint.hs                      # UNCHANGED — already ships CIP-0057 parser +
                                    #             decodeBlueprintData. Used by Diff.hs
                                    #             during the walker pass to decode any
                                    #             datum subtree whose script appears in
                                    #             humanBlueprintIndex.

test/Cardano/Tx/
  RewriteRules/
    EntityIndexSpec.hs              # NEW (S1) — Entity/Identifier construction, EntityIndex
                                    #            builder + collision detection (FR-010) +
                                    #            zero-identifier rejection (FR-011) +
                                    #            multi-role entity (FR-012).
    LoadSpec.hs                     # NEW (S2) — YAML loader tests: legacy collapse-only
                                    #            documents parse identical EntityIndex as
                                    #            before; new `entities:` form parses; sugar
                                    #            forms (`from-address`, `script`, `pool`,
                                    #            `drep`, `asset`, `keys+bytes`) all produce
                                    #            entries in the same index.
    WalkerSpec.hs                   # NEW (S3) — typed-leaf walker on a synthetic projection;
                                    #            #43 reproducer (collapse pinning
                                    #            `resolved.address` still fires rename);
                                    #            cross-leaf identity (two leaves at unrelated
                                    #            sites hit the same entity).
    CollapseSpec.hs                 # NEW (S4) — nested collapse depth-1, depth-2; per-rule
                                    #            `view: omit | hide-matched | show`;
                                    #            backwards-compat (no `nested:` /
                                    #            no `view:` → identical to legacy semantics).
    BlueprintRenameSpec.hs          # NEW (S5) — datum subtree decoded via blueprint;
                                    #            typed leaves fire rename; without blueprint,
                                    #            raw bytes render verbatim (FR-006 negative
                                    #            test); blueprint-decode failure falls back
                                    #            to verbatim + warning (FR-015).
    AssetClassSpec.hs               # NEW (S6) — multi-asset map entry renders as entity
                                    #            name when an AssetClass entity matches;
                                    #            policy and name leaves do not appear
                                    #            verbatim.
  RewriteSpec.hs                    # EDITED — existing 032 ApplySpec / LoadSpec tests
                                    #          continue to pass against the new bridge.
  InspectSpec.hs                    # EDITED — golden files re-captured ONLY where the
                                    #          entity-index improves the render
                                    #          (annotated in PR). Behaviour-preserving
                                    #          cases pass byte-identically.

docs/
  rewriting-rules.md                # EDITED — new "Entities" section; new "Blueprints"
                                    #          section; new "Collapse: nested + view"
                                    #          section; the "Pattern — keep payment
                                    #          addresses out of required:" caveat is
                                    #          DELETED (SC-004); the "Not in this
                                    #          version — datum-embedded rename" caveat
                                    #          is DELETED (SC-004).

CHANGELOG.md                        # EDITED — one entry under [Unreleased]:
                                    #          "Entity-centric rewriting rules:
                                    #          cross-leaf identity via blueprint-decoded
                                    #          datum rename, nested collapse + raw-omit
                                    #          mode, #43 collapse-rename bug fixed.
                                    #          Legacy YAML grammar preserved as
                                    #          loader sugar."

cardano-tx-tools.cabal              # EDITED — new module `Cardano.Tx.RewriteRules`
                                    #          listed in `exposed-modules`; new test
                                    #          sub-tree files listed in the
                                    #          `unit-tests` test-suite.

rules/                              # UNCHANGED in this PR. Operators who want to
                                    # migrate amaru-treasury.yaml from the legacy
                                    # kind-tagged form to the entities-first form
                                    # land that as a separate operator-facing PR
                                    # after the engine ships.
```

**Structure Decision**: Single Haskell library + five shipped executables (existing structure). The engine + ADT redesign is internal to the library; the user-facing surface is the YAML grammar (extended additively) and the rendered output (improved per the spec). No new executable, no new sub-package, no new dependency.

## Slices

Seven bisect-safe vertical slices. Each is one subagent run = one commit. Each compiles + tests green + ships the per-slice live-boundary smoke (`cabal run -v0 -O0 tx-inspect …` against a checked-in CBOR fixture).

### S1 — Entity types + EntityIndex builder (additive, no behaviour change)

- Add `Cardano.Tx.RewriteRules` with `Entity`, `RoleClass`, `Identifier`, `EntityIndex`, `mkEntityIndex` (collision + zero-id validation), `lookupEntity`.
- Add `EntityIndexSpec` covering FR-010, FR-011, FR-012.
- Cabal: list new module in `exposed-modules`; list new test file.
- `tx-diff` / `tx-inspect` behaviour unchanged: nothing wires `EntityIndex` into the renderer yet.
- Per-slice smoke: existing `tx-inspect` golden render runs unchanged.

### S2 — Legacy-sugar bridge + new entities-first loader (parser only, no renderer change)

- Extend `Cardano.Tx.Rewrite.parseRewriteRulesYaml` so legacy `kind: address | script` rules normalise into the new `EntityIndex` internally. Externally the legacy `RewriteRules` record still returns; the bridge sits underneath.
- Add `loadEntityRules :: ByteString -> Either String EntityIndex` for the new entities-first form (`entities:` + `blueprints:` + new `collapse:` schema with `nested:` + `view:`).
- `LoadSpec` covers: legacy form parity (every 032 fixture parses to an EntityIndex byte-equal to the new path's output); new entities-first form parses; the six sugar forms (`from-address`, `script`, `pool`, `drep`, `asset`, `keys+bytes`) all produce equivalent index entries; collision and zero-identifier rejection.
- Renderer still does not consult `EntityIndex`. 032 goldens unchanged.
- Per-slice smoke: a new `examples/entities-first.yaml` is rendered through `tx-inspect`; output today is identical to the legacy path because the typed-leaf walker (S3) is not yet wired.

### S3 — Typed-leaf walker + #43 fix (engine change)

- Refactor `conwayDiffProjection` so every payment-address, script-hash, withdrawal-key, certificate-credential, mint/value asset-key, witness-script, reference-script leaf flows through a single `classifyLeaf :: ConwayDiffValue -> Maybe TypedLeaf`. `TypedLeaf` carries `(RoleClass, ByteString)`.
- `HumanRenderOptions` gains `humanEntityIndex :: Maybe EntityIndex`. When `Just`, the renderer substitutes the entity name at every typed-leaf site that hits the index.
- Collapse engine: the matched-item snapshot is replaced by a structural walk that keeps the typed-leaf identity through the collapse bucket's variable slots. **#43 fixed** — `resolved.address` in `required:` no longer suppresses rename.
- `WalkerSpec` includes the #43 reproducer (collapse with `resolved.address` in `required:` AND an entity rule for that address → bucket slot renders as entity name).
- Backwards compat: `humanRenameRules` from 032 is still consumed; when both `humanRenameRules` and `humanEntityIndex` are populated, `humanEntityIndex` wins. 032 goldens re-captured for the *single* case where the entity index now reaches a leaf the legacy rename did not (annotated in PR; this is SC-005's "strictly better" carve-out).
- Per-slice smoke: a CBOR fixture with a collapse rule pinning `resolved.address` is rendered; output shows the entity name in the bucket slot (would have rendered as `{"bytes":"…"}` before).

### S4 — Collapse engine rebuild: nested + per-rule view

- `CollapseRule` (in `Cardano.Tx.RewriteRules`) gains `crNested :: [CollapseRule]` and `crView :: ItemView`. `ItemView = ShowItem | HideMatchedLeaves | OmitItem`.
- YAML loader (already extended in S2) parses `nested:` and `view:`.
- Engine: nested rules apply with `at:` relative to the parent's matched item subtree. Arbitrary depth.
- The global `views.raw:` field remains as a per-tx default; per-rule `view:` overrides when present.
- `CollapseSpec` covers depth-1, depth-2, per-rule view modes, legacy-compat (no nested/view → identical semantics).
- Per-slice smoke: a fixture matching Story 9's shape (chunked outputs) renders one bucket and no per-output subtree below it.

### S5 — Blueprint loader + decode integration

- YAML grammar accepts `blueprints:` mapping script hashes (or entity names) → CIP-0057 file paths.
- Loader builds `BlueprintIndex = Map ScriptHash Blueprint` using the existing `Cardano.Tx.Blueprint.parseBlueprintJSON`.
- `HumanRenderOptions` gains `humanBlueprintIndex :: Maybe BlueprintIndex`.
- `renderOpenValueHuman` checks the script attached to the parent UTxO; if the script's hash appears in `humanBlueprintIndex`, the datum/redeemer subtree is decoded via `decodeBlueprintData`; the resulting AST's leaves carry semantic role classes; the typed-leaf walker (S3) fires rename on them.
- Without a blueprint, raw bytes render verbatim — no heuristic (FR-006).
- Blueprint decode failure → warning + fallback to verbatim (FR-015).
- `BlueprintRenameSpec` covers: positive case (datum field typed `PubKeyHash` matches an entity); negative case (no blueprint → no rename inside data); decode failure fallback.
- Per-slice smoke: render Story 1's shape (33 SwapOrder inputs + blueprint) and confirm `datum.SwapOrder.recipient` renders as the treasury entity name.

### S6 — AssetClass entity rendering

- The multi-asset map renderer (`ConwayMintValue`, `ConwayValueValue`, output asset maps) recognises an `AssetClass` entity match and collapses `(policy, name): qty` into `entity-name: qty`.
- `AssetClassSpec` covers: two unrelated asset entities side-by-side; policy and name leaves do not render verbatim anywhere; same-bytes-as-script entity (the Story 4 shape) coexists without interference.
- Per-slice smoke: a fixture with a USDM asset entity renders `usdm: 95` in the output's asset map (not `c48cbb3d…5553444d: 95`).

### S7 — Docs + caveat deletion + release wiring

- `docs/rewriting-rules.md` extended with: "Entities" section, "Blueprints" section, "Collapse: nested + view" section. Caveats deleted (SC-004).
- `CHANGELOG.md`: one entry under `[Unreleased]`.
- Version bumped per `feat:` semantics. Release flow: existing `release-please` config picks it up.
- The deprecated re-exports introduced in S2 (`applyCollapseFromRewriteRules`, `applyRenameFromRewriteRules`) are dropped; downstream `tx-inspect`'s `Main.hs` already calls `applyRewriteRules` (the single composite) from S2.
- `gate.sh` is dropped (matches the 032 convention of dropping `gate.sh` in the final slice).

## Complexity Tracking

Empty. No constitutional violation that needs justification.

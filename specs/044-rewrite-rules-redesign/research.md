# Research: Rewrite-rules redesign

**Branch**: `044-rewrite-rules-redesign` | **Date**: 2026-05-19

Phase 0 of `/speckit.plan`. Resolves the design unknowns surfaced while drafting the spec and the plan.

## R1 — Role-class enumeration is closed (no extension axis)

**Decision**: The `RoleClass` enum is closed and fixed at: `PaymentKey`, `PaymentScript`, `StakeKey`, `StakeScript`, `DRepKey`, `DRepScript`, `PoolId`, `Policy`, `AssetClass`. Adding a new role class requires a constructor addition and recompilation of consumers (i.e., is a breaking change to the library API).

**Rationale**: The enum maps 1:1 to the typed-leaf classes the Conway projection and the blueprint decoder can produce. Cardano has a fixed set of identifier kinds at the protocol level (Conway era, CIP-129 for governance, CIP-67 for asset name standards). New role classes would only arise from new ledger features or new CIP standards — both of which are infrequent and warrant a library API change. Keeping the enum closed is what makes role-class narrowness (FR-012) safe by construction: there is no "future role class" the engine has to default-match against.

**Alternatives considered**:
- (a) Open the enum via a type parameter (`RoleClass a = … | Custom a`). Rejected: makes the index polymorphic and the loader has to parse arbitrary tag strings into a typed payload; the user value (entities the operator declares) is dominated by the nine baseline classes; the polymorphism buys nothing the operator can use today.
- (b) Index by bytes only, dispatch by leaf context. Rejected: re-introduces the false-positive failure mode the spec gates against — a 28-byte payment-key-hash and a 28-byte stake-key-hash with the same bytes would render with the same entity name across both site contexts when the operator didn't ask for that.

## R2 — Legacy YAML grammar is preserved unchanged (additive grammar)

**Decision**: Every YAML document that `parseRewriteRulesYaml` accepts in 032 parses unchanged under the new loader. The new entities-first grammar (`entities:` + `blueprints:` + new `collapse:` schema with `nested:` + `view:`) is *additive* at the top level — both grammars coexist; the loader detects which form is in use by the presence/absence of `entities:`.

**Rationale**: SC-005 + the spec's Assumptions section pin loader backwards compatibility as a hard constraint. The Amaru-treasury `rules/amaru-treasury.yaml` and any operator-authored 032-style YAML must keep working. The bridge implementation: a `kind: address` rule is normalized into an entity `{ name: <user's name>, identifiers: [(PaymentKey-or-PaymentScript, <derived bytes>)] }` (loader picks the role class based on the bech32's payment side); `kind: script` becomes `{ name, identifiers: [(PaymentScript, hash)] }`. The internal `EntityIndex` is the same regardless of which grammar produced it.

**Alternatives considered**:
- Force a one-time migration. Rejected: operators have authored YAMLs against the 032 grammar; a breaking change adds friction with no engine benefit (the internal model is identical post-bridge).
- Two loaders, two engines. Rejected: doubles the test surface and re-introduces drift between the two paths.

## R3 — Blueprint decode already exists; this plan only wires it to rename

**Decision**: Reuse `Cardano.Tx.Blueprint` (existing module) for CIP-0057 parsing and `decodeBlueprintData` for datum decoding. The plan's S5 slice is *wiring*, not new infrastructure: build a `BlueprintIndex :: Map ScriptHash Blueprint` from the YAML's `blueprints:` section, attach it to `HumanRenderOptions`, and have `renderOpenValueHuman` consult it when entering a datum subtree whose parent UTxO's script hash appears in the index.

**Rationale**: Discovered while drafting the plan — `src/Cardano/Tx/Blueprint.hs` already exposes `Blueprint`, `parseBlueprintJSON`, `decodeBlueprintData`, `blueprintDataDecoder`, plus the diff-side machinery (`diffBlueprintData`, `matchBlueprintArgument`, fallback reasons). The library is full enough that the rename engine just needs to descend the decoded AST and classify its leaves into `(RoleClass, ByteString)` pairs.

**Alternatives considered**:
- New blueprint parser. Rejected: duplicates existing work and risks drift between the diff path and the rename path.
- Plutus's official blueprint type (from `plutus-ledger-api`). Rejected: the existing in-repo module is already aligned with how the diff core consumes blueprint metadata; introducing the upstream type would be a structural refactor whose payoff is decoupled from this PR.

## R4 — Typed-leaf classification lives in `Cardano.Tx.RewriteRules`, not `Cardano.Tx.Diff`

**Decision**: The function `classifyLeaf :: ConwayDiffValue -> Maybe TypedLeaf` (and its blueprint sibling `classifyBlueprintLeaf :: BlueprintDataValue -> Maybe TypedLeaf`) live in the new `Cardano.Tx.RewriteRules` module. `Cardano.Tx.Diff` imports and calls them from inside the projection walker. The reverse direction (RewriteRules importing Diff) is avoided.

**Rationale**: Keeps the typed-leaf concept owned by the rewriting-rules module — the module that documents the role classes and the entity index also defines the classifier. `Cardano.Tx.Diff` continues to own the projection itself and the render primitives; it just delegates one decision point (classify a leaf) to the rewriting-rules module. This matches the existing 032 pattern where `Cardano.Tx.Rewrite` reaches into `Cardano.Tx.Diff` for the user-facing API rather than the other way round.

**Alternatives considered**:
- Move the classifier into `Cardano.Tx.Diff`. Rejected: `Cardano.Tx.Diff` already has too much surface; adding role-class knowledge to it bloats a module that has been hard to evolve. Co-locating with the rewriting-rules data types is the natural home.
- Cross-import (both modules import each other through a `.Internal` shim). Rejected: more layering than necessary for one shared function.

## R5 — Collapse engine: structural walk replaces path-extracted snapshot

**Decision**: The collapse engine in S4 walks the typed-leaf tree structurally rather than pre-extracting a JSON snapshot at each matched `at:` path. When a collapse rule matches an item, the engine records the bucket and recurses *into* the item's typed-leaf subtree with the rule's `nested:` children. Rename fires at every typed leaf the recursion reaches — including the bucket's `required:` slots.

**Rationale**: This is the property that closes #43 by construction. The old engine pre-extracted a frozen JSON view at the matched path; rename walked the typed leaves separately; the two channels raced and the bucket slots lost typed-leaf identity. With a single typed-leaf walker that the collapse engine drives, there is no second channel. The structural walk also enables FR-008 (nested collapse) and FR-009 (per-rule view) without re-introducing path-extraction.

**Alternatives considered**:
- Fix #43 by re-running rename on the bucket's variable slots after pre-extraction. Rejected: keeps the two-channel structure; preserves the leaky-abstraction concern that the spec's Background section calls out; doesn't unlock nested-collapse.
- Drop collapse entirely. Rejected: collapse is the primitive that makes large-chunked transactions readable (Story 9); removing it regresses the operator experience.

## R6 — Asset entity rendering: walker collapses `(policy, name)` into one leaf

**Decision**: When the typed-leaf walker reaches a multi-asset map entry (`ConwayMintValue` or `ConwayValueValue` asset map), it classifies the `(policy, name)` pair as a single `AssetClass` typed leaf, looks it up in the entity index, and on hit renders `entity-name: qty` (one leaf, not two). On miss, the walker falls back to the existing per-leaf rendering (policy rendered with `Policy` role class lookup, name rendered verbatim or under an `AssetName`-only future role class).

**Rationale**: The asset entity is a compound identifier. FR-014 requires the renderer to collapse the policy and name leaves into one rendered slot when the AssetClass entity matches. The natural place is the asset-map renderer, which already iterates `(policy, name) → qty` triples. This avoids inventing a `Map (PolicyId, AssetName) Entity` separate from the unified `(RoleClass, ByteString) → Entity` index — the index entry for an AssetClass identifier stores the bytes as `policy <> name` (canonical concatenation), and the asset-map renderer composes the lookup key the same way.

**Alternatives considered**:
- Render asset entity as `entity-name (asset)` with the policy still shown above. Rejected: the operator-facing payoff in Story 1 ("the swap returns USDM to the treasury") needs the asset to read as a single word; verbose forms defeat the purpose.
- Render the asset entity only at mint sites, leave value-map sites verbatim. Rejected: asymmetric; the operator would see `usdm: +1000` at the mint and `c48cbb3d…5553444d: 95` in the output asset map of the same tx.

## Resolution status

All NEEDS CLARIFICATION markers are resolved. No outstanding open question blocks the plan or the slice schedule.

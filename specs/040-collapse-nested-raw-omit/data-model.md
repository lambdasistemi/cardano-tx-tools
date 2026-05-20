# Data Model: collapse engine — nested rules + `raw: omit`

**Branch**: `040-collapse-nested-raw-omit` | **Date**: 2026-05-18

Phase 1 of `/speckit.plan`. The Haskell-level model carrying the two new primitives. Strictly additive on top of the existing `Cardano.Tx.Diff` types — no field rename, no constructor rename, no public-API breaking change.

## Type changes

### `CollapseRule` *(existing, extended)*

```haskell
data CollapseRule = CollapseRule
    { collapseRuleName :: Text
    , collapseRuleAt :: DiffPath
    , collapseRuleRequired :: [DiffPath]
    , collapseRuleNested :: [CollapseRule]      -- NEW (default: [])
    }
    deriving stock (Eq, Show)
```

- **`collapseRuleNested`** *(new)*: ordered list of child rules. The empty list means "no nested behavior" and renders identically to a rule with no `nested:` key (legacy compatibility, US2).
- Existing fields (`collapseRuleName`, `collapseRuleAt`, `collapseRuleRequired`) are unchanged in name, type, and semantics.

### `CollapseRawView` *(existing, extended)*

```haskell
data CollapseRawView
    = CollapseRawShow
    | CollapseRawHide
    | CollapseRawOmit                            -- NEW
    deriving stock (Eq, Show)
```

- **`CollapseRawOmit`** *(new)*: documents that under this raw-view mode, items matched by a collapse rule do not render below the bucket. Unmatched siblings continue to render verbatim (see R2 in `research.md` for the engine semantics).
- Existing constructors (`CollapseRawShow`, `CollapseRawHide`) are unchanged.

### Unchanged types

The following types are referenced by the engine but are **not** modified:

- `CollapseRules` — carries `collapseRawView :: CollapseRawView` (which gains the new value range) and `collapseRules :: [CollapseRule]` (whose elements now optionally carry nested children). The wrapper type itself is unchanged.
- `RewriteRules`, `RenameRules`, `RenameRule`, `AddressMatch`, `AddressTarget` — stage-2 types, unaffected.
- `HumanRenderOptions` — unchanged; the engine already accepts `humanCollapseRules :: Maybe CollapseRules`.
- `OpenValue`, `ConwayDiffValue`, `DiffPath`, `RenderTrie`, `DiffNode` — unchanged.

## YAML grammar changes

### `CollapseRule` *(extended)*

```yaml
- name: "SwapOrder"                # unchanged
  at: body.outputs                 # unchanged
  match:                           # unchanged
    required:
      - coin
      - datum.constructor
  nested:                          # NEW, optional, default []
    - name: "ScopeOwners"
      at: datum.fields.1.fields.0  # interpreted RELATIVE to each
                                   # matched parent item
      match:
        required:
          - constructor
          - fields.0
      # `nested:` may carry further children for arbitrary depth.
```

- **`nested:`** *(new, optional)*: a YAML list of `CollapseRule` entries. Each child's `at:` is interpreted relative to the matched parent item's base path (`<parent at> </> <matched-item-index>`). Children may themselves carry `nested:` — depth is unbounded.
- A missing `nested:` key parses to `collapseRuleNested = []` (the legacy-compat property).

### `views.raw:` *(extended)*

```yaml
views:
  raw: show | hide | omit          # `omit` is new
```

- The accepted value range gains `"omit"`. The error message for an unrecognised value enumerates the full set (`show | hide | omit`).
- `views:` and `views.raw:` are both optional; missing means `show` (unchanged default).

## Validation rules

### Loader

- `nested:` value MUST be a YAML list. A non-list value (string, object, scalar) is a parse error.
- Each entry in `nested:` MUST be a valid `CollapseRule` shape (`name`, `at`, `match.required`, optional `nested:`).
- `views.raw:` MUST be one of `show | hide | omit`. Any other string value is a parse error with a message enumerating the accepted set.
- All other validation rules from the legacy grammar are unchanged (positive `match.required`, valid `DiffPath` shape, non-empty `name`, etc.).

### Engine (apply time)

- A child rule's `at:` is interpreted as a relative `DiffPath`; the engine **does not** validate that the relative path resolves in every matched item's subtree. If the relative path does not resolve, the recursion is gracefully a no-op for that item — no error, no missing bucket (per the spec's Edge Cases).
- Under `views.raw: omit`, the engine MUST suppress per-item subtrees only for items matched by at least one rule at the array site. Unmatched siblings render verbatim (per R2 in `research.md`).

## State transitions (engine)

The engine is stateless across array sites — every `collectValueArray` call is determined by its inputs. The new nested-rule recursion is a single state transition at apply time:

```
                  (rules, hideEmpty, path, trie, children)
                                  │
                  ┌───────────────┴───────────────┐
                  │                               │
            collapseRulesAt              foreach item:
            (top-level rules)             collectValueRequiredLeaves
                  │                               │
                  v                               v
            insertValueCollapseView           covered leaf paths
                  │                               │
                  v                               v
           (withViews, hasView)        ┌──────────┴──────────┐
                  │                    │                     │
                  v                    │           foreach matched item:
   ┌──────────────┼──────────────┐     │           rewrite `nested:` rules
   │              │              │     │           to absolute `at:` paths
   v              v              v     │                     │
 (False,_)     (True,Show)    (True,Hide)                    v
walkRaw      walkRaw         walkPruned             augmented-rules
(verbatim)   (under raw/)    (covered pruned)             │
                                                          v
                                                walkRaw   /walkPruned/
                                                walkRawUnmatched
                                                (with augmented rules)
                                                          │
                                                          v
                                              recursion into matched
                                              items' subtrees via
                                              collectValueTrie[Pruned]
```

The new edges are:

- `withViews → augmented-rules` (path rewriting per R1).
- `(True, CollapseRawOmit) → walkRawUnmatched` (new branch per R2).
- `walkRaw[Unmatched]` and `walkPruned` calls now thread the augmented rules into the recursive walker so the nested children fire at the rewritten absolute paths.

## Relationships

- `CollapseRule` ⇄ `CollapseRule` via `collapseRuleNested` — a recursive type (a rule contains zero or more rules).
- `CollapseRules` `→` `[CollapseRule]` — unchanged; the recursion lives inside the elements, not in the container.
- `CollapseRawView` ⇄ engine `case` dispatch — extending the enum extends the case dispatch in `collectValueArray`.

## Backwards compatibility properties

1. **Type-level**: any existing call site that constructs `CollapseRule` via named-field syntax compiles with one extra line (`collapseRuleNested = []`). Open question P1 in `plan.md` enumerates the nine sites.
2. **Parser-level**: every YAML document accepted by `parseRewriteRulesYaml` before this feature lands MUST continue to parse to a `RewriteRules` value byte-equal to the pre-change result modulo the empty `collapseRuleNested` defaults inside every `CollapseRule`. Tested in `LoadSpec` (FR-011 legacy-compat block).
3. **Engine-level**: every existing golden file under `test/fixtures/` MUST render byte-identically. Tested implicitly by the existing #032 InspectSpec describe blocks plus the per-slice `gate.sh` runs.
4. **API-level**: no field renaming, no constructor renaming, no exported symbol removal. The `Cardano.Tx.Rewrite` module's re-export list is unchanged.

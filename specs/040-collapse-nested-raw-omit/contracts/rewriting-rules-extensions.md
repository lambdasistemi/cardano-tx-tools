# Contract: rewriting-rules YAML extensions

**Branch**: `040-collapse-nested-raw-omit` | **Date**: 2026-05-18

Phase 1 of `/speckit.plan`. The on-disk contract for the two new YAML keys. This file is the planning-time anchor; the canonical user-facing grammar doc (`docs/rewriting-rules.md`) is updated in slice S4 to mirror this content.

## Top-level grammar (delta)

```yaml
version: 1                            # unchanged
views:                                # unchanged shape
  raw: show | hide | omit             # `omit` is new
collapse:                             # unchanged shape
  - <CollapseRule>                    # see below
rename:                               # unchanged
  - <RenameRule>
```

Unchanged keys (`version`, `views.raw: show | hide`, `collapse` list shape, `rename`) carry over from issue #32's grammar. Only the additive deltas are documented here.

## `CollapseRule` (delta)

```yaml
- name: <string>                      # unchanged
  at: <DiffPath>                      # unchanged
  match:                              # unchanged
    required:
      - <DiffPath>
  nested:                             # NEW (optional, default [])
    - <CollapseRule>                  # recursive — each child is a
                                      # full CollapseRule with its
                                      # own optional `nested:`
```

### `nested:` semantics

- **Type**: a YAML list of `CollapseRule` entries. May be empty (`nested: []`) or omitted entirely. Both are semantically identical to a rule without `nested:` (legacy compatibility).
- **`at:` of a child**: a `DiffPath` interpreted **relative** to each matched parent item's subtree. The engine rewrites the child's `at:` to an absolute path under `<parent at> </> <matched-item-index>` at apply time.
- **Required leaves of a child**: relative to the matched parent item, the same way the parent's `required:` is relative to each candidate at the parent `at:` site.
- **Depth**: unbounded. A child may carry `nested:` recursively. There is no syntactic depth limit and no engine-side depth cap.
- **No-fire conditions**:
  - A child rule whose `at:` does not resolve in a particular matched parent item (e.g. the relative path points into a missing object key, or the value at the path is not an array) is a graceful no-op for that item — no error, no bucket header.
  - A child rule whose parent rule did not match for an item does not fire on that item — recursion is gated on the parent match.

### `nested:` parse-error conditions

- `nested:` value is not a YAML list (e.g. a string, an object, a scalar): YAML parse error from the underlying decoder with a message naming the offending entry.
- An entry under `nested:` is not a valid `CollapseRule` shape (missing `name`, `at`, or `match.required`): parse error inherited from the existing `CollapseRule` FromJSON instance.

## `views.raw:` (delta)

```yaml
views:
  raw: show | hide | omit             # `omit` is new
```

### Accepted values

| Value | Existing? | Semantics |
|---|---|---|
| `show` | yes (default) | Walk every item under the array site verbatim. Bucket views are inserted into a `raw/` subtree. |
| `hide` | yes | Walk every item under the array site, but prune the leaves covered by any matching rule. |
| `omit` | **new** | At array sites where at least one rule matched: bucket views are emitted, matched items' subtrees are suppressed (no per-item rendering), unmatched siblings render verbatim under their original indices. At array sites where no rule matched: behaves identically to `show` (no items to suppress). |

### `omit` no-op identity

A rules document with `views.raw: omit` and an empty `collapse: []` list MUST render identically to the same tx rendered with `views.raw: show` and an empty `collapse: []` list — `omit` is a no-op when no items are matched at any array site.

### `omit` interaction with `nested:`

- Nested rule matches at deeper array sites are still emitted as bucket views — `omit` does not suppress them.
- Per-item subtrees suppressed by `omit` are suppressed at every depth: a matched parent item's matched child item's subtree is also suppressed (because the engine never walks the matched parent item under `omit`).
- Unmatched siblings at any depth render verbatim (the suppression is matched-item-only, not array-site-wide).

### Parse-error conditions

- `views.raw: <anything other than show / hide / omit>` (e.g. `skip`, `redact`, `none`, empty string): the loader returns `Left "unsupported raw collapse view: <value>; expected show | hide | omit"`. Parse-time error, before the engine is invoked.

## Backwards compatibility contract

The following properties MUST hold post-feature:

1. **Every existing YAML parses unchanged**. Documents accepted by `parseRewriteRulesYaml` before this feature lands MUST parse to a `RewriteRules` value byte-equal to the pre-change parser result, modulo the empty `collapseRuleNested = []` defaults inside every `CollapseRule`.
2. **Every existing render is byte-identical**. Goldens captured before this feature lands — `inspect.verbatim.txt`, `inspect.collapse-only.txt`, `inspect.rename-only.txt`, the Amaru `swap-1.both.txt` *before its S3 recapture*, etc. — MUST be reproducible byte-for-byte from the same inputs under the new engine.
3. **No exported symbol is removed or renamed**. `CollapseRule`, `CollapseRules`, `CollapseRawView`, `parseRewriteRulesYaml`, `parseCollapseRulesYaml`, and every `Cardano.Tx.Rewrite` re-export continue to exist with the same names. The only additions are the new field (`collapseRuleNested`) and the new constructor (`CollapseRawOmit`).
4. **The `views.raw:` default is unchanged**. A missing `views:` block still defaults to `show`. Adding the third value does not flip the default.

## Cross-tool contract (FR-015)

Both `tx-inspect` and `tx-diff` consume the same rewriting-rules YAML through the same `parseRewriteRulesYaml` loader and the same `applyRewriteRules` plumbing. After this feature lands:

- `tx-diff swap-1 swap-2 --collapse-rules rules/amaru-treasury.yaml` MUST produce a diff where each side's `body.outputs` section renders with the new bucket-only view (the same as `tx-inspect swap-N --rules rules/amaru-treasury.yaml`).
- The shared-substrate property from #32 (per-leaf render bytes equal between the two tools) MUST hold for the nested + omit shape.

## Worked example (canonical)

The post-S3 `rules/amaru-treasury.yaml` is the canonical worked example. Its shape:

```yaml
version: 1
views:
  raw: omit

collapse:
  - name: "SwapOrder"
    at: body.outputs
    match:
      required:
        - coin
        - datum.constructor
    nested:
      - name: "ScopeOwners"
        at: datum.fields.1.fields.0
        match:
          required:
            - constructor
            - fields.0

rename:
  # unchanged from pre-S3 — script + address rules for amaru.swap.v2,
  # amaru-treasury.network_compliance, swap-order address, treasury
  # self-address, user recipient, amaru network wallet.
  - kind: script
    key: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077
    name: amaru.swap.v2
  # … (remaining entries unchanged)
```

Annotations:

- `views.raw: omit` suppresses the per-output detail tree for items matched by the `SwapOrder` rule. The two non-swap outputs (treasury-leftover, user-payment) continue to render verbatim because they do NOT match `SwapOrder` (they lack the `datum.constructor` required leaf).
- The `ScopeOwners` nested rule collapses the committee-owners list at `datum.fields.1.fields.0` (relative to each matched `SwapOrder` item) into a named bucket. Its `required: [constructor, fields.0]` covers the constructor index + the first scope-owner key-hash; the remaining scope-owners appear as variable-slot rows in the bucket header.
- The `rename:` section is unchanged from pre-S3; rename and collapse continue to compose orthogonally.

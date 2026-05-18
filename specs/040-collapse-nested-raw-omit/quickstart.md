# Quickstart: collapse engine — nested rules + `raw: omit`

**Branch**: `040-collapse-nested-raw-omit` | **Date**: 2026-05-18

Phase 1 of `/speckit.plan`. Operator-facing quick path for the two new YAML keys. This file is the human-readable companion to the formal contracts; the canonical user docs land in `docs/rewriting-rules.md` in slice S4.

## What changed

Two new keys in the rewriting-rules YAML grammar. **No new CLI**, no new flag. The same `tx-inspect <tx> --rules <yaml>` (and `tx-diff <txa> <txb> --collapse-rules <yaml>`) command from issue #32 picks up the new shape.

```yaml
# rewriting-rules YAML — only the additive deltas
collapse:
  - name: "SwapOrder"
    at: body.outputs
    match:
      required:
        - coin
        - datum.constructor
    nested:                          # NEW: child rules
      - name: "ScopeOwners"
        at: datum.fields.1.fields.0  # RELATIVE to each matched
                                     # SwapOrder item
        match:
          required:
            - constructor
            - fields.0
views:
  raw: omit                          # NEW raw-view value
                                     # show | hide | omit
```

## 1. Render the 33-chunk Amaru swap as one bucket

```bash
tx-inspect path/to/amaru-swap.cbor.hex \
    --rules rules/amaru-treasury.yaml \
    --n2c-socket-path /run/cardano-node/node.socket
```

After this feature lands (S3 updates `rules/amaru-treasury.yaml`), `body.outputs` renders as one `SwapOrder` bucket header + the nested `ScopeOwners` header + the variable-slot rows — and nothing else. The 33 per-output detail trees that used to follow the bucket are gone.

## 2. Try nested rules without `raw: omit`

If you want to keep the per-output subtrees visible (e.g. while investigating an unknown field of a swap output) but still collapse the recurring committee-owners list, leave `views.raw: hide` (the default for `rules/amaru-treasury.yaml` pre-S3) and add only the `nested:` block:

```yaml
collapse:
  - name: "SwapOrder"
    at: body.outputs
    match: { required: [coin, datum.constructor] }
    nested:
      - name: "ScopeOwners"
        at: datum.fields.1.fields.0
        match: { required: [constructor, fields.0] }
views:
  raw: hide
```

Each per-output subtree renders below the bucket (with covered leaves pruned, per existing `hide` semantics) AND inside each per-output subtree the committee-owners list appears under a `ScopeOwners` nested header.

## 3. Try `raw: omit` without nested rules

If you want the per-output noise gone but don't yet need nested buckets:

```yaml
collapse:
  - name: "SwapOrder"
    at: body.outputs
    match: { required: [coin, datum.constructor] }
views:
  raw: omit
```

`body.outputs` renders as the `SwapOrder` bucket header + variable-slot rows. The 33 per-output subtrees disappear. Outputs at the same array site that did NOT match the `SwapOrder` rule (e.g. treasury-leftover, user-payment) continue to render verbatim below the bucket.

## 4. Author depth > 1 nesting

Children may themselves carry `nested:`:

```yaml
collapse:
  - name: "OrderBook"
    at: body.outputs
    match: { required: [coin] }
    nested:
      - name: "Tier"
        at: datum.fields.0           # relative to each OrderBook item
        match: { required: [constructor] }
        nested:
          - name: "Quote"
            at: fields.0             # relative to each Tier item
            match: { required: [fields.0, fields.1] }
```

Each level's `at:` is relative to the parent's matched item. Depth is unbounded — the engine recurses as far as the rule tree carries `nested:` lists.

## 5. What does NOT change

- **The CLI surface**. `tx-inspect`, `tx-diff`, `tx-sign`, `tx-validate`, `cardano-tx-generator` all keep their existing flags and exit codes.
- **The rename layer (stage 2)**. Rename rules and the address-book semantics are untouched. Nested rules surface variable slots that remain subject to rename in the same way the parent rule's variable slots are.
- **Existing rules YAML files**. Every collapse-only YAML accepted before this feature lands continues to parse and render byte-identically. Adding `nested:` is strictly opt-in; absent → empty list → no-op.
- **The `views.raw:` defaults**. A missing `views:` block still defaults to `show`. `hide` semantics are unchanged. Only `omit` is new.

## 6. Failure modes

- `views.raw: <other>` (e.g. `skip`, `redact`, `none`): the loader returns `Left "unsupported raw collapse view: <value>; expected show | hide | omit"`. Parse-time, not render-time.
- `nested:` is not a list (e.g. a string, an object, a scalar): the loader returns `Left <YAML parse error>` with a message naming the offending entry.
- A nested rule's `at:` does not resolve in a matched item's subtree (e.g. typo in the relative path): the recursion is a silent no-op for that item — the parent's bucket still renders, no nested bucket header is emitted, and `tx-inspect` exits 0.
- An empty `nested: []` list: equivalent to omitting `nested:`. No-op.

## 7. Cross-tool symmetry

The same rewriting-rules YAML drives `tx-diff`:

```bash
tx-diff swap-1.cbor.hex swap-2.cbor.hex \
    --collapse-rules rules/amaru-treasury.yaml
```

Each side of the diff applies collapse (including nested rules and `omit`) identically. The per-side render bytes equal what `tx-inspect` produces for the corresponding transaction — the shared-substrate property from #32 is preserved.

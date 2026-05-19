# Contract: Rewriting-rules YAML grammar v2

**Branch**: `044-rewrite-rules-redesign` | **Date**: 2026-05-19

The YAML grammar accepted by `Cardano.Tx.Rewrite.parseRewriteRulesYaml` after this PR. The grammar is **additive** over the 032-shipped grammar: every legacy document parses unchanged; the new `entities:` and `blueprints:` top-level keys plus the new `nested:` and `view:` fields on collapse rules are opt-in extensions.

## Top-level document

```yaml
version: 1                          # optional, defaults to 1
views:                              # optional (legacy default for raw view)
  raw: show | hide                  # optional, defaults to show
entities:                           # NEW. Optional. List of entity declarations.
  - <Entity>
blueprints:                         # NEW. Optional. List of blueprint attachments.
  - <Blueprint>
collapse:                           # optional, defaults to []
  - <CollapseRule>                  # CollapseRule schema extended (see below)
rename:                             # LEGACY. Still accepted; parses into entities.
  - <RenameRule>                    # Unchanged shape from specs/032-tx-inspect.
```

A document with neither `entities:`, `blueprints:`, `collapse:`, nor `rename:` parses to an empty `RewriteRules` (no-op renderer).

A document that uses both `entities:` and the legacy `rename:` at the same time is accepted: both contribute to the same `EntityIndex`. The loader rejects with `EntityCollision` if the legacy and expressive forms declare the same identifier under conflicting names.

## `Entity` shape

```yaml
- name: <string>                    # required; the reviewer-facing display name
  # one or more identifier sugars; at least one must be present
  from-address: <bech32>            # optional; emits the payment + stake
                                    # credentials extracted from the bech32
                                    # under their respective role classes
  script: <56-hex>                  # optional; emits (PaymentScript, hash)
  pool: <bech32>                    # optional; emits (PoolId, hash)
  drep: <bech32>                    # optional; emits (DRepKey, hash) for
                                    # `drep1...` or (DRepScript, hash) for
                                    # `drep_script1...` per CIP-129
  stake: <bech32>                   # optional; emits (StakeKey, hash) or
                                    # (StakeScript, hash) depending on the
                                    # bech32's credential side
  asset:                            # optional; emits (AssetClass, policy <> name)
    policy: <56-hex>                # required when `asset:` is present
    name: <utf8-string or 0x-hex>   # required when `asset:` is present;
                                    # accepts a UTF-8 string (CIP-67 name) or
                                    # `0x<hex>` for arbitrary byte sequences
  keys: [<RoleClass>, ...]          # optional; explicit form. Pairs with `bytes:`
  bytes: <hex>                      # optional; pairs with `keys:`. Emits one
                                    # identifier per role class in `keys:`,
                                    # all sharing the same bytes.
```

### Sugar semantics

`from-address`: the loader parses the bech32, extracts both halves, and emits:

- one identifier under `PaymentKey` or `PaymentScript` based on the payment-credential type
- one identifier under `StakeKey` or `StakeScript` based on the stake-credential type (omitted for enterprise addresses without a stake half)

`stake` (sugar for stake-only addresses, e.g., `stake1...`): the loader extracts the stake credential and emits one `StakeKey` or `StakeScript` identifier.

`asset` (CIP-67 + CIP-68 aware): the loader concatenates `policy <> name` (canonical encoding) and emits one `AssetClass` identifier. The `name:` field accepts a literal UTF-8 string for human-readable asset names and a `0x<hex>` form for arbitrary byte sequences (CIP-68 reference-token names with non-printable prefixes).

`keys` + `bytes` (escape hatch for entities whose identifier doesn't fit any sugar): the operator lists the role classes the bytes apply to. Example — a treasury whose payment credential and minting policy share a hash:

```yaml
- name: usdm-control
  keys: [PaymentScript, Policy]
  bytes: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad
```

### Validation (loader)

- An entity with zero identifiers → `EntityZeroIdentifiers <name>`.
- Two entities declaring the same `(role-class, bytes)` pair → `EntityCollision (role-class, bytes) (<name1>, <name2>)`. Order in the YAML is preserved for the error message.
- A `from-address` / `pool` / `drep` / `stake` value that fails bech32 decoding → `EntityBadBech32 <name> <input>`.
- A `script` / `bytes` / `asset.policy` value that is not 56-character lowercase hex (28 bytes) → `EntityBadHex <name> <input>`.
- An `asset.name` value with more than 32 bytes after decoding → `EntityBadAssetName <name> <input>`.
- A `keys:` value containing an unknown role class → parse error with the list of accepted role classes.

## `Blueprint` shape

```yaml
- script: <56-hex> or <entity-name>   # required; identifies the script the
                                      # blueprint decodes for
  datum: <path>                       # optional; CIP-0057 file for datum
                                      # schemas attached to this script's
                                      # UTxOs
  redeemer: <path>                    # optional; CIP-0057 file for redeemer
                                      # schemas the script consumes
```

### Validation (loader)

- A `script:` that is neither 56-hex nor a known entity name → `BlueprintBadScriptRef <input>`.
- A `script:` that is an entity name but that entity has no `(PaymentScript, _)` or `(Policy, _)` identifier → `BlueprintBadScriptRef <name>`.
- A `datum:` or `redeemer:` file that doesn't exist → `BlueprintFileNotFound <path>`.
- A `datum:` or `redeemer:` file that doesn't parse via `Cardano.Tx.Blueprint.parseBlueprintJSON` → `BlueprintParseError <path> <reason>`.
- Two `Blueprint` entries pointing at the same script hash → `BlueprintCollision <hash>`.

A `Blueprint` entry with neither `datum:` nor `redeemer:` is accepted (no-op), to keep documents stable when an operator is in the middle of authoring.

## `CollapseRule` shape (extended)

```yaml
- name: <string>                    # required
  at: <DiffPath>                    # required
  match:                            # required
    required:                       # required
      - <DiffPath relative to each matched item>
  nested:                           # NEW. Optional. List of child rules
    - <CollapseRule>                # whose `at:` is relative to each
                                    # parent-matched item's subtree.
                                    # Arbitrary depth.
  view: show | hide-matched | omit  # NEW. Optional. Defaults to the
                                    # document's `views.raw:` setting
                                    # (or `show` if absent).
```

`DiffPath` is the existing dot-separated literal-segment form from 032.

### Path semantics in the presence of blueprints

When a blueprint is attached to the script of a UTxO at `body.inputs.N`, the `datum.` subtree of that input is decoded via the blueprint *before* `at:` and `match:` paths are evaluated. The operator can reference blueprint-typed fields by their symbolic name:

```yaml
collapse:
  - name: SwapOrderInput
    at: body.inputs
    match:
      required:
        - resolved.address
        - datum.SwapOrder.recipient    # uses the blueprint's constructor +
                                       # field names
```

When the same rule is applied to an input whose script has no blueprint, the rule does not match that input (because `datum.SwapOrder.recipient` is not a path in the un-decoded raw-data view). The other inputs render normally below the bucket.

## `RenameRule` shape (legacy, retained)

Unchanged from 032. Loader bridges into the `EntityIndex`:

| Legacy rule | EntityIndex contribution |
|---|---|
| `kind: address, key: <bech32>, match: payment` | `(PaymentKey-or-PaymentScript, <bytes>)` under entity named `<name>` |
| `kind: address, key: <bech32>, match: full` | both `(PaymentKey-or-PaymentScript, <bytes>)` and `(StakeKey-or-StakeScript, <bytes>)` under entity named `<name>` |
| `kind: script, key: <56-hex>` | `(PaymentScript, <bytes>)` under entity named `<name>` |

A document mixing legacy `rename:` and new `entities:` is accepted; both contribute to the same index. Conflicts are detected and reported the same as same-form collisions.

## Backwards-compatibility checklist

- Every 032-passing YAML document parses to a `RewriteRules` value whose rendered output is byte-identical to the 032 path (modulo SC-005 strictly-better carve-outs).
- The global `views.raw:` setting is preserved as a per-tx default for the new collapse view; the per-rule `view:` field overrides when present.
- The legacy stage-order rule (collapse first, rename second) is preserved as an engine invariant — the new typed-leaf walker drives collapse, which in turn drives rename at each typed leaf; the order is therefore the same end-to-end behaviour.

## Out of scope for this contract

- Wildcards in `at:` (still rejected — operator uses `nested:` instead).
- Pattern-matching on subtree shape beyond the existing `match.required:` list.
- Operator overrides of blueprint-supplied constructor / field names (deferred; spec Assumptions section).
- Multi-tx documents (rules YAML is always per-tx-style; a future `tx-batch` would author its own document shape if needed).

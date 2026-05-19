# Contract: Blueprint loader

**Branch**: `044-rewrite-rules-redesign` | **Date**: 2026-05-19

How the rewriting-rules YAML's `blueprints:` section becomes a `BlueprintIndex` consumed by the renderer at typed-leaf classification time. Establishes the contract between `Cardano.Tx.Rewrite` (loader) and `Cardano.Tx.Diff` (renderer); the actual CIP-0057 parsing remains owned by `Cardano.Tx.Blueprint` (existing module — see [research.md R3](../research.md#r3-blueprint-decode-already-exists-this-plan-only-wires-it-to-rename)).

## Loader entry point

```haskell
loadBlueprintIndex ::
    Map Text Entity            -- ^ entity table, for script-name resolution
    -> [YamlBlueprintEntry]    -- ^ raw parsed blueprints: section
    -> IO (Either BlueprintLoadError BlueprintIndex)
```

`IO` because the loader reads `datum:` / `redeemer:` files from disk. The loader resolves working-directory-relative paths against the YAML document's location (i.e., if `rules/contingency.yaml` references `./blueprints/contingency.cip57.json`, the path resolves to `rules/blueprints/contingency.cip57.json`).

## Resolution algorithm

For each `YamlBlueprintEntry`:

1. **Resolve the script reference** (`script:` field):
   - If 56-character lowercase hex → parse as `ScriptHash` directly.
   - Otherwise → look up in the entity table. The named entity must carry a `(PaymentScript, hash)` or `(Policy, hash)` identifier; pick the `PaymentScript` identifier if both are present. If the entity has neither, return `BlueprintBadScriptRef`.

2. **Load the schema files** (`datum:` and/or `redeemer:`):
   - For each path: open file → `BlueprintFileNotFound` on `IOError`; read bytes → `parseBlueprintJSON :: ByteString -> Either String Blueprint` → wrap any `Left` as `BlueprintParseError path reason`.
   - A blueprint entry may carry one or both of `datum:` and `redeemer:`; both fields populated produce a single `Blueprint` whose datum/redeemer schemas are merged (the existing `Blueprint` record supports both).

3. **Insert into the index**:
   - On duplicate `ScriptHash` → `BlueprintCollision`.

4. **Return** `BlueprintIndex (Map ScriptHash Blueprint)`.

## Renderer consumption

`HumanRenderOptions` gains `humanBlueprintIndex :: Maybe BlueprintIndex`. The renderer consults the index in two paths:

### Path A — datum decode at a script-locked UTxO

When `renderOpenValueHuman` enters the `datum` subtree of an input whose `resolved.address` carries a `PaymentScript` credential, it:

1. Looks up `(scriptHash, blueprint)` in `humanBlueprintIndex`.
2. On hit: decodes the datum bytes via `Cardano.Tx.Blueprint.decodeBlueprintData blueprint dat`. The decoded AST replaces the raw-data subtree in the render output. Each blueprint-typed leaf is classified via `classifyBlueprintLeaf` and dispatched through `humanEntityIndex` (typed-leaf walker).
3. On miss: renders the datum verbatim as raw Plutus Data; no rename fires inside (FR-006).
4. On decode failure: emits a structured warning via the renderer's diagnostic channel; renders the datum verbatim (FR-015).

### Path B — redeemer decode at a script-spending input

Same as Path A, applied to the redeemer subtree found in the witness set under the spending input's pointer. The blueprint's `redeemer:` schema is consulted; same on-hit / on-miss / on-failure semantics.

## Constructor + field name resolution

When the blueprint is consulted, the renderer uses the blueprint's constructor + field names instead of positional indices:

| Without blueprint | With blueprint (example) |
|---|---|
| `datum.constructor: 0` | `datum.SwapOrder` |
| `datum.fields.0` | `datum.SwapOrder.recipient` |
| `datum.fields.1.fields.0` | `datum.SwapOrder.expiry` |

The name resolution is owned by `Cardano.Tx.Blueprint` (its existing `BlueprintArgumentSelector` machinery) — the rewriting-rules loader does not interpret blueprint schemas itself.

## Collapse + blueprint interaction

A collapse rule whose `match.required:` references a path under `datum.<ConstructorName>.<fieldName>` matches only those items whose script has a blueprint registered for it. Items without a blueprint fail the rule's `required:` check (the path doesn't exist in the un-decoded view) and render uncollapsed below the bucket. This is the FR-checked behaviour from the spec's Edge Cases.

## Diagnostic channel

Blueprint decode failures are surfaced to stderr (not to the rendered output) using a structured prefix:

```
[blueprint] decode failed for script <script-hash> at <DiffPath>: <reason>
```

The line is emitted once per (script, path) pair per render. Downstream `tx-inspect` callers (CI graders, etc.) can grep for the `[blueprint]` prefix to detect blueprint drift. The renderer's exit code is unaffected — fallback to verbatim is the expected behaviour.

## Loader test surface

Covered by `BlueprintRenameSpec` (S5):

| Scenario | Expected behaviour |
|---|---|
| Valid datum schema → typed leaves substituted | render shows entity name at blueprint-typed leaf |
| No blueprint → raw bytes verbatim | render shows `{"bytes":"..."}`; no rename fires; no warning |
| Blueprint decode failure (shape mismatch) | render shows raw verbatim; stderr emits `[blueprint] decode failed …` |
| Blueprint for a script that doesn't appear in the tx | silently ignored; no error |
| Two `blueprints:` entries for the same script hash | loader rejects with `BlueprintCollision` |
| Blueprint references an entity name; entity has no script identifier | loader rejects with `BlueprintBadScriptRef` |

## Out of scope for this contract

- Hot-reload of blueprints during a long-running `tx-inspect` session (current `tx-inspect` is one-shot).
- Per-tx override of blueprint registration via CLI flag (current registration is YAML-only).
- A blueprint *validator* (CIP-0057 also defines `validators` describing on-chain script metadata) is parsed by `Cardano.Tx.Blueprint.parseBlueprintJSON` but not consumed by this PR; reserved for a future ticket that surfaces validator parameters at `tx-inspect` time.

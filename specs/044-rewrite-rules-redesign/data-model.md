# Data Model: `Cardano.Tx.RewriteRules`

**Branch**: `044-rewrite-rules-redesign` | **Date**: 2026-05-19

Phase 1 of `/speckit.plan`. Pins the Haskell types the new module introduces and the integration points in the existing modules. The YAML grammar that maps to these types lives in [contracts/rules-yaml-grammar-v2.md](./contracts/rules-yaml-grammar-v2.md). The blueprint loader's contract lives in [contracts/blueprint-loader-contract.md](./contracts/blueprint-loader-contract.md).

## Top-level types

### `Entity`

```haskell
data Entity = Entity
    { entityName :: Text
    -- ^ The reviewer-facing display name. Operator-supplied; preserved
    -- verbatim by the renderer.
    , entityIds :: NonEmpty Identifier
    -- ^ The (role-class, bytes) pairs by which this entity is
    -- identifiable. Non-empty by FR-011.
    }
    deriving stock (Eq, Show)
```

### `Identifier`

```haskell
data Identifier = Identifier
    { identifierRole :: RoleClass
    , identifierBytes :: ByteString
    -- ^ Canonical encoding. 28-byte hash for most role classes;
    -- `policy <> name` concatenation for AssetClass.
    }
    deriving stock (Eq, Ord, Show)
```

### `RoleClass`

```haskell
data RoleClass
    = PaymentKey       -- 28-byte Ed25519 key hash, payment side
    | PaymentScript    -- 28-byte script hash, payment side
    | StakeKey         -- 28-byte Ed25519 key hash, stake side
    | StakeScript      -- 28-byte script hash, stake side
    | DRepKey          -- 28-byte Ed25519 key hash, DRep credential
    | DRepScript       -- 28-byte script hash, DRep credential
    | PoolId           -- 28-byte cold-key hash
    | Policy           -- 28-byte minting policy hash (script hash, distinct
                       --                                semantic role from
                       --                                PaymentScript)
    | AssetClass       -- compound: `policy <> name`; canonical concatenation
    deriving stock (Eq, Ord, Show, Enum, Bounded)
```

**Notes**:
- The enum is closed (R1). Adding a constructor is a breaking library API change.
- `Enum` + `Bounded` are derived so the loader can iterate role classes when generating "did you mean?" error messages.
- `Ord` is required because `RoleClass` participates in the `EntityIndex` map key (`(RoleClass, ByteString)`).

### `EntityIndex`

```haskell
newtype EntityIndex = EntityIndex
    { unEntityIndex :: Map (RoleClass, ByteString) Entity
    }
    deriving stock (Eq, Show)
```

**Builder**:

```haskell
mkEntityIndex :: [Entity] -> Either EntityLoadError EntityIndex
```

Validates:
- FR-010: no two distinct entities share the same `(role-class, bytes)` pair. On collision, returns `EntityCollision (RoleClass, ByteString) (Text, Text)` naming both entities.
- FR-011: every entity has a non-empty `entityIds` (enforced by the `NonEmpty` type, so this case is statically impossible — included in the error type only for the YAML loader, which constructs Entity from possibly-empty parsed lists).

**Lookup**:

```haskell
lookupEntity :: RoleClass -> ByteString -> EntityIndex -> Maybe Entity
```

Constant-time on the underlying `Map`.

### `EntityLoadError`

```haskell
data EntityLoadError
    = EntityCollision (RoleClass, ByteString) (Text, Text)
      -- ^ Two entities (named) declared the same identifier.
    | EntityZeroIdentifiers Text
      -- ^ Entity name with no identifiers.
    | EntityBadBech32 Text Text
      -- ^ A `from-address` / `pool` / `drep` / `stake` sugar value that
      -- failed bech32 decoding. First Text = the rule's entity name;
      -- second = the offending input.
    | EntityBadHex Text Text
      -- ^ A `script` / `bytes` / `asset.policy` value that failed hex
      -- decoding or was the wrong length.
    | EntityBadAssetName Text Text
      -- ^ An `asset.name` value that was not valid UTF-8 / not the right
      -- byte length per CIP-67.
    deriving stock (Eq, Show)
```

The loader produces structured errors; the YAML wrapper converts them to a printable message at `Left :: String` boundary.

## Blueprint integration types

### `BlueprintIndex`

```haskell
newtype BlueprintIndex = BlueprintIndex
    { unBlueprintIndex :: Map ScriptHash Blueprint
    }
    deriving stock (Eq, Show)
```

`Blueprint` is the existing type from `Cardano.Tx.Blueprint`. The loader builds the index from the YAML `blueprints:` section by:

1. Resolving each entry's `script:` field to a `ScriptHash` (either an explicit hex hash, or by name pointing at a previously-declared entity carrying a `(PaymentScript, hash)` or `(Policy, hash)` identifier).
2. Parsing the referenced file via `Cardano.Tx.Blueprint.parseBlueprintJSON`.
3. Inserting `(scriptHash, blueprint)` into the map. Duplicate script hashes are rejected at load time with `BlueprintCollision ScriptHash`.

### `BlueprintLoadError`

```haskell
data BlueprintLoadError
    = BlueprintBadScriptRef Text
    | BlueprintFileNotFound FilePath
    | BlueprintParseError FilePath String
    | BlueprintCollision ScriptHash
    deriving stock (Eq, Show)
```

## Typed-leaf classification

### `TypedLeaf`

```haskell
data TypedLeaf = TypedLeaf RoleClass ByteString
    deriving stock (Eq, Show)
```

### `classifyLeaf`

```haskell
classifyLeaf :: ConwayDiffValue -> Maybe TypedLeaf
```

Inspects a `ConwayDiffValue` from the Conway projection and, if it's a leaf at a known typed site, returns the corresponding `(RoleClass, ByteString)` pair. Sites the function covers (full list pinned during S3 implementation):

| `ConwayDiffValue` shape | Role class produced |
|---|---|
| `ConwayAddressValue` with `Addr` payment side `KeyHashObj _` | `PaymentKey` |
| `ConwayAddressValue` with `Addr` payment side `ScriptHashObj _` | `PaymentScript` |
| `ConwayRewardAccountValue` with `KeyHashObj _` stake-cred | `StakeKey` |
| `ConwayRewardAccountValue` with `ScriptHashObj _` stake-cred | `StakeScript` |
| `ConwayScriptValue ScriptHash` (witness/ref-script) | `PaymentScript` |
| `ConwayPoolIdValue` | `PoolId` |
| `ConwayDRepValue` with `KeyHashObj _` | `DRepKey` |
| `ConwayDRepValue` with `ScriptHashObj _` | `DRepScript` |
| `ConwayPolicyIdValue` (mint, value-map key) | `Policy` |
| `ConwayAssetMapEntry (policy, name)` | `AssetClass` (bytes = `policy <> name`) |
| anything else | `Nothing` (verbatim render) |

### `classifyBlueprintLeaf`

```haskell
classifyBlueprintLeaf :: BlueprintLeafContext -> Data -> Maybe TypedLeaf
```

`BlueprintLeafContext` carries the blueprint-declared semantic role of the leaf (PubKeyHash / Credential / AssetClass / etc.) which lets the function map a `Data` value (the existing Plutus data leaf) into a `(RoleClass, ByteString)`. The mapping table mirrors CIP-0057's type vocabulary:

| Blueprint type | Data shape | Role class produced |
|---|---|---|
| `PubKeyHash` | 28-byte `B` | `PaymentKey` |
| `ScriptHash` | 28-byte `B` | `PaymentScript` |
| `Credential` (PlutusV2/V3) | `Constr 0 [B 28-byte]` | `PaymentKey` |
| `Credential` | `Constr 1 [B 28-byte]` | `PaymentScript` |
| `StakeCredential` | analogous to Credential | `StakeKey` / `StakeScript` |
| `PolicyId` (alias of `ScriptHash` in mint context) | 28-byte `B` | `Policy` |
| `AssetClass` | `Constr 0 [B policy, B name]` | `AssetClass` (bytes = `policy <> name`) |
| `PoolId` | 28-byte `B` (extension; not yet in baseline CIP-57) | `PoolId` |
| `DRep` | tagged union (covered in BlueprintRenameSpec) | `DRepKey` / `DRepScript` |
| any other type / shape mismatch | `Nothing` | verbatim |

## Collapse rule

### `CollapseRule`

```haskell
data CollapseRule = CollapseRule
    { crName :: Text
    , crAt :: DiffPath
    , crRequired :: [DiffPath]
    -- ^ Relative paths inside each item that must be present for the
    -- rule to fire and that constitute the bucket's variable slots.
    , crNested :: [CollapseRule]
    -- ^ Child rules interpreted with `at:` relative to each matched
    -- item's subtree. Arbitrary depth (FR-008).
    , crView :: ItemView
    -- ^ How the matched items render below the bucket (FR-009).
    }
    deriving stock (Eq, Show)
```

### `ItemView`

```haskell
data ItemView
    = ShowItem            -- render the matched item below the bucket in full
    | HideMatchedLeaves   -- prune leaves the rule covered; render the rest
    | OmitItem            -- bucket only; matched items don't appear below
    deriving stock (Eq, Show)
```

`ShowItem` is the legacy `raw: show` default; `HideMatchedLeaves` is the legacy `raw: hide`; `OmitItem` is new in this PR (FR-009). The global `views.raw:` setting from 032 is preserved as a per-tx default; the per-rule `crView` overrides when present.

## Top-level wrapper

### `RewriteRules` (new shape)

```haskell
data RewriteRules = RewriteRules
    { rrEntityIndex :: EntityIndex
    , rrBlueprintIndex :: BlueprintIndex
    , rrCollapseRules :: [CollapseRule]
    , rrLegacyDefaults :: LegacyDefaults
    }
    deriving stock (Eq, Show)
```

`LegacyDefaults` carries the global `views.raw:` setting and any other pre-existing per-document defaults so the loader can reconstruct 032 documents byte-equivalently. The 032 `RewriteRules` shape is **NOT** kept as-is; it is replaced by this record. The bridge in `Cardano.Tx.Rewrite.parseRewriteRulesYaml` returns the new record from both legacy and entities-first YAML documents.

**Backwards compatibility for downstream code that pattern-matched on the old `RewriteRules`**: the deprecated re-exports `rewriteCollapse :: RewriteRules -> CollapseRules` and `rewriteRename :: RewriteRules -> RenameRules` are kept as derived functions during S2–S6 (they project out a legacy view of the new record) and dropped in S7. Downstream `tx-inspect`'s `Main.hs` is updated in S2 to call the new accessors.

## HumanRenderOptions integration

`Cardano.Tx.Diff.HumanRenderOptions` gains:

```haskell
data HumanRenderOptions = HumanRenderOptions
    { -- existing fields …
    , humanEntityIndex :: Maybe EntityIndex
    -- ^ NEW. When `Just`, every typed leaf reached by the renderer
    -- is dispatched through this index for substitution.
    , humanBlueprintIndex :: Maybe BlueprintIndex
    -- ^ NEW. When `Just`, datum/redeemer subtrees whose parent UTxO's
    -- script appears in the index are decoded via CIP-57 and their
    -- leaves classified for rename.
    -- The existing humanCollapseRules and humanRenameRules fields
    -- remain in place for the deprecation window (S2–S6).
    }
```

When both old and new index fields are populated, the new index wins. The legacy `humanRenameRules` field is dropped in S7.

## Invariants

- **Role-class narrowness**: a lookup of `(PaymentKey, bs)` will not match an entity declared only under `(StakeKey, bs)` (FR-012).
- **Asset-class compound key**: `AssetClass` identifier bytes are canonically `policy <> name` (28 bytes + ≤32 bytes per CIP-67). The asset-map renderer composes the lookup key the same way (R6).
- **Loader rejection is total**: every `EntityLoadError` / `BlueprintLoadError` constructor maps to a deterministic message; the loader never produces an `EntityIndex` containing a collision or an entity with zero identifiers.
- **Render never throws on missing entity**: an unmatched typed leaf renders verbatim (FR-006-analogue for the Conway projection). No partial-function defaults.

## Test surface

| Test module | Targets |
|---|---|
| `EntityIndexSpec` | Builder + collision detection + role-class narrowness |
| `LoadSpec` | Legacy-form parity + entities-first form + all six sugar forms |
| `WalkerSpec` | `classifyLeaf` coverage + `#43` reproducer + cross-leaf identity |
| `CollapseSpec` | Nested depth-1/depth-2 + per-rule view + legacy-compat |
| `BlueprintRenameSpec` | Blueprint-decoded leaves + decode-failure fallback + FR-006 negative |
| `AssetClassSpec` | Multi-asset map collapse + same-bytes-as-script coexistence |

All test modules are pure Haskell against the new module surface. The end-to-end golden tests for the ten user stories are delivered by [issue #45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45) and consume this PR's engine via the same `tx-inspect` CLI surface.

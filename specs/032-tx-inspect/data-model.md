# Data Model: `Cardano.Tx.Rewrite`

**Branch**: `032-tx-inspect` | **Date**: 2026-05-18

Phase 1 of `/speckit.plan`. Pins the Haskell types the new module
introduces; the YAML grammar that maps to these types lives in
`contracts/rules-yaml-grammar.md`.

## Types

### `RewriteRules`

```haskell
data RewriteRules = RewriteRules
    { rewriteCollapse :: CollapseRules
    -- ^ Stage 1 rules. Carries the existing `CollapseRules` record
    -- unchanged (including its `collapseRawView` field).
    , rewriteRename :: RenameRules
    -- ^ Stage 2 rules. Empty when the YAML has no `rename:` key.
    }
    deriving (Eq, Show)
```

**Defaults**: `defaultRewriteRules` ≡ `RewriteRules CollapseRules{ collapseRawView = CollapseRawShow, collapseRules = [] } emptyRenameRules`.

**Invariants**: none beyond the per-stage invariants of `CollapseRules` and `RenameRules`. The stage order (collapse first, rename second) is enforced at *application* time by `applyRewriteRules`, not at construction.

---

### `RenameRules`

```haskell
newtype RenameRules = RenameRules { renameEntries :: [RenameRule] }
    deriving (Eq, Show)

emptyRenameRules :: RenameRules
emptyRenameRules = RenameRules []
```

**Implementation note**: list ordering is preserved by `parseRewriteRulesYaml` so a deterministic conflict-resolution rule (currently "first match wins" — see *Conflict Resolution* below) is available even though the spec lists conflict resolution as out-of-scope for this PR. The list form is also what the rename application path consumes; a derived `Map (Either AddressKey ScriptHash) Text` is built once per rule set at apply time.

---

### `RenameRule`

```haskell
data RenameRule
    = RenameAddress
        { renameAddressKey :: Text
        -- ^ The bech32 string as it appeared in the YAML. Preserved
        -- verbatim for round-trip + error messages; matching uses
        -- the parsed payment credential (when `match: payment`) or
        -- the canonical bech32 (when `match: full`), captured below.
        , renameAddressMatch :: AddressMatch
        , renameAddressTarget :: AddressTarget
        -- ^ Pre-computed lookup key from the bech32 string, set
        -- once by the FromJSON instance at parse time.
        , renameName :: Text
        }
    | RenameScript
        { renameScriptHash :: ScriptHash
        -- ^ Parsed from the hex string at YAML load time.
        , renameName :: Text
        }
    deriving (Eq, Show)

data AddressMatch = MatchFull | MatchPayment
    deriving (Eq, Show)

data AddressTarget
    = TargetFullAddress Addr
    -- ^ For `match: full`. The full ledger Addr (payment + stake)
    -- as parsed from the bech32 string.
    | TargetPaymentCredential PaymentCredential
    -- ^ For `match: payment`. The payment credential extracted
    -- from the parsed bech32, with the stake credential
    -- discarded.
    deriving (Eq, Show)
```

Notes:
- `Addr` and `PaymentCredential` are the existing ledger types already imported by `Cardano.Tx.Diff`.
- `MatchPayment` is the default when `match:` is missing in YAML (FR-009).
- An invalid bech32 in `renameAddressKey`, or a `kind: address` rule whose bech32 cannot be decoded, is a *parse-time* failure: `parseRewriteRulesYaml` returns `Left`.
- An invalid hex script hash in `renameScriptHash` is similarly a parse-time failure.

---

### `parseRewriteRulesYaml`

```haskell
parseRewriteRulesYaml :: BS.ByteString -> Either String RewriteRules
```

Behavior:
- Decodes the bytes as a YAML object using the same `Data.Yaml` path `parseCollapseRulesYaml` uses.
- The object keys `version`, `views`, `collapse` are parsed by the existing `CollapseRules` FromJSON instance (reused unchanged).
- The optional `rename:` key is parsed as a list of `RenameRule` entries via a new FromJSON instance. Missing or empty `rename:` ⇒ `emptyRenameRules`.
- A document with neither `collapse:` nor `rename:` parses to `defaultRewriteRules`.

The legacy `parseCollapseRulesYaml :: BS.ByteString -> Either String CollapseRules` is **kept** (unchanged) so existing consumers (`tx-diff`) compile without churn. Internally, `parseRewriteRulesYaml` can be expressed in terms of `parseCollapseRulesYaml` plus the rename-key handling — but exposing it as its own top-level function is clearer for new consumers.

---

### `applyRewriteRules`

Per the planning-phase correction (see [research.md R1](./research.md#r1-renderer-extraction-a-new-top-level-entry-sharing-the-projection--render-primitives)), the top-level type the renderer consumes is `ConwayTx` (via `renderConwayTxHuman`), not `OpenValue`. The rename layer's site list (payment addresses + script hashes) lives in `ConwayDiffValue` leaves, not `OpenValue` leaves. The `applyRewriteRules` signature is therefore deferred to **S3 planning**, where rename application lands. S1 only ships the types and the parser.

The current best-guess shape (subject to S3 refinement) is one of:

```haskell
-- S3 will pick one of these (or a small variant):

-- (a) Apply collapse + rename to a ConwayDiffValue tree before rendering.
applyRewriteRulesConwayTx ::
    RewriteRules -> HumanRenderOptions -> ConwayDiffValue -> (HumanRenderOptions, ConwayDiffValue)

-- (b) Hand RewriteRules to renderConwayTxHuman and have it apply both stages inline.
renderConwayTxHumanWithRewrite ::
    HumanRenderOptions -> TxDiffOptions -> RewriteRules -> ConwayTx -> Text
```

Behavior is unchanged from the original sketch:
- **Stage 1 (collapse)**: collapse rules apply to the projection tree (`ConwayDiffValue` or its child branches as `humanCollapseRules` already handles in the diff renderer).
- **Stage 2 (rename)**: walks the `ConwayDiffValue` tree, rewriting payment-address and script-hash leaves per `rewriteRename rr`.

Stage order is hard-wired (collapse first, rename second), independent of YAML key order.

---

### `humanRenameRules` field on `HumanRenderOptions`

```haskell
data HumanRenderOptions = HumanRenderOptions
    { ... -- existing fields
    , humanCollapseRules :: Maybe CollapseRules
    , humanRenameRules :: Maybe RenameRules   -- NEW
    }

defaultHumanRenderOptions :: HumanRenderOptions
defaultHumanRenderOptions =
    HumanRenderOptions
        { ... -- existing defaults
        , humanCollapseRules = Nothing
        , humanRenameRules = Nothing   -- NEW
        }
```

This addition is **additive only**. Existing record-update call sites (e.g. `defaultHumanRenderOptions { humanCollapseRules = Just rules }`) compile unchanged. The renderer applies `humanRenameRules` (if `Just`) to the input `OpenValue` before walking it.

---

## Conflict Resolution

The spec lists rename-rule conflict resolution as out-of-scope. The implementation must still pick a deterministic policy when two rules map the same identifier to different names within a single `--rules` file:

- **Policy**: *first matching rule wins*. The list order in `renameEntries` is preserved by the YAML parser; the apply path's derived lookup map is built by `Map.fromListWith (\_old new -> new)` *in reverse list order* — which collapses to "the first occurrence in the YAML file is what survives".
- **Rationale**: matches a YAML reader's left-to-right expectation; needs no additional configuration; is easy to override (delete the conflicting rule).
- **Not surfaced to users as a feature**. If conflict resolution becomes a recurring need it gets a separate ticket.

---

## Relationship to existing types

| Existing type | Status under this feature |
|---|---|
| `CollapseRule` | reused unchanged |
| `CollapseRules` | reused unchanged |
| `CollapseRuleMatch` | reused unchanged |
| `CollapseViews`, `CollapseRawView` | reused unchanged |
| `OpenValue` | reused unchanged; `applyRewriteRules` walks it but does not alter its types |
| `DiffPath` | reused unchanged |
| `HumanRenderOptions` | one additive field (`humanRenameRules`) |
| `defaultHumanRenderOptions` | updated to set `humanRenameRules = Nothing` |
| `parseCollapseRulesYaml` | reused unchanged |
| `renderDiffNodeHuman[With]` | per-side delegation to the new `renderOpenValueHuman[With]` (S1); output byte-identical for empty rename rules |

No type is renamed, removed, or signature-changed.

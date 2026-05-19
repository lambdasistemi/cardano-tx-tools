# Contract — `test/fixtures/rewrite-redesign/` filesystem layout

**Phase**: 1 (Design & Contracts).
**Owner**: this PR.
**Consumers**: `#47` (emitter), `#50` (blueprint decode), `#51` (cli-tree view), and any future engine PR reviewer.

## Directory layout

Two sibling subtrees: a **Haskell module subtree** under `Fixtures/RewriteRedesign/` whose path matches each module name 1:1 (GHC requirement — `Fixtures.RewriteRedesign.S02_AliceBobAda` cannot resolve from a Haskell-illegal directory name like `02-alice-bob-ada`), and ten **per-fixture data-file directories** named `<NN>-<kebab-slug>/` holding the non-Haskell artifacts. The `StoryId` is the kebab directory name; the corresponding module's `S<NN>_<CamelCaseSlug>` name is mechanically derivable from it.

```text
test/fixtures/rewrite-redesign/
├── Fixtures/                                              # Haskell module subtree
│   └── RewriteRedesign/
│       ├── Helpers.hs                                     # Fixtures.RewriteRedesign.Helpers
│       ├── S01_AmaruTreasurySwap.hs                       # exports `tx`, `shape`
│       ├── S02_AliceBobAda.hs
│       ├── S03_MultiAssetTransfer.hs
│       ├── S04_MintSpendScriptOverlap.hs
│       ├── S05_WithdrawalScriptStake.hs
│       ├── S06_StakePoolDelegation.hs
│       ├── S07_VoteDelegation.hs
│       ├── S08_ContingencyDisburse.hs
│       ├── S09_MpfsFactsRequest.hs
│       └── S10_GovernanceTreasuryWithdrawal.hs
├── blueprints/                                            # CIP-57 data files
│   ├── swap-v2-datum.cip57.json                           # consumed by S01 / 01-amaru-treasury-swap
│   └── mpfs-fact.cip57.json                               # consumed by S09 / 09-mpfs-facts-request
├── 01-amaru-treasury-swap/                                # per-fixture data-file directory
│   ├── rules.yaml
│   ├── expected.txt                                       # vocab-independent (A-side)
│   └── expected.ttl                                       # vocab-pinned (B-side, post-signal)
├── 02-alice-bob-ada/
│   └── (same three files)
├── 03-multi-asset-transfer/
│   └── (same three files)
├── 04-mint-spend-script-overlap/
│   └── (same three files)
├── 05-withdrawal-script-stake/
│   └── (same three files)
├── 06-stake-pool-delegation/
│   └── (same three files)
├── 07-vote-delegation/
│   └── (same three files)
├── 08-contingency-disburse/
│   └── (same three files)
├── 09-mpfs-facts-request/
│   └── (same three files)
└── 10-governance-treasury-withdrawal/
    └── (same three files)
```

Ten data-file directories named `<NN>-<kebab-slug>`. The two-digit `NN` prefix matches the 044 story number. Each `S<NN>_<CamelCaseSlug>.hs` references the corresponding kebab directory via its `StoryId` constructor + `mkFixturePaths`.

## Per-file contracts

### `Fixtures.RewriteRedesign.S<NN>_<CamelCaseSlug>` Haskell module

- Filesystem path: `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S<NN>_<CamelCaseSlug>.hs` (driven by GHC module-name resolution).
- Exports at least three top-level bindings:
  - `storyId :: StoryId` — the kebab-slug constructor for this fixture's data-file directory.
  - `tx :: ConwayTx` — the fixture's transaction value (using the project-local `ConwayTx` alias from `Cardano.Tx.Ledger`).
  - `shape :: ExpectedShape` — the body-field counts the structural Hspec item asserts on.
- Built via `Fixtures.RewriteRedesign.Helpers.mkTx { ... }` declarative record style.
- ≤ 80 lines (excluding imports and the module header). Reviewability gate per SC-007.
- Compiles under the existing `unit-tests` cabal warnings (`-Wall -Werror`).
- Carries a Haddock module header in canonical `{- | Module ... -}` form per constitution IV.

### `rules.yaml`

- UTF-8 text, LF line endings, no BOM.
- Verbatim copy of the corresponding 044 user-story's `Rules YAML` code-block.
- Parses successfully via `Cardano.Tx.Rewrite.parseRewriteRulesYaml` (existing parser, or its additive extension landed in slice S4 if needed).

### `expected.txt`

- UTF-8 text. Whitespace canon:
  - trailing whitespace stripped per line,
  - exactly one final newline (`\n`),
  - no tab characters,
  - no BOM.
- Byte-equal to the corresponding 044 user-story's `Expected rendered output` code-block under that canon.
- A-side artifact (lands ahead of kmaps#53 Phase A signal).

### `expected.ttl`

- UTF-8 text, well-formed Turtle (parses via the harness's internal shim).
- Uses only `cardano:` prefix URIs published by `cardano-knowledge-maps#53` Phase A. May additionally use locally-declared prefixes (e.g. `tx:`, the operator's own `:` for entity URIs).
- Represents the **un-inferred** base graph the emitter (#47) is contracted to produce. No `owl:sameAs` deductions.
- Contains, at minimum:
  - one `cardano:Transaction` node with all body-field properties the 044 story names,
  - one `cardano:Identifier` node per typed-leaf the projection touches,
  - the operator's `cardano:Entity` triples (compiled from `rules.yaml`),
  - (for fixtures 01 and 09) blueprint-decoded datum triples.
- B-side artifact (lands AFTER the kmaps#53 Phase A signal; see `kmaps-signal.md`).

### `blueprints/swap-v2-datum.cip57.json`

- Minimal CIP-57 JSON. Exposes a single constructor `SwapOrder` with a `recipient: Credential` field.
- Consumed by fixture `01-amaru-treasury-swap`.

### `blueprints/mpfs-fact.cip57.json`

- Minimal CIP-57 JSON. Exposes a single constructor `Fact` with a `requester: PubKeyHash` field.
- Consumed by fixture `09-mpfs-facts-request`.

## Invariants

- **No on-disk CBOR**. Fixtures are Haskell modules; no `Tx ConwayEra` is serialized to disk in this harness.
- **Reviewability**. A reviewer can read `Tx.hs` + `rules.yaml` + `expected.txt` side by side and recover the 044 story narrative without running anything.
- **Order independence**. Fixtures are independent; the registry is a list of records and order is not load-bearing.
- **Read-only**. Nothing in the harness writes to its own directories at test time. All files are committed-source.

## Out of scope for this contract

- The format and contents of `Tx.hs`'s `tx` value beyond "structurally-correct `Tx ConwayEra` matching the 044 story" — fixtures may evolve internally without changing this contract.
- The semantic validity of `expected.ttl` against the kmaps ontology (axiom checks belong to `#49`).
- Production-fidelity of blueprint files (the harness ships minimal blueprints; `#50` validates).

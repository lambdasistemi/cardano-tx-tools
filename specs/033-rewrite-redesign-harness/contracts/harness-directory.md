# Contract — `test/fixtures/rewrite-redesign/` filesystem layout

**Phase**: 1 (Design & Contracts).
**Owner**: this PR.
**Consumers**: `#47` (emitter), `#50` (blueprint decode), `#51` (cli-tree view), and any future engine PR reviewer.

## Directory layout

```text
test/fixtures/rewrite-redesign/
├── Helpers.hs                                       # Fixtures.RewriteRedesign.Helpers
├── blueprints/
│   ├── swap-v2-datum.cip57.json                     # consumed by 01-amaru-treasury-swap
│   └── mpfs-fact.cip57.json                         # consumed by 09-mpfs-facts-request
├── 01-amaru-treasury-swap/
│   ├── Tx.hs                                        # exports `tx`, `shape`
│   ├── rules.yaml
│   ├── expected.txt                                 # vocab-independent (A-side)
│   └── expected.ttl                                 # vocab-pinned (B-side, post-signal)
├── 02-alice-bob-ada/
│   └── (same four files)
├── 03-multi-asset-transfer/
│   └── (same four files)
├── 04-mint-spend-script-overlap/
│   └── (same four files)
├── 05-withdrawal-script-stake/
│   └── (same four files)
├── 06-stake-pool-delegation/
│   └── (same four files)
├── 07-vote-delegation/
│   └── (same four files)
├── 08-contingency-disburse/
│   └── (same four files)
├── 09-mpfs-facts-request/
│   └── (same four files)
└── 10-governance-treasury-withdrawal/
    └── (same four files)
```

Ten fixture directories, named `<NN>-<kebab-slug>`. The two-digit `NN` prefix matches the 044 story number.

## Per-file contracts

### `Tx.hs`

- Haskell module named `Fixtures.RewriteRedesign.S<NN>_<CamelCaseSlug>`.
- Exports at least two top-level bindings:
  - `tx :: Tx ConwayEra` — the fixture's transaction value.
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

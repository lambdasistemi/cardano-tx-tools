# Data Model — fixture / registry shapes

**Phase**: 1 (Design & Contracts).
**Date**: 2026-05-19

The harness has no runtime data store. The "data model" here is the in-process shape of fixture metadata that the goldens-spec iterates over, plus the on-disk filesystem contract under `test/fixtures/rewrite-redesign/`.

## Filesystem layout

Two sibling subtrees live under `test/fixtures/rewrite-redesign/`:

1. A **Haskell module subtree** under `Fixtures/RewriteRedesign/`, whose path matches each module name 1:1 (GHC requires this — module `Fixtures.RewriteRedesign.Helpers` MUST live at `<hs-source-dir>/Fixtures/RewriteRedesign/Helpers.hs`, and a per-fixture module name such as `Fixtures.RewriteRedesign.S02_AliceBobAda` cannot resolve from a Haskell-illegal directory name like `02-alice-bob-ada`).
2. A **per-fixture data-file subtree** under reviewer-friendly `<NN>-<kebab-slug>/` directories, holding the non-Haskell artifacts (`rules.yaml`, `expected.txt`, `expected.ttl`). The two subtrees are linked by the fixture's `StoryId`: the `StoryId` is the kebab directory name (e.g. `"02-alice-bob-ada"`); the corresponding builder lives in `Fixtures.RewriteRedesign.S<NN>_<CamelCaseSlug>` (e.g. `S02_AliceBobAda`).

```text
test/fixtures/rewrite-redesign/
├── Fixtures/                                                  # Haskell module subtree
│   └── RewriteRedesign/
│       ├── Helpers.hs                                         # Fixtures.RewriteRedesign.Helpers (S2)
│       ├── S01_AmaruTreasurySwap.hs                           # Fixtures.RewriteRedesign.S01_AmaruTreasurySwap
│       ├── S02_AliceBobAda.hs                                 # Fixtures.RewriteRedesign.S02_AliceBobAda
│       ├── S03_MultiAssetTransfer.hs
│       ├── S04_MintSpendScriptOverlap.hs
│       ├── S05_WithdrawalScriptStake.hs
│       ├── S06_StakePoolDelegation.hs
│       ├── S07_VoteDelegation.hs
│       ├── S08_ContingencyDisburse.hs
│       ├── S09_MpfsFactsRequest.hs
│       └── S10_GovernanceTreasuryWithdrawal.hs
├── blueprints/                                                # data files (CIP-57 JSON)
│   ├── swap-v2-datum.cip57.json                               # consumed by 01-amaru-treasury-swap
│   └── mpfs-fact.cip57.json                                   # consumed by 09-mpfs-facts-request
└── <NN>-<kebab-slug>/                                         # one data-file directory per fixture
    ├── rules.yaml                                             # A-side
    ├── expected.txt                                           # A-side (vocab-independent)
    └── expected.ttl                                           # B-side (post-kmaps#53 Phase A)
```

The `<NN>-<kebab-slug>` directory name matches the fixture's `StoryId`. The leading two-digit prefix preserves the 044 story order; the slug is unambiguous human-readable. The corresponding Haskell module's `S<NN>_<CamelCaseSlug>` name is mechanically derivable from the `StoryId` — strip the leading digits, replace hyphens with capitalised joins, prefix with `S<NN>_`. `mkFixturePaths` resolves the data-file paths from a `StoryId`; the per-fixture `Tx.hs` references that `StoryId` and `mkFixturePaths` to build its `FixturePaths` record.

Ten directories total, named:

1. `01-amaru-treasury-swap`
2. `02-alice-bob-ada`
3. `03-multi-asset-transfer`
4. `04-mint-spend-script-overlap`
5. `05-withdrawal-script-stake`
6. `06-stake-pool-delegation`
7. `07-vote-delegation`
8. `08-contingency-disburse`
9. `09-mpfs-facts-request`
10. `10-governance-treasury-withdrawal`

Fixtures 01 and 09 reference a blueprint under `blueprints/`; the other eight do not.

## Haskell types

### `StoryId`

```haskell
newtype StoryId = StoryId { unStoryId :: Text }
  deriving (Show, Eq, Ord)
```

Constructed from the directory slug (e.g. `StoryId "01-amaru-treasury-swap"`). Used as the `describe` label in Hspec and as the key in the fixture registry.

### `FixturePaths`

```haskell
data FixturePaths = FixturePaths
  { fpStoryId      :: StoryId
  , fpDirectory    :: FilePath          -- "test/fixtures/rewrite-redesign/<NN>-<slug>"
  , fpRulesYaml    :: FilePath          -- "<dir>/rules.yaml"
  , fpExpectedTxt  :: FilePath          -- "<dir>/expected.txt"
  , fpExpectedTtl  :: FilePath          -- "<dir>/expected.ttl" (may be absent pre-signal)
  , fpBlueprint    :: Maybe FilePath    -- "blueprints/<file>" if the fixture references one
  }
  deriving (Show)
```

Pure record; constructed once per fixture by the registry's smart constructor.

### `FixtureEntry`

```haskell
data FixtureEntry = FixtureEntry
  { feStoryId :: StoryId
  , feBuilder :: ConwayTx                       -- the `tx` export of the fixture module
  , fePaths   :: FixturePaths
  , feShape   :: ExpectedShape                      -- structural shape contract
  }
```

`feBuilder` is the result of evaluating `Fixtures.RewriteRedesign.S<NN>_<…>.tx`. It is built once when the spec module loads; the structural-shape `it` block asserts properties on this value.

`feShape` captures the body-field counts the 044 story specifies, used by the active structural Hspec item:

```haskell
data ExpectedShape = ExpectedShape
  { esInputs         :: Int
  , esOutputs        :: Int
  , esCertificates   :: Int
  , esWithdrawals    :: Int
  , esProposals      :: Int
  , esCollateral     :: Int
  , esReferenceIns   :: Int
  , esMintEntries    :: Int                          -- distinct (policy, name) entries in the mint field
  , esScriptWits     :: [ScriptHashTag]              -- tags of scripts expected in witness set
  , esBlueprintRef   :: Maybe BlueprintRef           -- "this script's datum decodes via <blueprint>"
  }
```

Values for `ExpectedShape` are extracted directly from each 044 story's "What's in the tx" prose and hand-encoded in the fixture's `Tx.hs` module:

```haskell
module Fixtures.RewriteRedesign.S02_AliceBobAda (storyId, tx, shape) where

import Cardano.Tx.Ledger (ConwayTx)
import Fixtures.RewriteRedesign.Helpers

storyId :: StoryId
storyId = StoryId "02-alice-bob-ada"

tx :: ConwayTx
tx = mkTx defTxBuilder
  { txInputs   = [alice `at` 0 `withResolved` (alice, 100 `ada`)]
  , txOutputs  = [bob `to` (10 `ada`), alice `to` (89_825_000 `lovelace`)]
  , txFee      = 175_000
  }

shape :: ExpectedShape
shape = baseShape { esInputs = 1, esOutputs = 2 }
```

(The `at` / `withResolved` / `to` / `ada` smart constructors are illustrative; each is added to `Fixtures.RewriteRedesign.Helpers` by the first fixture slice that needs it, riding in the same bisect-safe commit as the fixture per the per-fixture growth model from S2.)

### `FixtureRegistry`

```haskell
fixtureRegistry :: [FixtureEntry]
```

A single top-level list inside `RewriteRedesignGoldenSpec`. The goldens spec iterates this list and produces three Hspec items per entry:

```haskell
spec :: Spec
spec = describe "RewriteRedesignGoldens" $
  forM_ fixtureRegistry $ \FixtureEntry{..} ->
    describe (Text.unpack (unStoryId feStoryId)) $ do
      it "produces a ConwayTx of expected shape" $
        assertShape feBuilder feShape
      it "Turtle byte-equivalence with the future emitter (#47)" $
        pendingWith "awaits #47 emitter MVP"
      it "Text byte-equivalence via cli-tree SPARQL view (#51)" $
        pendingWith "awaits #51 cli-tree SPARQL view"
```

Adding a fixture is appending one record to `fixtureRegistry`. No per-fixture Hspec wiring.

## File-content contracts

### `rules.yaml`

Verbatim copy of the YAML inside the corresponding 044 user story's `Rules YAML` code-block. UTF-8, no BOM, LF line endings. Parsed at test time via `parseRewriteRulesYaml`; structural check asserts parse success.

### `expected.txt`

Verbatim copy of the corresponding 044 user story's `Expected rendered output` code-block, with the whitespace canon applied:

- Trailing whitespace stripped per line.
- Exactly one final newline (single `\n` terminating the file).
- No tab characters (replace with spaces where 044 used tabs, which it does not).
- No BOM.

The harness ships `expected.txt` ahead of the kmaps#53 Phase A signal. The static byte-equal check between `expected.txt` and the future `cli-tree` SPARQL projection is added in #51's work, not here.

### `expected.ttl`

Hand-authored Turtle that the future emitter (#47) is contracted to produce for the corresponding fixture + `rules.yaml` pair. Authored AFTER the kmaps#53 Phase A signal arrives. Constraints:

- Uses only `cardano:` prefix URIs that kmaps#53 Phase A published.
- May use additional prefix declarations (`tx:`, the operator's own `:` for entities) that are local to the file.
- Well-formed Turtle (parses via the harness's internal Turtle shim — see D5 in `research.md`).
- Contains, for each fixture:
  - one `cardano:Transaction` node with all body-field properties the 044 story names,
  - typed-leaf `cardano:Identifier` nodes for every credential / script-hash / pool-id / drep-cred / policy / asset-class the projection touches,
  - the operator's `cardano:Entity` declarations from `rules.yaml`, transparently compiled to Turtle,
  - (for stories 1 and 9) blueprint-decoded datum triples (`_:datum cardano:swapRecipient _:cred`-style; exact property names pinned to whatever kmaps#53 publishes).
- No `owl:sameAs` deductions. The deductions are the reasoner's responsibility (#49); the `expected.ttl` is the **un-inferred** base graph the emitter ships.

### Blueprint files (`blueprints/*.cip57.json`)

CIP-57-shaped JSON, hand-authored to the minimum surface needed by the corresponding fixture:

- `swap-v2-datum.cip57.json` exposes a `SwapOrder` constructor with a `recipient: Credential` field.
- `mpfs-fact.cip57.json` exposes a `Fact` constructor with a `requester: PubKeyHash` field.

Each file is a few-dozen-line JSON document. Schema validation is out of scope for the harness; the engine (`#50`) consumes them and decides whether the structure is sufficient for its decoder.

## Cabal wiring

```cabal
test-suite unit-tests
  ...
  hs-source-dirs:   test test/fixtures/rewrite-redesign
  other-modules:
    ...
    Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec
    Fixtures.RewriteRedesign.Helpers
    Fixtures.RewriteRedesign.S01_AmaruTreasurySwap
    Fixtures.RewriteRedesign.S02_AliceBobAda
    Fixtures.RewriteRedesign.S03_MultiAssetTransfer
    Fixtures.RewriteRedesign.S04_MintSpendScriptOverlap
    Fixtures.RewriteRedesign.S05_WithdrawalScriptStake
    Fixtures.RewriteRedesign.S06_StakePoolDelegation
    Fixtures.RewriteRedesign.S07_VoteDelegation
    Fixtures.RewriteRedesign.S08_ContingencyDisburse
    Fixtures.RewriteRedesign.S09_MpfsFactsRequest
    Fixtures.RewriteRedesign.S10_GovernanceTreasuryWithdrawal
```

`hs-source-dirs` adds the fixtures directory so cabal can resolve `Fixtures.RewriteRedesign.*` modules. The `unit-tests` build-depends stays unchanged in slice S1; if a Turtle shim or extra ledger module is needed for a later slice, the build-depends grows then.

## Test-suite invocation

```bash
nix develop --quiet -c just unit
```

Hspec output excerpt (target shape, post-S1):

```text
Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec
  RewriteRedesignGoldens
    02-alice-bob-ada
      produces a ConwayTx of expected shape
      Turtle byte-equivalence with the future emitter (#47) # PENDING: awaits #47 emitter MVP
      Text byte-equivalence via cli-tree SPARQL view (#51)  # PENDING: awaits #51 cli-tree SPARQL view
    ...
```

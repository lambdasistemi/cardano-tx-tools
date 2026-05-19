# Contract — `Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec`

**Phase**: 1 (Design & Contracts).
**Owner**: this PR.
**Consumers**: `#47` (emitter), `#51` (cli-tree view), and any future test author adding a new fixture.

## Module location

```text
test/Cardano/Tx/Rewrite/RewriteRedesignGoldenSpec.hs
```

Wired into the existing `unit-tests` test-suite via `test/unit-main.hs`:

```haskell
import Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec qualified as RewriteRedesignGoldenSpec

main :: IO ()
main = hspec $ do
    ...
    RewriteRedesignGoldenSpec.spec
    ...
```

## Public surface

```haskell
module Cardano.Tx.Rewrite.RewriteRedesignGoldenSpec (spec) where

spec :: Spec
```

The spec module exports exactly one function, `spec`. The fixture registry is internal.

## Behavioural contract

`spec` emits exactly two kinds of `describe` block:

1. **One foundational block** at the top level (`describe "blueprints"`) — present from slice S3 onward, independent of `fixtureRegistry`. Asserts that the two CIP-57 blueprint files under `test/fixtures/rewrite-redesign/blueprints/` exist on disk and parse as JSON. One active item, never pending. This block is outside the per-fixture iteration.

2. **One per-fixture block** per entry in `fixtureRegistry`, with **exactly three Hspec items per fixture**: one active structural-shape item and two pending items. The active-item count per fixture stays at one across both A-side and B-side; the B-side does NOT add a fourth active item — instead, the structural item grows to include a Turtle-parse sub-check once `expected.ttl` is present on disk.

```haskell
spec :: Spec
spec = do
  blueprintsDescribe                                       -- foundational, S3+
  describe "RewriteRedesignGoldens" $
    forM_ fixtureRegistry $ \fe ->
      describe (Text.unpack (unStoryId (feStoryId fe))) $ do
        it "produces a Tx ConwayEra of expected shape" $
          assertShape (feBuilder fe) (feShape fe) (fePaths fe)
        it "Turtle byte-equivalence with the future emitter (#47)" $
          pendingWith "awaits #47 emitter MVP"
        it "Text byte-equivalence via cli-tree SPARQL view (#51)" $
          pendingWith "awaits #51 cli-tree SPARQL view"
```

Total active surface = 1 (blueprints) + 1 per fixture (structural). With ten fixtures registered: 11 active items + 20 pending items.

### Active item — "produces a Tx ConwayEra of expected shape"

- Constructs the fixture's transaction by forcing `feBuilder`.
- Calls `assertShape :: Tx ConwayEra -> ExpectedShape -> FixturePaths -> Expectation`.
- `assertShape` checks at minimum:
  - era is `ConwayEra` (statically guaranteed by `Tx ConwayEra` typing — the check is a documentation pass),
  - number of inputs equals `esInputs`,
  - number of outputs equals `esOutputs`,
  - number of certificates equals `esCertificates`,
  - withdrawals map size equals `esWithdrawals`,
  - proposal procedure count equals `esProposals`,
  - collateral input count equals `esCollateral`,
  - reference input count equals `esReferenceIns`,
  - mint map entry count equals `esMintEntries`,
  - witness-set script tags include every `ScriptHashTag` listed in `esScriptWits`,
  - if `esBlueprintRef` is `Just`, the referenced blueprint file exists on disk,
  - `fpRulesYaml` exists and parses successfully via `parseRewriteRulesYaml`,
  - `fpExpectedTxt` exists and is non-empty,
  - **if `fpExpectedTtl` exists on disk** (post-B-side): parses as well-formed Turtle via the internal shim and every URI in the `cardano:` namespace resolves under the kmaps#53 Phase A prefix. **If `fpExpectedTtl` is absent** (pre-B-side): this sub-check is skipped, not failed.

The Turtle-parse clause is conditional on the file's presence so the A-side and B-side both leave `./gate.sh` green at HEAD. Failure of any active clause is an Hspec assertion failure.

### Foundational block — "blueprints"

- Lives at `describe "blueprints" $ ...` at the top of `spec`, outside `fixtureRegistry`.
- Two active items: `swap-v2-datum.cip57.json` exists + parses as JSON; `mpfs-fact.cip57.json` exists + parses as JSON.
- Landed in slice S3. Stays for the life of the harness.

### Pending item — "Turtle byte-equivalence with the future emitter (#47)"

- Reports `pendingWith "awaits #47 emitter MVP"`.
- When `#47` lands, replaced by a real assertion using `Emitter.emitTurtle` and `BS.readFile (fpExpectedTtl …)`.

### Pending item — "Text byte-equivalence via cli-tree SPARQL view (#51)"

- Reports `pendingWith "awaits #51 cli-tree SPARQL view"`.
- When `#51` lands, replaced by a real assertion that projects `expected.ttl` through `views/cli-tree.rq` and compares to `expected.txt`.

## Adding a fixture (post-S1)

1. Add `Fixtures.RewriteRedesign.S<NN>_<…>` to the cabal `unit-tests` `other-modules`.
2. Write the fixture module exporting `tx :: Tx ConwayEra` and `shape :: ExpectedShape`.
3. Append one `FixtureEntry { … }` record to `fixtureRegistry` in `RewriteRedesignGoldenSpec`.

No other Hspec wiring is required.

## Flipping a pending item to active

The flip is one-line-per-item (or one-call-per-item to a shared helper). Example for the Turtle item:

```haskell
-- before
it "Turtle byte-equivalence with the future emitter (#47)" $
  pendingWith "awaits #47 emitter MVP"

-- after
it "Turtle byte-equivalence with the future emitter (#47)" $
  assertTurtleByteEqual fe
  where
    assertTurtleByteEqual FixtureEntry{..} = do
      graph <- Emitter.emitTurtle feBuilder =<< loadRules (fpRulesYaml fePaths)
      expected <- BS.readFile (fpExpectedTtl fePaths)
      graph `shouldBe` expected
```

Per SC-008 / SC-009, this change requires no fixture file rework.

## Invariants

- **No emitter at import time**. The spec module compiles and runs without `Cardano.Tx.Rewrite.Emit` (or any future `#47` module) being present. Pending items are unconditional `pendingWith` calls.
- **No SPARQL runtime at import time**. Likewise — no dependency on a SPARQL engine or view loader.
- **`pendingWith` messages name the upstream ticket**. Future grep-by-message works.
- **Registry order = directory NN order**. The 044 story numbers are 1..10; the registry is presented in that order so the Hspec output is predictable.
- **`gate.sh` exit code 0** on every commit of this PR, even when every Turtle / text item is pending.
- **Per-fixture active-item count = 1** across both A-side and B-side. The B-side grows the existing structural item's checks rather than adding a fourth Hspec item. The foundational `blueprints` block (from S3) is outside the per-fixture iteration and adds 2 active items at the suite level — not per-fixture.

## Out of scope for this contract

- The internal shape of `assertShape`'s checks (callers see pass/fail; the per-field implementation may evolve).
- The choice of Turtle parser shim (a research decision; see `research.md` D5).
- The set of YAML keys `parseRewriteRulesYaml` accepts (the conditional S4 slice may extend it; that contract is in `Cardano.Tx.Rewrite`'s public API, not here).

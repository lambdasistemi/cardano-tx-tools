# Quickstart — using the harness

**Audience**: an engine implementer (#47, #50, #51) or a design reviewer of any engine PR.
**Last updated**: 2026-05-19

## Running the harness today

```bash
cd /path/to/cardano-tx-tools-issue-45
nix develop --quiet -c just unit -- --match "RewriteRedesignGoldens"
```

What you see depends on which slices have landed.

After slice S1 (scaffold) only:

```text
RewriteRedesignGoldens
  (no fixtures registered yet)

Finished in 0.00 seconds
0 examples, 0 failures
```

After at least one fixture slice (e.g. S5 = `02-alice-bob-ada`):

```text
RewriteRedesignGoldens
  02-alice-bob-ada
    produces a Tx ConwayEra of expected shape
    Turtle byte-equivalence with the future emitter (#47) [PENDING: awaits #47 emitter MVP]
    Text byte-equivalence via cli-tree SPARQL view (#51)  [PENDING: awaits #51 cli-tree SPARQL view]

Finished in 0.05 seconds
3 examples, 0 failures, 2 pending
```

After every A-side fixture has landed (S5..S14):

```text
RewriteRedesignGoldens
  01-amaru-treasury-swap         (1 passed, 2 pending)
  02-alice-bob-ada               (1 passed, 2 pending)
  03-multi-asset-transfer        (1 passed, 2 pending)
  ...
  10-governance-treasury-withdrawal (1 passed, 2 pending)

Finished in 0.50 seconds
30 examples, 0 failures, 20 pending
```

## Inspecting a single fixture

```bash
ls test/fixtures/rewrite-redesign/02-alice-bob-ada/
# Tx.hs  rules.yaml  expected.txt  (expected.ttl after kmaps#53 Phase A signal)

cat test/fixtures/rewrite-redesign/02-alice-bob-ada/Tx.hs
```

`Tx.hs` is a single small Haskell module producing the fixture's `Tx ConwayEra` value via `mkTx { ... }` record-style. No imperative builder chains. The fixture's `rules.yaml` is the operator's rule set verbatim from the 044 spec. The `expected.txt` is the rendered output the 044 spec promises; the `expected.ttl` (post-signal) is the Turtle graph the future emitter must produce.

## Flipping a pending item to active — the engine implementer's task

When `#47` emitter MVP lands, every fixture's "Turtle byte-equivalence" item changes from one pending line to one active assertion. The change is mechanical:

```haskell
-- before (today):
it "Turtle byte-equivalence with the future emitter (#47)" $
  pendingWith "awaits #47 emitter MVP"

-- after (#47 has shipped):
it "Turtle byte-equivalence with the future emitter (#47)" $ do
  graph <- Emitter.emitTurtle (feBuilder fe) (loadRules (fpRulesYaml (fePaths fe)))
  expected <- BS.readFile (fpExpectedTtl (fePaths fe))
  graph `shouldBe` expected
```

The same one-line-per-fixture change works for every fixture because the registry is iterated and the pending message is the only fixture-specific surface; one shared helper (`assertTurtleByteEqual`) is enough.

When `#51` cli-tree SPARQL view lands, the same shape applies to the "Text byte-equivalence" item.

## Adding a new fixture

Only useful if a new 044-style story is added. The 044 spec freezes ten stories; this section documents the pattern in case follow-up tickets add an eleventh.

1. Create a new directory `test/fixtures/rewrite-redesign/<NN>-<slug>/`.
2. Write `Tx.hs` exporting `tx :: Tx ConwayEra` and `shape :: ExpectedShape`. Use `Fixtures.RewriteRedesign.Helpers` for `mkTx`, addresses, and smart constructors.
3. Drop `rules.yaml` verbatim from the new story.
4. Drop `expected.txt` (whitespace-canonicalised) from the new story's expected output.
5. If the story needs a blueprint, drop the CIP-57 JSON into `blueprints/`.
6. Append the fixture to the cabal `unit-tests` `other-modules` list.
7. Append one `FixtureEntry` to `fixtureRegistry` in `RewriteRedesignGoldenSpec`.
8. Run `./gate.sh`. The new fixture's structural item runs actively; the Turtle and text items show as pending until upstreams ship.
9. (Post-signal) Drop `expected.ttl` once the new story's vocab is published by kmaps#53.

## What this harness does NOT do

- It does **not** run an emitter. The emitter is `#47`; until it ships, the Turtle byte-equivalence item is pending.
- It does **not** run a SPARQL view. The cli-tree view is `#51`; until it ships, the text byte-equivalence item is pending.
- It does **not** ship a JSON Schema validator for blueprints. That belongs to `#50`.
- It does **not** validate `expected.ttl` against the kmaps `cardano:` ontology beyond well-formedness and prefix usage. Semantic validation against axioms is `#49`'s job (reasoner).
- It does **not** assert anything about transaction admissibility on chain (min-UTxO, balance, witness coverage, fee bounds). Fixtures are illustrative — structurally-correct, not necessarily ledger-valid.
- It does **not** mutate `Cardano.Tx.InspectSpec` or any existing 032/014/015 test suite. The harness is purely additive.

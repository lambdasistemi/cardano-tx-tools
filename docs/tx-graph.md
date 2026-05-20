# tx-graph

Emit a Conway transaction as RDF — the operator-entity overlay
(from a rules file in Turtle or YAML sugar), the transaction body
(inputs, outputs, addresses with payment + stake credentials, fee,
mint, withdrawal, certificates, collateral, proposals), and their
cross-references — in one canonical Turtle or JSON-LD graph.

```text
Usage: tx-graph (--rules FILE | --tx FILE [--utxo FILE]) [--out FILE]
                [--format turtle|json-ld]

  --rules FILE          Operator-authored rules file (.ttl / .yaml / .yml)
  --tx FILE             Conway transaction CBOR
  --utxo FILE           Resolved-UTxO JSON (same shape consumed by
                        Cardano.Tx.Diff.Resolver)
  --out FILE            Output path (defaults to stdout)
  --format FORMAT       turtle | json-ld (defaults to turtle)
```

## Three modes by flag presence

| `--rules` | `--tx` | `--utxo` | Behaviour |
|-----------|--------|----------|-----------|
| present | absent  | absent  | **Overlay only** — emits the operator-entity overlay (`cardano:Entity` + `cardano:Identifier` blocks for every entity in the rules file). The deterministic blank-node naming scheme is documented under [rewriting-rules grammar](rewriting-rules.md) (entity slugs as IRI local parts; `_:<slug>_<roleSuffix>` per identifier). |
| present | present | present | **Joint graph** — emits the overlay followed by the transaction body. Body credentials cross-reference the overlay's identifier blank nodes when an entity covers the credential's `(LeafType, bytesHex)` pair; otherwise a raw-bytes naming fallback applies. |
| absent  | present | optional | **Body only** — emits the transaction body with raw-bytes naming for every credential (no entity-named bnodes). Useful for ad-hoc inspection without authoring rules. |

## Examples

Emit the operator-entity overlay from a rules file:

```bash
tx-graph --rules rules/amaru-treasury.yaml
```

Emit the joint graph for a built unsigned tx:

```bash
tx-graph \
  --tx tx.cbor \
  --utxo resolved.json \
  --rules rules/amaru-treasury.yaml \
  --out graph.ttl
```

Same input, JSON-LD output:

```bash
tx-graph \
  --tx tx.cbor \
  --utxo resolved.json \
  --rules rules/amaru-treasury.yaml \
  --format json-ld \
  --out graph.jsonld
```

## Output shape

The Turtle output is canonical (byte-stable) and structured as:

1. **Prefix declarations** — `cardano:`, `rdfs:`, fixture-local `:`.
2. **Operator-entity overlay** — verbatim from the rules loader
   (`Cardano.Tx.Graph.Rules.Load`), one `cardano:Entity` block per
   declared entity plus one `cardano:Identifier` block per
   `(leafType, bytesHex)` pair.
3. **Transaction body** — `_:tx a cardano:Transaction ; ...`,
   followed by per-cluster blocks for inputs, outputs, mints,
   withdrawals, certs, collateral inputs, and proposals.
4. **Address decompositions** — one block per unique address,
   linking the address to its payment and stake credentials, and
   each credential to the corresponding identifier blank node
   (entity-named or raw-bytes-named).

The JSON-LD output is the same triple set serialized as a single
JSON document with `@context` (the three prefixes) and `@graph` (a
flat array of subject-grouped objects). `--format turtle` and
`--format json-ld` produce set-equivalent triple sets; Turtle is
the byte-diff anchor in the test harness.

## Library entry point

```haskell
import Cardano.Tx.Graph.Emit
import Cardano.Tx.Graph.Rules.Load (loadRulesFile, RulesLoadResult (..))

emitJoint :: FilePath -> ConwayTx -> ResolvedUTxO -> IO ByteString
emitJoint rulesPath tx utxo = do
    Right result <- loadRulesFile rulesPath
    let Right graph = emit tx utxo (rulesEntities result)
    pure (serialize Turtle graph)
```

Both `emit` and `serialize` are pure; the only IO happens at the
rules-loading boundary (which the CLI handles for operators).

## See also

- [rewriting-rules grammar](rewriting-rules.md) — the YAML sugar
  and Turtle subset the rules loader consumes.
- [tx-inspect](tx-inspect.md) — collapse + rename pipeline for the
  same Conway transactions, rendered as a structured human report.

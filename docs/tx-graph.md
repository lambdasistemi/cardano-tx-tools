# tx-graph

Emit a Conway transaction as RDF — the operator-entity overlay
(from a rules file in Turtle or YAML sugar), the transaction body
(inputs, outputs, addresses with payment + stake credentials, fee,
mint, withdrawal, certificates, collateral, proposals), and their
cross-references — in one canonical Turtle or JSON-LD graph.

```text
Usage: tx-graph [--rules FILE] [--tx PATH | -]
                [--utxo FILE | --n2c-socket-path SOCKET]
                [--network-magic WORD32]
                [--out FILE] [--format turtle|json-ld]

  --rules FILE              Operator-authored rules file (.ttl / .yaml /
                            .yml). Overlay-only mode when used alone.
  --tx PATH | -             Conway tx CBOR (hex envelope, raw hex, or
                            binary). '-' reads from stdin. Triggers the
                            body-emitting dispatcher.
  --utxo FILE               Pre-resolved UTxO JSON for the tx's inputs.
                            Mutually exclusive with --n2c-socket-path.
  --n2c-socket-path SOCKET  Local cardano-node Node-to-Client socket.
                            Resolves the tx's inputs live against the
                            node (requires --network-magic).
  --network-magic WORD32    Network magic for the --n2c-socket-path
                            session (default: mainnet, 764824073).
  --out FILE                Output path (defaults to stdout).
  --format turtle|json-ld   Output format (defaults to turtle).
```

## Three modes by flag presence

| `--rules` | `--tx` | UTxO source | Behaviour |
|-----------|--------|-------------|-----------|
| present | absent  | n/a | **Overlay only** — emits the operator-entity overlay (`cardano:Entity` + `cardano:Identifier` blocks for every entity in the rules file). The deterministic blank-node naming scheme is documented under [rewriting-rules grammar](rewriting-rules.md) (entity slugs as IRI local parts; `_:<slug>_<roleSuffix>` per identifier). |
| present | present | `--utxo` or `--n2c-socket-path` (optional) | **Joint graph** — emits the overlay followed by the transaction body. Body credentials cross-reference the overlay's identifier blank nodes when an entity covers the credential's `(LeafType, bytesHex)` pair; otherwise a raw-bytes naming fallback applies. |
| absent  | present | `--utxo` or `--n2c-socket-path` (optional) | **Body only** — emits the transaction body with raw-bytes naming for every credential (no entity-named bnodes). Useful for ad-hoc inspection without authoring rules. |

`--utxo` and `--n2c-socket-path` are mutually exclusive; passing
both exits non-zero with a one-line stderr message. With neither,
the UTxO map is empty, which is enough for leaves that key off
the body alone.

## Examples

Emit the operator-entity overlay from a rules file:

```bash
tx-graph --rules rules/amaru-treasury.yaml
```

Emit the joint graph for a built unsigned tx, with the UTxO
pre-resolved to JSON on disk:

```bash
tx-graph \
  --tx tx.cbor \
  --utxo resolved.json \
  --rules rules/amaru-treasury.yaml \
  --out graph.ttl
```

Same shape, but read the tx CBOR from stdin and resolve the
UTxO live against a local `cardano-node` over Node-to-Client
(same seam `tx-inspect` and `tx-validate` use):

```bash
cat tx.cbor | tx-graph \
  --tx - \
  --n2c-socket-path "$CARDANO_NODE_SOCKET_PATH" \
  --network-magic 764824073 \
  --rules rules/amaru-treasury.yaml \
  --out graph.ttl
```

JSON-LD output of the same input:

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
rules-loading boundary (which the CLI handles for operators) and,
when `--n2c-socket-path` is supplied, the Node-to-Client session
that resolves the tx's inputs.

## See also

- [rewriting-rules grammar](rewriting-rules.md) — the YAML sugar
  and Turtle subset the rules loader consumes.
- [tx-inspect](tx-inspect.md) — collapse + rename pipeline for the
  same Conway transactions, rendered as a structured human report.

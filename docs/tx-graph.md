# tx-graph

Emit a Conway transaction as RDF — the operator-entity overlay
(from a rules file in Turtle or YAML sugar), the transaction body
(inputs, outputs, addresses with payment + stake credentials, fee,
mint, withdrawal, certificates, collateral, proposals), and their
cross-references — in one canonical Turtle or JSON-LD graph. When
the rules file registers a CIP-57 blueprint for a script, Plutus
datum and redeemer fields are decoded into typed fixture-local
predicates; decode failures keep the raw bytes and add a
`cardano:decodeError` literal.

```text
tx-graph — operator-entity overlay + body emitter

Usage: tx-graph [--rules FILE] [--tx PATH | -] [--utxo FILE]
                [--n2c-socket-path SOCKET] [--network-magic WORD32] [--out FILE]
                [--format FORMAT]

  tx-graph — operator-entity overlay + body emitter. Loads operator-authored
  rules (overlay-only mode) or drives the joint-graph body emitter on a Conway
  tx + resolved UTxO. Output format defaults to Turtle.

Available options:
  --rules FILE             Operator-authored rules file (.yaml/.yml or .ttl).
                           Overlay-only mode when used alone.
  --tx PATH | -            Conway tx CBOR (hex text envelope, raw hex, or
                           binary). '-' reads from stdin. Triggers the
                           body-emitting dispatcher.
  --utxo FILE              Resolved-UTxO JSON for the tx's inputs. Mutually
                           exclusive with --n2c-socket-path.
  --n2c-socket-path SOCKET Local cardano-node Node-to-Client socket. When
                           supplied, the tx's inputs are resolved live against
                           the node (requires --network-magic).
  --network-magic WORD32   Network magic for the --n2c-socket-path session.
                           Defaults to mainnet. (default: 764824073)
  --out FILE               Output destination (default: stdout).
  --format FORMAT          Output format: 'turtle' or 'json-ld'.
                           (default: "turtle")
  -h,--help                Show this help text
```

```asciinema-player
{
  "file": "assets/asciinema/tx-graph.cast",
  "idle_time_limit": 2,
  "theme": "monokai",
  "poster": "npt:0:3"
}
```

The cast above uses fixture `11-amaru-treasury-swap-real` and the
mainnet `5fc04113...` CBOR it mirrors. It shows **overlay-only**
rules, then **joint graph** emission with real fee, lovelace
amounts, inline datums, withdrawals, collateral return, redeemers,
execution units, key witnesses, and address decompositions. The
last frames show the CIP-57 path added by issue #50: blueprint
decoded datums mint typed predicates such as `:SwapOrder_recipient`,
while decode failures preserve `cardano:hasRawBytes` and add
`cardano:decodeError`.

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

Decode an inline datum against the blueprint registered by the
rules file. The predicate names come from the blueprint constructor
and field titles, and use the fixture-local `:` namespace rather
than the canonical `cardano:` vocabulary:

```bash
tx-graph \
  --tx swap-order.cbor.hex \
  --rules rules/swap-v2.yaml
```

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_c9bc91a9f2f9d50c ;
  :SwapOrder_recipient _:outputDatum1_recipient .

_:outputDatum1_recipient :_0_pubKeyHash _:outputDatum1_recipient_pubKeyHash .

_:outputDatum1_recipient_pubKeyHash a cardano:Identifier ;
  cardano:leafType "Bytes" ;
  cardano:bytesHex "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef" .
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
4. **Blueprint-decoded payloads** — datum and redeemer sub-blocks
   use `:<Constructor>_<field>` predicates when a registered CIP-57
   blueprint decodes the Plutus data; otherwise the graph keeps
   `cardano:hasRawBytes`, with `cardano:decodeError` on decode
   failure.
5. **Address decompositions** — one block per unique address,
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
    let Right graph =
            emit tx utxo (rulesEntities result) (rulesBlueprints result)
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

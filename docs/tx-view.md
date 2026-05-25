# tx-view

Project the canonical Turtle graph that [`tx-graph`](tx-graph.md)
emits through one of four packaged views — `cli-tree`,
`asset-flow`, `entity-occurrences`, `json-ld` — and write the
rendered byte stream to stdout or a file.

```text
tx-view — packaged-view dispatcher over canonical Turtle graphs

Usage: tx-view --graph FILE [--view NAME] [--out FILE]

  Loads a canonical Turtle graph file (the kind tx-graph emits) and projects it
  through a named packaged view, writing the rendered byte stream to stdout or
  to --out FILE.

Available options:
  --graph FILE             Canonical Turtle graph file (from tx-graph).
  --view NAME              Packaged view name (cli-tree, asset-flow,
                           entity-occurrences, json-ld).  (default: "cli-tree")
  --out FILE               Output destination (default: stdout).
  -h,--help                Show this help text
```

## The four packaged views

Each view ships as a paired contract:

| View | SPARQL contract | Haskell runtime | Output |
|------|-----------------|-----------------|--------|
| `cli-tree` | [`views/cli-tree.rq`](https://github.com/lambdasistemi/cardano-tx-tools/blob/main/views/cli-tree.rq) | `Cardano.Tx.View.CliTree` | Text tree of the tx body (inputs / reference inputs / outputs / withdrawals / collateral / fee). |
| `asset-flow` | [`views/asset-flow.rq`](https://github.com/lambdasistemi/cardano-tx-tools/blob/main/views/asset-flow.rq) | `Cardano.Tx.View.AssetFlow` | Tab-separated rows: `<asset>\t<quantity>\t<source>\t<destination>`. One row per value movement. |
| `entity-occurrences` | [`views/entity-occurrences.rq`](https://github.com/lambdasistemi/cardano-tx-tools/blob/main/views/entity-occurrences.rq) | `Cardano.Tx.View.EntityOccurrences` | Tab-separated rows: `<entity-label>\t<count>`. |
| `json-ld` | [`views/json-ld.rq`](https://github.com/lambdasistemi/cardano-tx-tools/blob/main/views/json-ld.rq) | `Cardano.Tx.View.JsonLd` | The full graph as a single JSON-LD document (`@context` + `@graph`). |

The `.rq` SPARQL files in `views/` are the vendor-neutral contracts;
the Haskell modules under `Cardano.Tx.View.*` are the in-process
implementations. No SPARQL runtime ships on the classpath — the
projection is hand-rolled in Haskell against the same triple
patterns the SPARQL would match. An external SPARQL CLI (Apache
Jena's `sparql`, `rasqal`'s `roqet`, etc.) can run the `.rq` files
against the same graph and produce equivalent output.

## Examples

### cli-tree on a real on-chain tx

Emit the graph with `tx-graph`, then project with `tx-view`:

```bash
nix build .#tx-graph .#tx-view

# Resolved-input lattice from Blockfrost or N2C makes the input side
# render with full address+coin attribution; without resolution the
# input rows show only txOutRefs.
./result/bin/tx-graph \
  --tx 18d57a4f.cbor \
  --rules amaru-treasury.yaml \
  --n2c-socket-path /run/cardano/socket \
  --network-magic 764824073 \
  > /tmp/tx.ttl

./result/bin/tx-view --graph /tmp/tx.ttl --view cli-tree
```

### asset-flow

```bash
./result/bin/tx-view --graph /tmp/tx.ttl --view asset-flow
```

```text
ada	3852000000000	<unknown>	amaru-treasury.contingency
ada	205000000000	<unknown>	amaru-treasury.network_compliance
ada	92141887	<unknown>	amaru.network-wallet
```

(`<unknown>` source rows mean the canonical graph doesn't carry
input UTxO resolution — supply `--utxo` / `--n2c-socket-path` on
`tx-graph` to fill those in.)

### entity-occurrences

```bash
./result/bin/tx-view --graph /tmp/tx.ttl --view entity-occurrences
```

```text
amaru-treasury.contingency	2
amaru-treasury.network_compliance	2
amaru.network-wallet	2
```

### json-ld

```bash
./result/bin/tx-view --graph /tmp/tx.ttl --view json-ld > /tmp/tx.jsonld
jq '.["@graph"] | length' /tmp/tx.jsonld
# 53
```

The JSON-LD output is set-equivalent to the Turtle the graph was
loaded from (no information loss). Useful as the input to a
JavaScript-style consumer or a generic SPARQL endpoint.

## Empty-result invariant

If the loaded graph has no `cardano:Transaction` subject the
projection emits an empty byte stream and the executable exits with
code 0. This is the FR-008 invariant in the spec — useful when
piping `tx-view` over a stream of arbitrary Turtle inputs, some of
which are pure-rules overlays.

## CLI-surface notes

- `--graph` is required.
- `--view` is optional; default is `cli-tree`.
- `--out` writes to the named file when supplied; otherwise stdout.
- Unknown `--view` names produce an explicit error on stderr and
  exit code 1 — the four-view set is closed.

## Library entry point

```haskell
import Cardano.Tx.View (ViewKind (..), renderView)
import qualified Data.ByteString as BS

renderTo :: FilePath -> ViewKind -> IO BS.ByteString
renderTo graphPath view = do
    bytes <- BS.readFile graphPath
    pure (renderView view bytes)
```

`renderView` is pure and runs against a pre-parsed canonical graph;
the parser is `Cardano.Tx.View.Turtle.parseGraph` (a narrow subset
of Turtle that matches what `tx-graph` emits).

## Running the SPARQL contract directly

The `.rq` files in `views/` are valid SPARQL 1.1 and can be run
against the same graph by any standards-compliant runtime. Apache
Jena's `sparql` is the most common path:

```bash
# Get jena available transiently:
nix-shell -p apache-jena --run \
  "sparql --data /tmp/tx.ttl --query views/asset-flow.rq"
```

The result is set-equivalent to `tx-view --view asset-flow` on the
same graph (modulo trivial whitespace differences in the renderers).

## See also

- [tx-graph](tx-graph.md) — emits the canonical Turtle graph that
  `tx-view` consumes.
- [rewriting-rules grammar](rewriting-rules.md) — operator
  rules.yaml language; controls the entity overlay that affects
  cli-tree's address resolution and asset-flow's source / destination
  columns.
- [tx-inspect](tx-inspect.md) — the parallel non-SPARQL render
  pipeline (verbatim → collapse → rename) for the same Conway
  transactions.

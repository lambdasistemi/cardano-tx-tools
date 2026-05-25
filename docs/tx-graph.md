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

### Per-section triple coverage

The body emitter walks every Conway-era body field that carries
semantic content. The triples below are emitted regardless of whether
operator rules are supplied; rules.yaml only changes how the bytes are
*labelled* (entity-named vs raw-bytes-named bnodes).

#### Transaction-level predicates

- `cardano:hasInput`, `cardano:hasReferenceInput`,
  `cardano:hasCollateralInput` — one edge per `TxIn` in the
  corresponding ledger field.
- `cardano:hasOutput`, `cardano:hasCollateralReturn` — one edge per
  body output. The collateral-return output is on the same predicate
  family but distinguishable by its anchor predicate (used by
  `tx-view --view cli-tree` to elide it from the spending-output
  list).
- `cardano:hasFee` — integer lovelace literal.
- `cardano:hasValidityInterval` — sub-block with
  `cardano:invalidBefore` / `cardano:invalidHereafter` integers when
  set.
- `cardano:hasWithdrawal` — one edge per `Withdrawal`.
- `cardano:hasMint` — one edge per minted asset class (positive or
  negative quantity).
- `cardano:hasCertificate` — one edge per `Certificate` (stake
  registration / delegation / pool registration / drep declaration
  / vote delegation / governance authorisation).
- `cardano:hasRequiredSigner` — one edge per required-signer
  identifier (PaymentKey leaf).
- `cardano:hasProposal`, `cardano:hasVote` — one edge each per
  governance proposal / vote.
- `cardano:hasRedeemer` — one edge per Plutus redeemer with its
  `cardano:hasPurpose`, `cardano:hasIndex`, `cardano:hasData`, and
  `cardano:hasExUnits` sub-blocks.
- `cardano:scriptDataHash`, `cardano:auxiliaryDataHash` — when set.
- `cardano:totalCollateral` — integer lovelace when set.
- `cardano:hasReferenceScript` (per output) — emitted on the
  output's body when the output carries an attached reference script.

#### Input triples

- `cardano:fromTxOutRef` → typed `cardano:TxOutRef` sub-block.
- `cardano:hasTxId` (on the `TxOutRef`) → `_:hash_txid_<full-hex>`
  bnode carrying `cardano:leafType "TxId"` + `cardano:bytesHex`.
- `cardano:hasIndex` (on the `TxOutRef`) — integer.
- `cardano:resolvedTo` → resolved-`cardano:Output` sub-block when
  the input's UTxO is supplied (`--utxo` or `--n2c-socket-path`).
  Carries the parent's address + value at the time of consumption.

#### Output triples

- `cardano:atAddress` → typed `cardano:Address` sub-block (see
  *Address decompositions* below).
- `cardano:lovelace` — integer.
- `cardano:hasAssetValue` → typed RDF list of `cardano:Asset`
  entries when the output carries native tokens.
- `cardano:hasDatum` → typed `cardano:Datum` sub-block when the
  output carries either an inline datum (with `cardano:hasRawBytes`
  and/or blueprint-decoded predicates) or a datum hash (with
  `cardano:hasHash`).
- `cardano:hasReferenceScript` → typed sub-block when the output
  has an attached reference script (inline or hash-only).

#### Asset / multi-asset triples

The `cardano:hasAssetValue` payload is an RDF list. Each entry is a
typed `cardano:Asset` block:

- `cardano:hasIdentifier` → `_:cred_assetclass_<full-hex>` bnode
  with the concatenated `policy-id ++ asset-name` bytes and
  `cardano:leafType "AssetClass"`.
- `cardano:quantity` — integer (positive on outputs, signed on
  `hasMint`).

#### Address decomposition

Each unique `(payment-cred, stake-ref)` pair emits one
`cardano:Address` block:

- `cardano:bech32` — full bech32 address literal.
- `cardano:hasPaymentCredential` → `<base>CredPayment` sub-block.
- `cardano:hasStakeCredential` → `<base>CredStake` sub-block (when
  the stake reference is non-null).

Each credential sub-block carries one
`cardano:hasIdentifier` edge to the underlying identifier bnode
(entity-named when `rules.yaml` covers the credential's
`(leafType, bytesHex)` pair, otherwise raw-bytes-named).

#### Blueprint-decoded datum / redeemer payloads

When the rules file registers a CIP-57 blueprint for the script
controlling the datum, the walker emits a typed-emit projection of
the Plutus data tree:

- Each constructor's titled fields become
  `:<ConstructorTitle>_<fieldTitle>` predicates rooted at the
  enclosing data subject.
- A constructor without a `title` falls back to a positional
  `:_<index>` predicate.
- **`"dataType": "map"` (CIP-57 SchemaMap)** — a Plutus `Map`
  payload renders as an RDF list of `cardano:Asset`-shaped
  `OpenObject {"key" -> k, "value" -> v}` entries; the walker
  materialises each entry as a positional `:_<i>` bnode with the
  decoded `:key` and `:value` triples on the entry.
- Plutus byte fields → `_:<scope>_<field>_<i>` bnodes with
  `cardano:bytesHex` literal and `cardano:leafType "Bytes"`.
- Plutus integer fields → integer literals directly on the
  enclosing predicate.
- Decode failure → `cardano:decodeError "<reason>"` literal on the
  enclosing data subject; raw bytes are preserved on
  `cardano:hasRawBytes`.

#### Bnode-label naming scheme

Bnode labels are file-local and only need to be unique inside the
Turtle document. The emitter mints them deterministically from the
underlying bytes so that the same identifier emitted from two
positions in a tx collapses to a single RDF node (intentional
deduplication for the operator overlay) while distinct identifiers
never collide on label:

- **Identifier leaves** (TxId, datum hash, script hash, payment /
  stake credentials, asset classes) →
  `_:<family>_<role>_<full-hex>` where:
  - `<family>` is `cred` for operator-declarable credential leaves
    (payment / stake key / script, asset class, policy, pool id,
    drep key / script) and `hash` for body-walker hash leaves (TxId,
    datum hash, script hash, scriptdata hash, auxiliarydata hash).
  - `<role>` is the leafType in lowercase (`paymentkey`,
    `paymentscript`, `stakekey`, `stakescript`, `assetclass`,
    `txid`, …).
  - `<full-hex>` is the lowercase base16 encoding of the bytes,
    *not* truncated. (Earlier emitter versions truncated to 16 hex
    chars; that was a bnode-collision hazard for stub or
    long-zero-prefix byte sets and is fixed in 0.2.3.0.)
- **Address-level bnodes** → `<base>Addr`, `<base>CredPayment`,
  `<base>CredStake` where `<base>` is the entity slug (when
  rules.yaml binds the payment credential) or the raw-bytes form,
  *concatenated with* the stake credential when present:
  `<paymentBase>_s<stakeRole><stakeFullHex>` for non-null stake.
  This pinning is what makes two addresses sharing a payment
  credential but differing in stake credential mint distinct bnodes
  (the SundaeSwap V3 order-book pattern surfaced the
  payment-cred-only collision in 0.2.2.0; fixed in 0.2.3.0).
- **Per-tx-position bnodes** — `_:input<N>`, `_:output<N>`,
  `_:refInput<N>`, `_:collateral<N>`, `_:withdrawal<N>`,
  `_:certificate<N>`, etc. — are *positional* (1-based on the
  ledger body). These collide across distinct Turtle files emitted
  for distinct transactions (each tx's body has its own
  `_:input1`); for cross-tx SPARQL the recommended pattern is one
  Turtle file per tx + multiple `--data` files at query time, which
  lets the SPARQL engine rename per-file blank nodes uniquely.

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

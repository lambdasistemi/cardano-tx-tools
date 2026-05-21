# 13-blueprint-passthrough — design narrative

The negative twin of fixture `12-blueprint-typed` and the second
behaviour-changing on-disk fixture for feature 050. The transaction
body is byte-equal to fixture 12 — same SwapOrder inline datum on
output 1 at the `amaru.swap.v2` script-credential address, same
recipient pubkey-credential output 2 — but the fixture's
`rules.yaml` does __not__ declare a `blueprints:` block. The walker
therefore hits the `NoBlueprintRegistered` branch in
`Cardano.Tx.Graph.Emit.Blueprint` and falls back to the pre-#50
opaque `cardano:hasRawBytes` literal on the Datum subject.

This is the operational proof of:

- **SC-003** — no typed `:<ctor>_<field>` predicates leak into the
  no-blueprint path.
- **FR-018** — back-compat byte-stability: the emitted Datum block
  is byte-equal to what the pre-T103 emitter would have produced on
  the same datum body. The blueprint-decode work added in T101–T103
  must not regress the opaque-fallback shape that fixtures
  01..11 already rely on.

The cross-fixture traceability spec
(`test/Cardano/Tx/Graph/Emit/BlueprintPredicateTraceabilitySpec.hs`,
introduced by T104's navigator) asserts the emitted
`:<ctor>_<field>` predicate set is empty here.

## Provenance

The SwapOrder shape and the recipient pubKeyHash bytes come from
the operator-paste Conway CBOR at
`test/fixtures/blockfrost-cache/operator-paste-2026-05-21.cbor.hex`,
the same source fixture 12 uses. The inline datum on output 1
carries:

```
d8799fd8799f581c64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540efffff
```

which decodes as `Constr 0 [Constr 0 [B 0x64f35d…]]` — the wire
form of `SwapOrder { recipient = PubKeyCredential 0x64f35d… }`.
Keeping the datum body byte-equal to fixture 12 is deliberate:
isolating the variable under test (blueprint registered vs not)
makes the negative-vs-positive byte-diff between
`12-blueprint-typed/expected.ttl` and
`13-blueprint-passthrough/expected.ttl` directly readable.

The `amaru.swap.v2` script hash
(`fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077`) is the
same on-chain mainnet hash fixtures 11 + 12 mirror.

## Byte-shape ADR

The walker emits the pre-#50 opaque shape on the SwapOrder Datum
subject:

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_c9bc91a9f2f9d50c ;
  cardano:hasRawBytes "d8799fd8799f581c64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540efffff" .

_:hash_datum_c9bc91a9f2f9d50c a cardano:Identifier ;
  cardano:leafType "DatumHash" ;
  cardano:bytesHex "c9bc91a9f2f9d50ce4972df3f798f41b114375b22b1829cef28e3ef94ba0675f" .
```

No `:SwapOrder_*` predicates on the Datum subject and no per-field
sub-bnodes — the typed-emission branch is only reached when
`paymentScriptHash → lookupBlueprint` returns `Just`.

## Relationship to fixture 12

Cross-reading the two `expected.ttl` files line-by-line is the
intended reviewer workflow:

| line range          | fixture 12                              | fixture 13                            |
|---------------------|-----------------------------------------|---------------------------------------|
| `_:outputDatum1`    | `:SwapOrder_recipient _:…_recipient`    | `cardano:hasRawBytes "d8799f…"`       |
| `_:…_recipient`     | `:_0_pubKeyHash _:…_recipient_pubKey…`  | (no sub-bnode)                        |
| `_:…_pubKeyHash`    | `Identifier` with `bytesHex 64f35d…`    | (no sub-bnode)                        |

Everything else (entity overlay, address decompositions, output 2's
payment-credential bnode joining the recipient pubKeyHash, the
transaction-body subjects) is identical between the two fixtures.

## Walker contract

No walker changes are needed for T104. The `NoBlueprintRegistered`
branch has been correct since T102 — fixture 13 is the first
fixture to exercise it on a script-credential output (fixtures
01..11 sit at pubkey-credential addresses where the
`paymentScriptHash` lookup returns `Nothing` upstream). The
byte-equality assertion in `EmitGoldenSpec` is the load-bearing
check; the traceability spec is the cross-fixture invariant.

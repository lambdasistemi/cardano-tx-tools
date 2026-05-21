# 12-blueprint-typed — design narrative

First behaviour-changing on-disk fixture for feature 050
(blueprint-decode typed triples). The transaction body is the
minimum needed to exercise:

- **Typed SwapOrder emission** — output 1 sits at the
  `amaru.swap.v2` script-credential address and carries an inline
  CIP-57 SwapOrder datum. With the blueprint at
  `../blueprints/swap-v2-datum.cip57.json` registered in
  `rules.yaml`, the walker mints typed
  `:SwapOrder_recipient` / `:_0_pubKeyHash` predicates instead of
  the opaque `cardano:hasRawBytes` triple.
- **SC-002 cross-bnode bytesHex join** — output 2 sits at a
  pubkey-credential address whose payment key-hash equals the
  SwapOrder recipient's `pubKeyHash`. The emitter independently
  emits the same 28-byte hex literal on the recipient bnode AND on
  the output's payment-credential bnode, so the literal appears
  ≥ 2 times in the byte stream. The future #49 reasoner promotes
  this co-occurrence to `owl:sameAs`; here we only assert the
  textual coincidence.

## Provenance

The SwapOrder shape and the recipient pubKeyHash bytes come from
the operator-paste Conway CBOR at
`test/fixtures/blockfrost-cache/operator-paste-2026-05-21.cbor.hex`.
The inline datum on the operator-paste tx's output 1 carries:

```
d8799fd8799f581c64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef ff ff
```

which decodes as `Constr 0 [Constr 0 [B 0x64f35d…]]` — the wire
form of `SwapOrder { recipient = PubKeyCredential 0x64f35d… }`.
The 28-byte hash
`64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef` is the
PubKey recipient's hash; the spec.md User Story 1 example has been
patched to match (the pre-T103 draft mis-typed it as
`PaymentScript`).

The `amaru.swap.v2` script hash
(`fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077`) is the
same on-chain script hash fixture
`11-amaru-treasury-swap-real` already mirrors.

## Byte-shape ADR

The walker emits a triply-nested shape on the SwapOrder Datum
subject:

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_… ;
  :SwapOrder_recipient _:datum1_recipient .

_:datum1_recipient :_0_pubKeyHash _:datum1_recipient_pubKeyHash .

_:datum1_recipient_pubKeyHash a cardano:Identifier ;
  cardano:leafType "Bytes" ;
  cardano:bytesHex "64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef" .
```

The `:_0_pubKeyHash` predicate uses the `"_0"` constructor-title
fallback (FR-008 / D-001b) because the inner OpenObject (the
`PubKeyCredential` constructor) doesn't carry a title through the
`decodeBlueprintData` AST — only field titles survive. The outer
`:SwapOrder_*` predicates use the SwapOrder definition's title,
sourced through `resolveBlueprintSchema` from the
`$ref` indirection in the blueprint.

**Leaf-type refinement (decided: deferred)**. The walker emits
`cardano:leafType "Bytes"` on the recipient pubKeyHash bnode. A
small `leafTypeFromFieldName` lookup table (mapping `pubKeyHash`
→ `"PaymentKey"`, `scriptHash` → `"PaymentScript"`, etc.) is an
attractive operator-blueprint-aware refinement but it introduces a
new concept (field-name → leafType) that should land in its own
slice with broader fixture coverage. T103 ships the typed-emission
path with `"Bytes"`; a follow-up will refine.

## Cross-bnode join (SC-002)

The recipient pubKeyHash bytes
(`64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540ef`)
appear twice in `expected.ttl`:

1. On `_:datum1_recipient_pubKeyHash`, sourced through the typed
   SwapOrder datum walk.
2. On the payment-credential bnode for output 2's address (the
   recipient output), sourced through the body emitter's address
   decomposition path.

The navigator `bytes-match-output-address` invariant counts these
occurrences in the emitted Turtle.

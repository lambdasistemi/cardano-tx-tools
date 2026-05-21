# 14-blueprint-decode-fail — design narrative

The third on-disk fixture for feature 050 and the
__wrong-shape blueprint__ case. The transaction body is byte-equal
to fixtures `12-blueprint-typed` + `13-blueprint-passthrough` (same
SwapOrder inline datum on output 1 at the `amaru.swap.v2`
script-credential address, same recipient pubkey-credential output
2). The behaviour difference comes from `rules.yaml` registering
the deliberately-wrong-shape blueprint
`../blueprints/swap-v2-wrong-shape.cip57.json` against the SwapOrder
script hash.

When the walker calls `decodeBlueprintData` against the registered
blueprint and the real SwapOrder payload, the decoder hits
`BlueprintDataTypeMismatch "bytes"`: the schema declares the
SwapOrder `recipient` field as a flat `bytes` leaf, but the payload's
`recipient` is a `Constr` value (the PubKeyCredential wrapper). The
walker projects this onto the `DecodeFailed` branch in
`Cardano.Tx.Graph.Emit.Blueprint`, which `emitDecodedOrOpaque`
renders as:

- ONE `cardano:hasRawBytes "<cbor-hex>"` literal on the Datum
  subject (pre-#50 opaque shape).
- ONE `cardano:decodeError "<reason>"` literal on the same Datum
  subject (FR-005 / D-001d FIRST-error-only).

No `:<ctor>_<field>` typed predicates appear on the Datum subject —
the typed unfold never happens when decode fails.

## Wrong-shape ADR

The blueprint at `../blueprints/swap-v2-wrong-shape.cip57.json`:

```jsonc
"SwapOrder": {
  "dataType": "constructor",
  "index": 0,
  "fields": [
    { "title": "recipient", "dataType": "bytes" }  // wrong: real shape is a Credential constr
  ]
}
```

The correct blueprint at `../blueprints/swap-v2-datum.cip57.json`
wraps `recipient` in a `Credential` definition (`anyOf`
`PubKeyCredential` / `ScriptCredential`). The structural divergence
is the smallest possible — one field, constructor wrap vs flat leaf
— so a reviewer can pin the failure cause by diffing the two
JSON files.

## Stderr warning

The `tx-graph` exe writes one stderr line per `cardano:decodeError`
triple in the emitted graph. The line shape is recorded in
`expected.txt`; `TxGraphExeSpec` substring-matches stderr against
that file. The exe still exits 0 — `cardano:decodeError` is a
data-quality signal, not a fatal error.

## Provenance

Same datum body as fixtures 12 + 13 — the operator-paste CBOR at
`test/fixtures/blockfrost-cache/operator-paste-2026-05-21.cbor.hex`
(inline datum
`d8799fd8799f581c64f35d26b237ad58e099041bc14c687ea7fdc58969d7d5b66e2540efffff`,
SwapOrder { recipient = PubKeyCredential 0x64f35d… }).

## Walker contract

No walker changes are needed for T105. The `DecodeFailed` branch has
been correct since T102; the `cardano:decodeError` literal
machinery is at `src/Cardano/Tx/Graph/Emit/Project.hs:1808-1820`.
Fixture 14 is the first on-disk fixture to exercise that branch
end-to-end through the loader + walker + serializer. The only
production change is a small stderr-warn hook in `app/tx-graph/Main.hs`
that scans `graphBody` for `cardano:decodeError` triples and prints
one warning line per occurrence — necessary so the operator sees
the failure on stderr without parsing the emitted Turtle.

## Relationship to fixtures 12 + 13

| Fixture | Blueprint registered? | Blueprint shape | Datum subject emission                        |
|---------|-----------------------|-----------------|-----------------------------------------------|
| 12      | yes                   | correct         | `:SwapOrder_recipient` + per-field sub-bnodes |
| 13      | no                    | (n/a)           | `cardano:hasRawBytes` (opaque fallback)       |
| 14      | yes                   | wrong-shape     | `cardano:hasRawBytes` + `cardano:decodeError` |

The three fixtures cover the full FR-002 / FR-004 / FR-005 branch
table at the on-disk-fixture level.

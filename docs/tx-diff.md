# tx-diff

Structural diff between two Conway transactions. Reads each
transaction as CBOR hex (or a `cardano-cli` JSON envelope), decodes
it through the ledger, and reports the differences keyed by ledger
identity — input `TxIn`, output address + asset, vkey-witness key
hash, redeemer purpose + index — not by byte offset. Plutus datums
and redeemers are decoded against an optional blueprint schema.

```text
Usage: tx-diff [--render tree|paths] [--tree-art ascii|unicode]
               [--collapse-rules FILE] [--blueprint FILE ...]
               [--resolve-n2c SOCKET --network-magic N]
               [--resolve-web2 URL [--web2-api-key-file PATH]]
               TX_A TX_B
```

## Examples

Plain diff between two unsigned tx CBOR hex files:

```bash
tx-diff a.cbor.hex b.cbor.hex
```

Same, but decode datums and redeemers against a Plutus blueprint
and resolve referenced inputs from a running node via N2C:

```bash
tx-diff \
  --blueprint plutus.json \
  --resolve-n2c "$CARDANO_NODE_SOCKET_PATH" \
  --network-magic 1 \
  a.cbor.hex b.cbor.hex
```

Resolve inputs from a Blockfrost-style HTTP endpoint instead of
N2C:

```bash
tx-diff \
  --resolve-web2 https://cardano-preprod.blockfrost.io/api/v0 \
  --web2-api-key-file ~/.blockfrost/preprod.key \
  a.cbor.hex b.cbor.hex
```

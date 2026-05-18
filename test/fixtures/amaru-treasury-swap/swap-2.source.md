# Amaru treasury swap-2 — provenance

## Transaction

- **tx hash**: `5262be893119bd6d43c1c2fce5b0b89f7ac15f8e7d3d3dd66d0eb01e42b875d7`
- **network**: mainnet (network_compliance treasury scope)
- **block height**: 13416894
- **slot**: 187188550
- **block time**: 1778754841 (Unix epoch)
- **validity hereafter**: slot 187660799
- **fee**: 452865 lovelace
- **size**: 2190 bytes
- **redeemers**: 2 (`spend` on treasury input, `reward` on treasury stake)

This transaction is structurally identical to swap-1 (same script
addresses, same datum shape) but at different block height / different
input/output values. swap-2 spends the treasury leftover and one of
the user payments produced by swap-1.

## Outputs

Same shape as swap-1:
- two swap orders at the swap.v2 address (with treasury stake credential)
- one treasury leftover at the network_compliance treasury address
- two payments back to the user recipient

## Fetch

```bash
KEY=<mainnet blockfrost project_id>
HASH=5262be893119bd6d43c1c2fce5b0b89f7ac15f8e7d3d3dd66d0eb01e42b875d7
curl -s -H "project_id: $KEY" \
    "https://cardano-mainnet.blockfrost.io/api/v0/txs/$HASH/cbor" \
    | jq -r .cbor > swap-2.cbor.hex

for input_hash in \
    11ace24a7b0caad4a68a38ef2fff18185dc9ea604e84425dab487cae94e4cf54 \
    25ba96f5deb14bb5c56e7542d6a9ba8450f52cc698ebd74574e1a0525d861095 \
    810bfcbde85ae72f27d7e8cd154c03c802de15d3fa0dd83a32a4b0fdba330b3c \
    e7b395a93d49a17994d66df0e4778a01dee05e7711e6612f28d97b63e4e6311c \
    5fc04113da630ec676a5a7a66d82f53c0e64527ee592c3e6c5e1dccad67732ea ; do
  curl -s -H "project_id: $KEY" \
      "https://cardano-mainnet.blockfrost.io/api/v0/txs/$input_hash/cbor" \
      | jq -r .cbor > "swap-2.producer-txs/$input_hash.cbor.hex"
done
```

Fetched 2026-05-18.

## Resolved inputs

Stored as one `<txid>.cbor.hex` file per producer transaction under
`swap-2.producer-txs/`. Note: swap-1
(`5fc04113da630ec676a5a7a66d82f53c0e64527ee592c3e6c5e1dccad67732ea`)
appears here because swap-2 spends two of its outputs.

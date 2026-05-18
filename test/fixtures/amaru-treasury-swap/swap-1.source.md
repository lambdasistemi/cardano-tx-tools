# Amaru treasury swap-1 — provenance

## Transaction

- **tx hash**: `5fc04113da630ec676a5a7a66d82f53c0e64527ee592c3e6c5e1dccad67732ea`
- **network**: mainnet (network_compliance treasury scope)
- **block height**: 13416698
- **slot**: 187184064
- **block time**: 1778750355 (Unix epoch)
- **validity hereafter**: slot 187660799
- **fee**: 452865 lovelace
- **size**: 2190 bytes
- **redeemers**: 2 (`spend` on treasury input, `reward` on treasury stake)

## Outputs

- two swap orders at
  `addr1x8ax5k9mutg07p2ngscu3chsauktmstq92z9de938j8nqaejyqwur6p8pqmycmzz55lcnan4x99mnt2a5fe54ggt4gxst7gy3n`
  (payment = `amaru.swap.v2` script, stake = publisher key)
- one treasury leftover at
  `addr1xyezq8wpaqnssdjvd3p220uf7e6nzjae44w6yu625y965rfjyqwur6p8pqmycmzz55lcnan4x99mnt2a5fe54ggt4gxs8thzgk`
  (payment = `amaru-treasury.network_compliance` script, stake = publisher
  key)
- two payments to user
  `addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz`

## Fetch

```bash
KEY=<mainnet blockfrost project_id>
HASH=5fc04113da630ec676a5a7a66d82f53c0e64527ee592c3e6c5e1dccad67732ea
curl -s -H "project_id: $KEY" \
    "https://cardano-mainnet.blockfrost.io/api/v0/txs/$HASH/cbor" \
    | jq -r .cbor > swap-1.cbor.hex

for input_hash in \
    11ace24a7b0caad4a68a38ef2fff18185dc9ea604e84425dab487cae94e4cf54 \
    25ba96f5deb14bb5c56e7542d6a9ba8450f52cc698ebd74574e1a0525d861095 \
    810bfcbde85ae72f27d7e8cd154c03c802de15d3fa0dd83a32a4b0fdba330b3c \
    e7b395a93d49a17994d66df0e4778a01dee05e7711e6612f28d97b63e4e6311c \
    b63aa2dd78c2a63b71aeba687cf45d445a98653a81f48774aa30236e47f30b86 ; do
  curl -s -H "project_id: $KEY" \
      "https://cardano-mainnet.blockfrost.io/api/v0/txs/$input_hash/cbor" \
      | jq -r .cbor > "swap-1.producer-txs/$input_hash.cbor.hex"
done
```

Fetched 2026-05-18.

## Resolved inputs

Stored as one `<txid>.cbor.hex` file per producer transaction under
`swap-1.producer-txs/`, matching the canonical layout consumed by
`Cardano.Tx.Validate.LoadUtxo.loadUtxo` (the test-only resolver
shared with the `swap-cancel-issue-8` fixture).

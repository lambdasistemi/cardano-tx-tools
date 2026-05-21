# Blockfrost-cache fixture directory

Hex-encoded CBOR of random Conway mainnet transactions used by
the `BlockfrostSampleSmokeSpec` terminal acceptance gate
(T127 / S25, per operator A-005). Each `<slug>.cbor.hex` file
is the raw CBOR bytes of one Conway tx, hex-encoded (no
`txBodyType` envelope wrapping).

## Provenance

Cache files are sourced from `cardano-mainnet.blockfrost.io`:

- `GET /blocks/latest` — pin a chain tip.
- `GET /blocks/<hash>/txs` — list tx hashes in the block.
- `GET /txs/<hash>/cbor` — fetch CBOR hex.

The first cache entry was vendored from the operator's morning
tx that crashed pre-T116
(`operator-paste-2026-05-21.cbor.hex`).

## Refresh policy

- The cache stays checked-in so CI without Blockfrost
  credentials can still run the smoke gate.
- An operator with `$BLOCKFROST_API_KEY_MAINNET` set can
  refresh / extend the cache by running
  `scripts/blockfrost-sample-fetch <N>` (when present) or
  manually fetching `<hash>.cbor.hex` files via
  `curl -H "project_id: $KEY"`.
- Never log the API key — the helper script reads via
  environment variable and passes through to `curl` headers.

## Acceptance contract

`BlockfrostSampleSmokeSpec` walks every `*.cbor.hex` file in
this directory and asserts:

1. The bytes decode as a Conway `ConwayTx` (via
   `decodeConwayTxInput`).
2. `Cardano.Tx.Graph.Emit.emit` returns `Right` (no
   `PUnsupportedLeafType` / `MalformedTxCbor` / etc.).
3. The emitted Turtle parses cleanly (prefix declarations +
   body sections, no `_internal:` substring leak).

Per A-005, this is the **terminal acceptance gate** — a
failure on any cache entry blocks `gh pr ready`.

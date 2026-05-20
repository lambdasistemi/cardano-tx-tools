# 03-multi-asset-transfer — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Operator-declared entities

`alice` + `bob` reuse the same 28-byte payment / stake key hashes
as `02-alice-bob-ada` — identical bech32 strings, identical
identifier bytes.

`usdm` + `meme` are native assets; their `AssetClass` identifier
is encoded as a single `bytesHex` of policy (28 bytes) concatenated
with the asset name (hex-encoded ASCII), extending T015's
`Identifier` + `bytesHex` pattern. The semantic encoding (whether
to split into `hasPolicy` + `hasAssetName`) is #47's territory;
this file only locks the on-disk contract shape.

## Input

Alice's multi-asset UTxO (200 ADA + 500 USDM + 5_000_000 MEME).
Quantities live in the `rules.yaml` / `expected.txt` pair; this
graph only carries the structural shape (resolution + address)
per kmaps#53 Phase A.

## Address decompositions

Same bech32 + same identifier targets as `02-alice-bob-ada`.

# Quickstart: Rewriting rules v2 — entity-centric authoring

**Branch**: `044-rewrite-rules-redesign` | **Date**: 2026-05-19

Operator-facing quick path for authoring a v2 rewriting-rules YAML. Targets the post-merge state of branch `044-rewrite-rules-redesign`; the engine the goldens validate ships in this PR, and the runnable golden harness ships in [issue #45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45).

## The 30-second mental model

You declare **entities**. An entity is a thing on chain that has a name (`treasury`, `alice`, `usdm`). Each entity is identifiable by one or more *byte-strings* under role classes — `PaymentScript` for a script-controlled address, `PoolId` for a stake pool, `AssetClass` for a native asset, etc. The renderer prints your entity's name wherever any of its identifier byte-strings appears at a typed leaf of the matching role class.

The reviewer's payoff is **cross-leaf identity**: the same name appears at the source address AND inside the datum that references that address, so the narrative is on the page instead of in the reviewer's head.

## Minimal YAML

```yaml
entities:
  - name: alice
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: bob
    from-address: addr1q8r2k7yj4vkkznhcdrqz4qa3acsyxh8mxd8shx6yh4t7rgt8s8u04hgw95dx9j4uqe6flf3v3qcgyc60v3y6h4hpvy7s9j2q5g
```

Run `tx-inspect tx.cbor --rules rules.yaml` and the rendered output shows `alice` and `bob` instead of bech32 addresses everywhere they appear (output addresses, withdrawal keys, certificate stake-creds).

## Add an asset

```yaml
entities:
  - name: usdm
    asset:
      policy: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad
      name: USDM
```

Multi-asset values render `usdm: 95` instead of `c48cbb3d…5553444d: 95`.

## Multi-role entity (same bytes worn in two contexts)

```yaml
entities:
  - name: usdm-control
    keys: [PaymentScript, Policy]
    bytes: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad
```

The script-hash leaf at a witness site renders as `usdm-control` AND the policy-id leaf at a mint site renders as `usdm-control`. Cross-leaf identity at zero extra effort.

## Add a script blueprint to see datum fields by name

```yaml
entities:
  - name: amaru.swap.v2
    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077
  - name: amaru-treasury
    from-address: addr1xyezq8wpaqnssdjvd3p220uf7e6nzjae44w6yu625y965rfjyqwur6p8pqmycmzz55lcnan4x99mnt2a5fe54ggt4gxs8thzgk
blueprints:
  - script: amaru.swap.v2
    datum: ./blueprints/swap-v2-datum.cip57.json
```

A SwapOrder datum that today renders as `datum.fields.0.fields.0` (anonymous positional indices) now renders as `datum.SwapOrder.recipient`, and if the recipient bytes match the treasury entity's script credential, the value renders as `amaru-treasury` — both at the output address site AND inside the datum.

## Collapse a chunked transaction

```yaml
collapse:
  - name: SwapOrderInput
    at: body.inputs
    match:
      required:
        - resolved.address
        - datum.SwapOrder.recipient
    view: omit
```

33 SwapOrder inputs render as `SwapOrderInput × 33` with the two variable slots shown once. `view: omit` removes the per-input subtrees below the bucket. The bucket's `resolved.address` and `datum.SwapOrder.recipient` slots both render under entity names (no `{"bytes":"…"}` form leaks).

## Migrating from 032 rules

032-style YAMLs parse unchanged. To migrate `rules/amaru-treasury.yaml` from the kind-tagged form to the entities-first form:

| 032 form | v2 form |
|---|---|
| `kind: address, key: <bech32>, match: payment, name: alice` | `- name: alice` plus `from-address: <bech32>` |
| `kind: address, key: <bech32>, match: full, name: alice` | same — `from-address:` emits both halves anyway |
| `kind: script, key: <56-hex>, name: amaru.swap.v2` | `- name: amaru.swap.v2` plus `script: <56-hex>` |

There is no behavioural difference for what the legacy form covered. The new form lets you express the new identifier kinds (`pool`, `drep`, `stake`, `asset`) and the multi-role escape hatch (`keys: [...], bytes:`).

## Common authoring patterns

### Two assets side-by-side

```yaml
entities:
  - name: usdm
    asset: { policy: c48cbb3d…, name: USDM }
  - name: meme
    asset: { policy: aa11bb22…, name: MEME }
```

### A pool + the operator's address

```yaml
entities:
  - name: alice
    from-address: addr1qx9aqv…
  - name: iog-pool-1
    pool: pool1z22x50lqsrwent6en0llzzs32wadml78v300fl6yrqlqp9q5e07
```

A `StakeDelegation` cert renders as `StakeDelegation { stake-cred: alice, pool: iog-pool-1 }`.

### A DRep

```yaml
entities:
  - name: cardano-foundation-drep
    drep: drep1y2v5h0g4qjqj9p6h9rp3z5lyqz3xczvqj5x3z7c7gj7nf2c52u7m3
```

`drep1...` resolves to `DRepKey`; `drep_script1...` resolves to `DRepScript` per CIP-129.

### A stake-only entity

```yaml
entities:
  - name: cardano-foundation.ops
    stake: stake1u9zh2u6h7n9q3v8r0p4x5w7c8e9d2k4t6m1y3z5b8j2l4n6p8q1
```

Used at withdrawal keys and at governance-action treasury-withdrawal targets.

## What the loader rejects

- Two entities declaring the same `(role-class, bytes)` pair → `EntityCollision` with both names.
- An entity with no identifiers → `EntityZeroIdentifiers`.
- A bech32 that doesn't decode → `EntityBadBech32`.
- A hex hash that isn't 56 lowercase characters → `EntityBadHex`.
- An asset name longer than 32 bytes → `EntityBadAssetName`.
- Two `blueprints:` entries for the same script hash → `BlueprintCollision`.
- A blueprint referencing an entity name that has no script identifier → `BlueprintBadScriptRef`.

All errors are produced at YAML-load time, before any rendering happens.

## What's NOT in this PR

- A `tx-inspect suggest-entities` subcommand that scans a tx and proposes a starter YAML — see spec Assumptions, deferred.
- Operator overrides of blueprint-supplied constructor/field names — see spec Assumptions.
- The predicate DSL (#15) — depends on this PR's entity surface; lands in a follow-up.

## Where the goldens live

The ten golden-test transactions defined in `spec.md` (with their expected rendered output) ship via [issue #45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45). After this PR merges, run the harness PR's `cabal test rewrite-redesign-goldens` to confirm every story renders as advertised.

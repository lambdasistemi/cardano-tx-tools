# Feature Specification: Rewrite-rules redesign — entity-centric identifier model with blueprint-decoded datum rename

**Feature Branch**: `044-rewrite-rules-redesign`
**Created**: 2026-05-19
**Status**: Draft
**Input**: Redesign the `tx-inspect` rewrite-rules ADT and engine so that the open follow-ups (lambdasistemi/cardano-tx-tools #34, #35, #36, #37, #38, #39, #40, #43) are solved by design instead of accreted as per-ticket constructors. The reviewer-facing goal is **cross-leaf identity**: two leaves at unrelated tree sites that resolve to the same on-chain entity must render with the same name, so the reviewer reads the narrative of the transaction rather than cross-checking 56-hex strings. Acceptance is pinned by ten golden-test transactions covering the full identifier surface, the blueprint-decoded-datum case, the nested-collapse case, and the collapse-suppresses-rename bug.

## Background — what the current model can't express

The shipped rewriting-rules language (specs/032-tx-inspect/) has two stages run by the renderer: a *collapse* stage that names recurring structural shapes, and a *rename* stage that substitutes identifier leaves with operator-supplied names. Both stages have been useful, but the design accretes badly:

1. **Rename is kind-tagged-per-leaf-type.** `kind: address` lands in one substitution table; `kind: script` lands in another. Each new identifier family (#34 stake, #35 pool, #36 DRep, #37 asset-policy, #38 asset-name) proposes one more sum-type constructor, one more substitution table, one more set of golden tests.
2. **The reviewer-facing goal is unreachable with substitution alone.** In an Amaru treasury swap, the swap-order's datum field `recipient` and the output address it points to *are the same entity* — but they live at different leaf sites, so today they render under two unrelated names (or, more commonly, one renders verbatim because no rule fires on the datum leaf). The reviewer has to cross-check 56-hex strings to see "the swap proceeds return to the treasury".
3. **Rename inside Plutus data is unsafe without semantic typing.** Raw Plutus Data has no notion of "this `bytes` leaf is a payment-key-hash": it's just a length-28 ByteString that could be a key-hash, a script-hash, a stake-key-hash, a DRep hash, a truncated datum hash, or an asset name padded to 28 bytes. Any heuristic match by length produces false positives that look authoritative because a name appears in the render.
4. **Collapse silently disables rename when a payment-address path is pinned in `required:`** (issue #43). Root cause: collapse pre-extracts a frozen JSON snapshot at the matched path; rename walks the typed-leaf tree. The two channels race, and the typed-leaf identity is lost at the collapsed site. Documented today as an operator-visible caveat ("keep payment-address paths out of `required:`") — i.e., a leaky abstraction.
5. **Collapse has no structural recursion** (issue #40 part 1). A `SwapOrder` collapse rule names the outer shape, but each per-output datum's inner committee list re-renders verbatim because the language has no path syntax for "the committee list inside every swap output". The result: a 33-chunk swap renders 33 redundant per-output trees ≈ 100 lines each, burying the bucket header.
6. **Collapse has no "omit raw entirely" view mode** (issue #40 part 2). `raw: hide` only prunes the leaves the rule covered; the per-item subtree still renders. For a 33-chunk swap, the bucket is unusable as a summary.

The redesign in this spec addresses all six.

## Clarifications

### Session 2026-05-19

- Q: What is the single primitive the rename engine substitutes against?
  → A: **An entity**, declared by the operator, identified by one or more `(role-class, bytes)` pairs. Every typed leaf reached by the renderer (whether from the body projection or from a blueprint-decoded datum AST) carries a role class. Lookup is `(role-class, bytes) → entity`. Cross-leaf identity emerges automatically when the same entity owns multiple identifiers; the renderer prints the entity's name at every matching site.
- Q: How is rename inside Plutus datums gated?
  → A: **Blueprint decode (CIP-57) is the only mechanism.** Raw Plutus Data without an attached blueprint renders verbatim — the engine never guesses. A blueprint declared for a script hash transforms a datum subtree into a typed AST whose leaves carry semantic roles (PubKeyHash → PaymentKey, Credential → PaymentKey-or-PaymentScript, AssetClass → policy + name pair, etc.) and whose constructors and fields carry symbolic names. The same typed-leaf walker that fires rename on body leaves also fires it on blueprint-decoded leaves.
- Q: How do the existing kind-tagged YAML rules (`kind: address | script`) survive?
  → A: As loader sugar. `kind: address` declares an entity with one identifier derived from the bech32 (payment-credential bytes under role `PaymentKey` or `PaymentScript`, depending on the bech32's payment side; optionally also the stake half). `kind: script` declares an entity with one `(PaymentScript, bytes)` identifier. New kinds in #34–#38 are loader-sugar additions, not new constructors. The internal model is the entity record; YAML kinds are just shortcuts for entity declarations.
- Q: When the blueprint types a datum field as `PubKeyHash`, should the engine cross-match against entities declared only under `StakeKey` (because both are 28-byte Ed25519 key hashes)?
  → A: **No.** Role classes are narrow by design. The operator declares an entity under every role class it genuinely wears (`keys: [PaymentKey, StakeKey]` is the explicit form). Cross-matching by default re-introduces the false-positive failure mode that gates raw datum bytes from rename in the first place.
- Q: What is the relationship between this redesign and the seven open tickets (#34, #35, #36, #37, #38, #39, #40, #43)?
  → A: This spec **supersedes** them as a single coordinated change. Each ticket is closed by one or more of the ten golden-test user stories below; the ticket numbers are cross-referenced from each story's Acceptance Scenarios. The seven tickets remain valid as work units only if the reviewer rejects this redesign — otherwise they are absorbed into the redesign's task plan and refined or closed once the harness ticket lands.
- Q: How is the test-fixture harness (the ten reproducible Conway tx builders + golden infrastructure) tracked?
  → A: As a **separate ticket** filed against this spec — [lambdasistemi/cardano-tx-tools#45](https://github.com/lambdasistemi/cardano-tx-tools/issues/45). Building synthetic Conway transactions with realistic UTxOs, blueprint-decoded datums, certificates, governance procedures, and witness sets is a non-trivial scaffold in its own right. Once the harness lands, it locks the design (the goldens are runnable artifacts a reviewer can re-render and compare) and the downstream tickets (#34–#40, #43) can be refined against runnable evidence or closed if the harness reveals they no longer make sense.

## User Scenarios & Testing *(mandatory)*

The ten user stories below are the **acceptance contract**. Each story is one Conway transaction (reproducible from a Haskell fixture builder so the golden test is end-to-end against the actual inspector engine) plus the rules YAML the operator authors plus the expected rendered output. Together they cover every identifier role class, the blueprint-decoded datum path, the nested-collapse path, the collapse-suppresses-rename bug, and the entity cross-leaf identity property.

Notation in expected output: a typed-leaf rendering as `entity-name` means the renderer substituted via the entity index; rendering as `<hex>` or `<bech32>` means no rule matched and the verbatim form is shown. The renderer prints values as a tree; indentation indicates nesting.

---

### User Story 1 — Amaru treasury swap settled (Priority: P1)

**What's in the tx**: 33 Amaru-treasury `SwapOrder` UTxOs are spent by the `amaru.swap.v2` script. Each input's datum carries a `recipient: Credential` field whose value is the `amaru-treasury.network_compliance` script hash. The settlement produces 95 USDM returned to the treasury per the recipient, plus a small ADA change output to `amaru.network-wallet`. Collateral is taken from the same network wallet. A blueprint for `amaru.swap.v2` decodes the datum into a typed AST exposing the `recipient` field by name.

**Rules YAML**:

```yaml
entities:
  - name: amaru-treasury.network_compliance
    from-address: addr1xyezq8wpaqnssdjvd3p220uf7e6nzjae44w6yu625y965rfjyqwur6p8pqmycmzz55lcnan4x99mnt2a5fe54ggt4gxs8thzgk
  - name: amaru.swap-order
    from-address: addr1x8ax5k9mutg07p2ngscu3chsauktmstq92z9de938j8nqaejyqwur6p8pqmycmzz55lcnan4x99mnt2a5fe54ggt4gxst7gy3n
  - name: amaru.swap.v2
    script: fa6a58bbe2d0ff05534431c8e2f0ef2cbdc1602a8456e4b13c8f3077
  - name: amaru.network-wallet
    from-address: addr1q802wxt6cg6aw0nl0vdzfxavu65rxu3yzhvgayw7chfxymduzkt66uw9t5kspx5jwjecx80dz4g33htknafhdhkvzd5st4f9xu
  - name: usdm
    asset:
      policy: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad
      name: USDM
blueprints:
  - script: amaru.swap.v2
    datum: ./blueprints/swap-v2-datum.cip57.json
collapse:
  - name: SwapOrderInput
    at: body.inputs
    match:
      required:
        - resolved.address
        - datum.SwapOrder.recipient
    view: omit
```

**Expected rendered output**:

```
inputs:
  SwapOrderInput × 33:
    resolved.address: amaru.swap-order
    datum.SwapOrder.recipient: amaru-treasury.network_compliance
  - resolved.address: amaru.network-wallet
    resolved.coin: 2.000000 ADA
outputs:
  - address: amaru-treasury.network_compliance
    coin: 1.500000 ADA
    assets: { usdm: 95 }
  - address: amaru.network-wallet
    coin: 0.850000 ADA
witnesses:
  scripts: [amaru.swap.v2]
fee: 0.650000 ADA
collateral:
  - resolved.address: amaru.network-wallet
```

**Why this priority**: P1 because this is the load-bearing demonstration of the redesign's reviewer-facing payoff. Every other story exercises a slice of the design; this one exercises all of it: entity cross-leaf identity (the treasury name appears at the output address *and* inside each input's blueprint-decoded datum recipient), blueprint decode (field named `recipient`, constructor named `SwapOrder`), asset entity (`usdm: 95` instead of `c48cbb3d…5553444d: 95`), nested collapse with `view: omit` (one bucket, no 33 redundant trees), and #43 fixed (`resolved.address` pinned in `required:` and the rename still fires).

**Independent Test**: Render the swap-settlement Conway tx (built by the test fixture) with the YAML above; diff against the expected output above; pass iff identical.

**Acceptance Scenarios**:

1. **Given** the swap-settlement Conway tx and the rules YAML above, **When** the inspector renders the tx, **Then** the output equals the expected output byte-for-byte. (Closes #39, #40, #43; demonstrates entity cross-leaf identity at the body-output ↔ datum-recipient sites.)
2. **Given** the same tx with the `blueprints:` section removed from the YAML, **When** the inspector renders, **Then** the `datum.SwapOrder.recipient` line is replaced by a verbatim raw-data rendering (e.g., `datum.fields.0.Script: <script-hex>`) and the collapse bucket's `required:` no longer matches that subpath; the rest of the rendering is unchanged. (Demonstrates: blueprint decode is the gate for datum rename — without a blueprint, datum bytes render verbatim, no heuristics.)

---

### User Story 2 — Plain ADA transfer Alice → Bob (Priority: P2)

**What's in the tx**: Alice spends one of her UTxOs and pays 10 ADA to Bob. The tx has one input, two outputs (Bob's payment + Alice's change), no scripts, no datums, no certificates, no withdrawals.

**Rules YAML**:

```yaml
entities:
  - name: alice
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: bob
    from-address: addr1q8r2k7yj4vkkznhcdrqz4qa3acsyxh8mxd8shx6yh4t7rgt8s8u04hgw95dx9j4uqe6flf3v3qcgyc60v3y6h4hpvy7s9j2q5g
```

**Expected rendered output**:

```
inputs:
  - resolved.address: alice
    resolved.coin: 100.000000 ADA
outputs:
  - address: bob
    coin: 10.000000 ADA
  - address: alice
    coin: 89.825000 ADA
fee: 0.175000 ADA
```

**Why this priority**: P2 baseline. Proves entity-centric rename for the simplest case (payment-key address, role `PaymentKey`); no blueprint, no collapse, no compound identifiers; if this fails the whole engine is broken.

**Independent Test**: Render the Alice→Bob Conway tx with the YAML above; assert byte-equal to the expected output.

**Acceptance Scenarios**:

1. **Given** the Alice→Bob Conway tx and the rules YAML above, **When** the inspector renders, **Then** every address leaf appears as its entity name; no leaf renders verbatim.

---

### User Story 3 — Multi-asset transfer with two declared assets (Priority: P2)

**What's in the tx**: One input from alice; one output to bob carrying `(50 ADA, 100 USDM, 1_000_000 MEME)`; one change output back to alice. Two asset entities are declared: USDM (a stablecoin) and MEME (a fictional memecoin under a different policy).

**Rules YAML**:

```yaml
entities:
  - name: alice
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: bob
    from-address: addr1q8r2k7yj4vkkznhcdrqz4qa3acsyxh8mxd8shx6yh4t7rgt8s8u04hgw95dx9j4uqe6flf3v3qcgyc60v3y6h4hpvy7s9j2q5g
  - name: usdm
    asset: { policy: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad, name: USDM }
  - name: meme
    asset: { policy: aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc, name: MEME }
```

**Expected rendered output**:

```
inputs:
  - resolved.address: alice
    resolved.coin: 200.000000 ADA
    resolved.assets: { usdm: 500, meme: 5_000_000 }
outputs:
  - address: bob
    coin: 50.000000 ADA
    assets: { usdm: 100, meme: 1_000_000 }
  - address: alice
    coin: 149.825000 ADA
    assets: { usdm: 400, meme: 4_000_000 }
fee: 0.175000 ADA
```

**Why this priority**: P2. Closes #37 + #38 via the `AssetClass` role class — one entity declared per (policy, name) compound key. Demonstrates that two unrelated asset entities can coexist and that the renderer collapses both the policy and the name leaves into the entity name at every multi-asset map site.

**Independent Test**: Render the multi-asset Conway tx; assert byte-equal to the expected output.

**Acceptance Scenarios**:

1. **Given** the multi-asset tx and the YAML above, **When** the inspector renders, **Then** every `(policy, name)` asset map key appears as the entity name (`usdm`, `meme`) and the policy/name leaves do not render verbatim anywhere in the tree.

---

### User Story 4 — Plutus mint where the policy hash is also a payment-script witness (Priority: P2)

**What's in the tx**: A treasury tx mints 1000 USDM (under the USDM policy) and *also* spends a UTxO locked by the same script hash being used as a spending validator (an unusual but legal pattern). The same 28-byte hash appears as a `Policy` role in the mint field and as a `PaymentScript` role in the input's address and in the witness set's `scripts` field.

**Rules YAML**:

```yaml
entities:
  - name: usdm-control
    keys: [PaymentScript, Policy]
    bytes: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad
  - name: usdm
    asset: { policy: c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad, name: USDM }
  - name: alice
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
```

**Expected rendered output**:

```
inputs:
  - resolved.address: <addr-under-usdm-control-script>   # bech32 verbatim
                                                          # because no entity
                                                          # declared for the full
                                                          # address
    resolved.coin: 5.000000 ADA
outputs:
  - address: alice
    coin: 4.500000 ADA
    assets: { usdm: 1000 }
mint:
  usdm-control: { usdm: +1000 }
witnesses:
  scripts: [usdm-control]
fee: 0.500000 ADA
```

**Why this priority**: P2. Closes the script-vs-asset-policy overlap concern in #37. Demonstrates: one entity carries two role classes (`PaymentScript` + `Policy`) for the same bytes; the renderer dispatches each typed leaf through the right role index and prints the entity name in both contexts; the `usdm` asset entity is independent of the `usdm-control` script entity (the asset is the thing minted; the script is the thing that authorised it). Also demonstrates the negative case: the input's full bech32 address does NOT match because the address as a whole was not declared as an entity — only the script credential it embeds was; the operator who wants address rendering at the input site declares an `address-of-usdm-control` entity (covered by Story 1).

**Independent Test**: Render the mint+spend tx; assert byte-equal to the expected output.

**Acceptance Scenarios**:

1. **Given** the mint+spend tx and the YAML above, **When** the inspector renders, **Then** the mint field renders as `usdm-control: { usdm: +1000 }` and the witness set's script entry renders as `usdm-control`; both leaves hit the same entity via different role classes.

---

### User Story 5 — Stake reward withdrawal from a script-controlled stake account (Priority: P2)

**What's in the tx**: Alice's wallet pays the fee; the withdrawal field claims 50 ADA in rewards from a stake account whose stake credential is a script hash (the `amaru-treasury` stake script).

**Rules YAML**:

```yaml
entities:
  - name: alice
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: amaru-treasury.network_compliance
    from-address: addr1xyezq8wpaqnssdjvd3p220uf7e6nzjae44w6yu625y965rfjyqwur6p8pqmycmzz55lcnan4x99mnt2a5fe54ggt4gxs8thzgk
```

**Expected rendered output**:

```
inputs:
  - resolved.address: alice
    resolved.coin: 2.000000 ADA
outputs:
  - address: alice
    coin: 51.825000 ADA
withdrawals:
  amaru-treasury.network_compliance: 50.000000 ADA
fee: 0.175000 ADA
```

**Why this priority**: P2. Closes #34. Demonstrates: the entity loader, fed a `from-address`, extracts *both* halves (`PaymentScript` and `StakeScript`); the withdrawal-key leaf at `body.withdrawals` is a RewardAccount with a `StakeScript` role; the entity index lookup succeeds; the withdrawal key renders as the entity name. No new YAML kind needed (`from-address` is sufficient sugar).

**Independent Test**: Render the withdrawal tx; assert byte-equal.

**Acceptance Scenarios**:

1. **Given** the withdrawal tx and the YAML above, **When** the inspector renders, **Then** the withdrawals map key appears as `amaru-treasury.network_compliance`, not as a `stake1...` bech32 string.

---

### User Story 6 — Stake pool delegation (Priority: P2)

**What's in the tx**: Alice delegates her stake to a known pool. The body carries a `StakeDelegation` certificate referencing the pool's key hash.

**Rules YAML**:

```yaml
entities:
  - name: alice
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: iog-pool-1
    pool: pool1z22x50lqsrwent6en0llzzs32wadml78v300fl6yrqlqp9q5e07
```

**Expected rendered output**:

```
inputs:
  - resolved.address: alice
    resolved.coin: 5.000000 ADA
outputs:
  - address: alice
    coin: 4.825000 ADA
certificates:
  - StakeDelegation:
      stake-cred: alice            # via stake credential of alice's address
      pool: iog-pool-1
fee: 0.175000 ADA
```

**Why this priority**: P2. Closes #35. Demonstrates: role class `PoolId`; entity declared via `pool: <bech32>` loader sugar; certificate cert-body leaf hits the entity index. Also demonstrates: the stake-credential of alice's address (extracted by the entity loader from `from-address`) is reused as the `stake-cred` of the certificate — cross-leaf identity between an address-derived stake credential and a cert's stake-cred field.

**Independent Test**: Render the delegation tx; assert byte-equal.

**Acceptance Scenarios**:

1. **Given** the delegation cert tx, **When** rendered, **Then** the pool leaf appears as `iog-pool-1` and the stake-cred leaf appears as `alice`.

---

### User Story 7 — Vote delegation to a DRep (Priority: P2)

**What's in the tx**: Alice delegates her voting power to a DRep operated by the Cardano Foundation. The body carries a `VoteDelegation` certificate (or `VoteRegDelegCert` if combined with registration) referencing the DRep's credential.

**Rules YAML**:

```yaml
entities:
  - name: alice
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: cardano-foundation-drep
    drep: drep1y2v5h0g4qjqj9p6h9rp3z5lyqz3xczvqj5x3z7c7gj7nf2c52u7m3   # CIP-129 form
```

**Expected rendered output**:

```
inputs:
  - resolved.address: alice
    resolved.coin: 5.000000 ADA
outputs:
  - address: alice
    coin: 4.825000 ADA
certificates:
  - VoteDelegation:
      stake-cred: alice
      drep: cardano-foundation-drep
fee: 0.175000 ADA
```

**Why this priority**: P2. Closes #36. Demonstrates: role classes `DRepKey` / `DRepScript`; entity declared via `drep: <bech32>` loader sugar discriminating on the CIP-129 prefix (`drep1...` → `DRepKey`; `drep_script1...` → `DRepScript`); the special `AlwaysAbstain` / `AlwaysNoConfidence` variants render verbatim (no rename — they are not credentials).

**Independent Test**: Render the vote-delegation tx; assert byte-equal.

**Acceptance Scenarios**:

1. **Given** the vote-delegation tx, **When** rendered, **Then** the drep leaf appears as `cardano-foundation-drep`.
2. **Given** a sibling tx that delegates votes to `AlwaysAbstain`, **When** rendered, **Then** the drep leaf appears verbatim as `AlwaysAbstain` (the variant is preserved, no rename attempted).

---

### User Story 8 — Contingency disburse (the #43 reproducer) (Priority: P2)

**What's in the tx**: Two inputs from the contingency self-script (`amaru-treasury.contingency.account`) carry the disbursement funds; one collateral input from a user wallet. One output disburses 100 ADA to a recipient.

**Rules YAML**:

```yaml
entities:
  - name: amaru-treasury.contingency.account
    from-address: addr1x8ndhlcfy30t38z0tql64fpg8ply93r37xrgvdagfpsz5nhxm0lsjfz7hzwy7kpl42jzswr7gtz8ruvxscm6sjrq9f8qruq0ae
  - name: user-wallet
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: recipient
    from-address: addr1q8r2k7yj4vkkznhcdrqz4qa3acsyxh8mxd8shx6yh4t7rgt8s8u04hgw95dx9j4uqe6flf3v3qcgyc60v3y6h4hpvy7s9j2q5g
collapse:
  - name: Input
    at: body.inputs
    match:
      required:
        - resolved.address
        - resolved.coin
    view: hide-matched
```

**Expected rendered output**:

```
inputs:
  Input × 2:
    resolved.address: amaru-treasury.contingency.account
    resolved.coin: [60.000000 ADA, 50.000000 ADA]
outputs:
  - address: recipient
    coin: 100.000000 ADA
  - address: amaru-treasury.contingency.account
    coin: 9.825000 ADA
collateral:
  - resolved.address: user-wallet
fee: 0.175000 ADA
```

**Why this priority**: P2. Closes #43 directly. Demonstrates: the collapse bucket pins `resolved.address` in `required:` — under the old design this *suppressed* rename and the address rendered as `{"bytes":"31e6dbff…"}`; under the redesign the typed-leaf walker descends into the matched subtree and the rename still fires. The bucket variable slot for `resolved.address` shows the entity name. The docs section "Pattern — keep payment addresses out of `required:`" is deleted by this fix.

**Independent Test**: Render the contingency-disburse tx; assert byte-equal to the expected output. The acceptance is that the `resolved.address` slot in the collapse bucket renders as the entity name, not as raw bytes.

**Acceptance Scenarios**:

1. **Given** the contingency-disburse tx with the YAML above, **When** rendered, **Then** the collapse bucket's `resolved.address` slot shows `amaru-treasury.contingency.account` and no `{"bytes":"…"}` form appears anywhere in the output.
2. **Given** the same YAML with `resolved.address` REMOVED from `required:`, **When** rendered, **Then** the output is structurally similar (per-input subtrees instead of a bucket) but the address renderings are identical (entity name in both cases). Cross-validates that collapse and rename are now genuinely orthogonal.

---

### User Story 9 — MPFS facts-request with chunked outputs (Priority: P2)

**What's in the tx**: An MPFS facts-request tx places N copies (e.g., 10) of the same "fact" datum into outputs to the MPFS oracle script address. Each output carries an identical inline datum shape but with per-output variable slots (the fact's content). One change output returns to the operator wallet. A blueprint for the MPFS oracle script decodes the datum into a typed AST with named fields.

**Rules YAML**:

```yaml
entities:
  - name: mpfs.oracle
    from-address: addr1x9zh2u6h7n9q3v8r0p4x5w7c8e9d2k4t6m1y3z5b8j2l4n6p8q1r3s5t7v9
  - name: mpfs.oracle.script
    script: aa11bb22cc33dd44ee55ff6677889900112233445566778899aabbcc
  - name: operator
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
blueprints:
  - script: mpfs.oracle.script
    datum: ./blueprints/mpfs-fact.cip57.json
collapse:
  - name: FactOutput
    at: body.outputs
    match:
      required:
        - address
        - datum.Fact.requester
    view: omit
```

**Expected rendered output**:

```
inputs:
  - resolved.address: operator
    resolved.coin: 50.000000 ADA
outputs:
  FactOutput × 10:
    address: mpfs.oracle
    datum.Fact.requester: operator
  - address: operator
    coin: 19.825000 ADA
fee: 0.175000 ADA
```

**Why this priority**: P2. Closes #40 (the `view: omit` mode) and cross-validates #39 (blueprint-decoded datum rename) in a second context independent of Story 1. Demonstrates: 10 facts collapse into one bucket, no per-output trees pile up below; the bucket exposes the named datum field (`requester`) and renames the operator's credential inside the datum.

**Independent Test**: Render the MPFS facts-request tx; assert byte-equal.

**Acceptance Scenarios**:

1. **Given** the MPFS facts-request tx and the YAML above, **When** rendered, **Then** the outputs section shows exactly one `FactOutput × 10` bucket and no per-output subtree appears below it.

---

### User Story 10 — Governance treasury withdrawal proposal (Priority: P3)

**What's in the tx**: An operator submits a Conway governance `ProposalProcedure` of variety `TreasuryWithdrawals` requesting that the chain treasury pay 50_000 ADA to the Cardano Foundation's operations stake address. The tx carries the proposal in `body.proposalProcedures` and an input + change output for the proposal deposit.

**Rules YAML**:

```yaml
entities:
  - name: operator
    from-address: addr1qx9aqvsf6gne2640jec828s25gzhk5wp2day8u24kf8mrs2v0zyuvk80fay35dx008p45ts0u6cdrv9g2maetq8jm8psznjcrz
  - name: cardano-foundation.ops
    from-address: addr1q8r2k7yj4vkkznhcdrqz4qa3acsyxh8mxd8shx6yh4t7rgt8s8u04hgw95dx9j4uqe6flf3v3qcgyc60v3y6h4hpvy7s9j2q5g
```

**Expected rendered output**:

```
inputs:
  - resolved.address: operator
    resolved.coin: 100_001.000000 ADA
outputs:
  - address: operator
    coin: 0.825000 ADA
proposalProcedures:
  - ProposalProcedure:
      deposit: 100_000.000000 ADA
      returnAddr: operator
      action:
        TreasuryWithdrawals:
          withdrawals:
            cardano-foundation.ops: 50_000.000000 ADA
fee: 0.175000 ADA
```

**Why this priority**: P3. Demonstrates: the governance leaf surface (proposal procedures' return address, treasury-withdrawal target) is uniformly served by the entity index — no governance-specific rename kind is needed. The `cardano-foundation.ops` entity matches the proposal's withdrawal target because the entity loader extracts the stake credential from `from-address` under role `StakeKey` (or `StakeScript` if the bech32 carries a script credential), and `TreasuryWithdrawals` target keys are RewardAccounts carrying a stake credential.

**Independent Test**: Render the governance proposal tx; assert byte-equal.

**Acceptance Scenarios**:

1. **Given** the proposal tx, **When** rendered, **Then** the proposal's `returnAddr` and the `TreasuryWithdrawals` target appear as entity names; no raw bech32 surfaces in the proposal subtree.

---

### Edge Cases

- **A 28-byte `bytes` leaf in a raw (non-blueprint-decoded) datum subtree**: renders verbatim. The renderer does NOT attempt heuristic lookup against any entity index. This is the explicit safety property protecting against false positives.
- **Two entities accidentally declaring the same `(role-class, bytes)` pair**: the loader rejects at load time with a clear error pointing at both entity declarations. There is no last-write-wins, no first-match-wins, no silent override.
- **An entity with zero identifiers (only a `name:`)**: the loader rejects. An entity must declare at least one identifier.
- **A `from-address` whose payment side is a key-credential AND a separate entity declaring the same key-hash under role `PaymentScript`**: the two entities are distinct (different role classes) and both load successfully; renders at a `PaymentKey` site hit only the first; renders at a `PaymentScript` site hit only the second. This is the role-class-narrowness property at work — the loader does not need to detect this case as ambiguous because role classes do not overlap.
- **A blueprint declared for a script that does not appear in the tx**: silently ignored (no error, no warning at render time — the blueprint just never triggers).
- **A blueprint that fails to decode a datum** (datum on chain does not match the blueprint's expected shape): the renderer falls back to verbatim raw-data rendering for that subtree and emits a structured warning. Rename does not fire on the fallback subtree; this is the only way verbatim raw bytes can co-exist with a declared blueprint, and it is the correct behaviour (a misdeclared blueprint must not corrupt the render).
- **A collapse rule whose `at:` path does not exist in the projection**: silently no-op; the collapse engine does not match anything; the rest of the rendering proceeds normally.
- **A collapse rule whose `match.required:` includes a path that the blueprint exposes by symbolic name (e.g., `datum.SwapOrder.recipient`) but the relevant input has no blueprint**: the rule does not match that input (because the path is not in the projection without blueprint decode); rule matches succeed only on the subset of inputs whose script does have a blueprint. The non-matched inputs render uncollapsed below the bucket.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The rewriting-rules language MUST express a primitive called *entity*, identified by one or more `(role-class, bytes)` identifier pairs, where the role-class enumeration is fixed and includes at least: `PaymentKey`, `PaymentScript`, `StakeKey`, `StakeScript`, `DRepKey`, `DRepScript`, `PoolId`, `Policy`, `AssetClass`.
- **FR-002**: The rename engine MUST be a single `(role-class, identifier-bytes) → entity` lookup index built once at load time. Every typed leaf reached by the renderer MUST be dispatched through this index with its role class.
- **FR-003**: Cross-leaf identity MUST be a rendering consequence: two leaves at unrelated tree sites whose `(role-class, bytes)` lookups resolve to the same entity MUST render with the same entity name. The renderer MUST NOT introduce any additional matching step that could break this property (e.g., a per-site rule list).
- **FR-004**: The YAML grammar MUST accept entity declarations in both *expressive form* (an `entities:` list with an explicit `name:` plus identifier fields) and *legacy-sugar form* (the existing `kind: address | script` rules from specs/032-tx-inspect, which the loader normalises into entity records). Both forms MUST produce identical in-memory entity indices.
- **FR-005**: The YAML grammar MUST accept a `blueprints:` section that maps script hashes (or entity names referencing scripts) to CIP-57 blueprint files. The renderer MUST use a script's blueprint to decode any datum/redeemer attached to a UTxO at that script's address into a typed AST whose leaves carry semantic roles and whose constructors and fields carry symbolic names.
- **FR-006**: Without a blueprint for a script, the renderer MUST render datums and redeemers for that script verbatim as raw Plutus Data. Rename MUST NOT fire on raw `bytes` leaves under any circumstance. There is no fallback heuristic.
- **FR-007**: The collapse engine MUST walk the typed-leaf tree once. Collapse rules MUST NOT introduce a separate pre-extracted projection. When a collapse rule pins a typed leaf in `required:`, the rename engine MUST still see that typed leaf at the collapsed site; the rendered bucket variable slot MUST show the renamed name when an entity matches. (This is the property that closes #43.)
- **FR-008**: Collapse rules MUST support nested rules via a `nested:` field whose entries are themselves collapse rules interpreted with `at:` relative to each matched item's subtree. Arbitrary nesting depth MUST be supported.
- **FR-009**: The collapse view setting MUST be a per-rule `view:` field (not a global `views.raw:`) accepting at least three modes: `show` (render the matched item below the bucket in full, current `raw: show` semantics), `hide-matched` (prune leaves the rule covered but render the rest of each item, current `raw: hide` semantics), and `omit` (render the bucket only; matched items do not appear below it).
- **FR-010**: The loader MUST reject a rules document that declares two entities sharing the same `(role-class, bytes)` identifier pair, with an error message naming both entity declarations and the offending pair.
- **FR-011**: The loader MUST reject an entity declaration with zero identifiers, with an error message naming the entity.
- **FR-012**: An entity MUST be allowed to declare multiple identifiers spanning different role classes (e.g., `keys: [PaymentScript, Policy]` for a Plutus minting policy that is also a payment validator under the same hash). Role-class narrowness MUST be preserved: entities declared under one role class MUST NOT match leaves of a different role class even when the identifier bytes coincide.
- **FR-013**: The loader sugar forms `from-address:`, `script:`, `pool:`, `drep:`, `asset:`, and explicit `keys: [...] bytes:` MUST all produce entries in the same `(role-class, bytes)` index. Sugars are interchangeable expressions of the same underlying entity model.
- **FR-014**: Renaming of an `AssetClass` identifier MUST collapse both the policy leaf and the asset-name leaf at a multi-asset map site into a single rendered name. The renderer MUST NOT render the policy separately from the asset name when the entity matches.
- **FR-015**: Blueprint decode that fails (datum bytes do not match the declared blueprint's expected shape) MUST emit a structured warning AND fall back to verbatim raw-data rendering for the affected subtree. The rest of the tx MUST render normally.
- **FR-016**: All ten golden-test transactions defined in the User Scenarios section MUST be reproducible from a checked-in Haskell fixture builder (delivered by the separate harness ticket), and each MUST have a corresponding `*.golden.txt` file whose contents equal the inspector's output byte-for-byte when run with the corresponding rules YAML.

### Key Entities

- **Entity**: A reviewer-facing name for one on-chain identity. Declared once by the operator. Carries one or more *identifiers*, each a `(role-class, bytes)` pair. The renderer prints the entity's name wherever any of its identifiers appears at a typed leaf of the matching role class.

- **Identifier**: A `(role-class, bytes)` pair. Role class is one of the closed enumeration (`PaymentKey`, `PaymentScript`, `StakeKey`, `StakeScript`, `DRepKey`, `DRepScript`, `PoolId`, `Policy`, `AssetClass`). Bytes are the canonical hash form for that role class (28 bytes for most; `AssetClass` is a compound `(28-byte policy hash, variable-length asset name)`).

- **Blueprint**: A CIP-57 schema attached to a script hash that describes how to decode datums and redeemers for UTxOs at that script's address into a typed AST. The blueprint supplies both *structural names* (constructor names, field names) and *leaf typing* (PubKeyHash → PaymentKey, Credential → PaymentKey-or-PaymentScript, AssetClass → AssetClass, etc.).

- **Typed leaf**: Any leaf the renderer reaches that carries a role class. Comes from two sources: the Conway projection (body addresses, withdrawal keys, certificate fields, mint/value asset keys, witness scripts, reference scripts) or a blueprint-decoded datum/redeemer AST. The rename engine treats both sources uniformly.

- **Collapse rule**: A subtree-shape rule that names a recurring structural pattern in the projection. Carries a `name:`, an `at:` (where the rule applies), a `match.required:` (relative paths inside each item that must be present for the rule to fire), an optional `nested:` (child rules interpreted relative to each matched item), and a `view:` (how the matched items render).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All ten golden-test transactions in this spec produce rendered output byte-equal to the expected output bundled with each story. (Pass/fail per story; 10/10 to ship.)
- **SC-002**: A reviewer presented with the rendered output of Story 1 (Amaru swap settled) can name the source entity, the destination entity, and the asset moved without consulting the rules YAML or any hash reference. Verified by user-testing the rendered output with at least three reviewers who are unfamiliar with the specific tx but familiar with the Amaru treasury vocabulary. (Qualitative pass: ≥ 2 of 3 reviewers identify all three facts correctly.)
- **SC-003**: The seven open issues (#34, #35, #36, #37, #38, #39, #40, #43) are reviewed against the harness once it lands. Each issue is either closed (because the corresponding golden-test story passes) or refined into a smaller follow-up (because the harness reveals a residual gap). The closing PR description includes a per-issue disposition table.
- **SC-004**: No operator-visible caveat survives the redesign for the cases the seven open issues describe. Specifically: the docs section "Pattern — keep payment addresses out of `required:`" is deleted; the "Not in this version: datum-embedded rename" caveat is deleted; no per-ticket workaround is documented as a permanent pattern.
- **SC-005**: All existing golden tests under `specs/032-tx-inspect/` continue to pass after the redesign loader is wired in, modulo intentional improvements where the new model renders strictly better (e.g., a previously verbatim leaf now appearing as an entity name because the legacy-sugar rule reaches it). Any intentional change is annotated in the PR.
- **SC-006**: The end-to-end render time for the Amaru swap tx (Story 1, 33-chunk settlement, blueprint-decoded datums, nested collapse with `view: omit`) is under 500ms on a developer laptop. (Not a tight budget — purely to prevent an O(n²) accident in the typed-leaf walker.)

## Assumptions

- **CIP-57 blueprints**: The redesign assumes at least one stable CIP-57 blueprint format. Test fixtures for Stories 1 and 9 include hand-authored blueprint files for the relevant scripts under `test/fixtures/blueprints/`.
- **Reviewers author rules manually**: The redesign does not include a "rule generator" that scans a tx and proposes entities. Operators write entity declarations by hand. (A follow-up ticket may add a `tx-inspect suggest-entities` subcommand that scans the diff and proposes a starter YAML — out of scope here.)
- **Predicate DSL (#15) is downstream**: The entity-centric model is the substrate the predicate DSL needs (named lvalues to address). This spec ships only the rendering side; the predicate DSL remains a separate ticket whose plan can assume entity names exist.
- **No predicate-level overrides yet**: The blueprint owns constructor and field names. Operators cannot override them in the rules YAML in this spec. (Possible follow-up: a per-blueprint override map. Out of scope here — the worked examples do not need it.)
- **Loader backwards compatibility**: Every YAML document that `parseRewriteRulesYaml` accepts today MUST parse successfully under the new loader and produce identical rendered output (modulo SC-005). This is a hard constraint, not an assumption — but stated here so the implementer knows the migration is strictly additive at the YAML level.
- **No on-disk wire-format change for collapse**: The existing collapse YAML grammar is preserved as-is. The new `view:` field per rule and the new `nested:` field are additive; documents without them parse identically. The global `views.raw:` setting is preserved as a per-tx default; a per-rule `view:` overrides it when present.
- **Test fixtures use real Conway tx builders, not synthetic stubs**: each of the ten stories has a Haskell builder that produces a `Tx ConwayEra` value structurally equivalent to a tx that could be submitted on chain (correct era, correct field shape; values are illustrative, not necessarily ledger-valid). The builders are delivered by the separate harness ticket; building synthetic UTxOs with realistic addresses, blueprint-decodable datums, certificates, governance procedures, and witness sets is non-trivial in its own right and is tracked outside this spec.

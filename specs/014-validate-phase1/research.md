# Phase 0 Research: Phase-1 pre-flight for unsigned transactions

**Feature**: 014-validate-phase1
**Date**: 2026-05-15

Five unknowns identified in `plan.md`; resolved below.

---

## R1. `Mempool.applyTx` entry point at the pinned ledger version

**Decision**: use
`Cardano.Ledger.Shelley.API.Mempool.applyTx :: Globals -> LedgerEnv ConwayEra -> MempoolState ConwayEra -> ConwayTx -> Except (ApplyTxError ConwayEra) (MempoolState ConwayEra, Validated ConwayTx)`
via the existing `cardano-haskell-packages` pin (`index-state: 2026-02-17` for hackage, `2026-03-23` for CHaP — set in `cabal.project`).

**Rationale**: this is the function inspector calls
([Validation.hs:358](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L358)).
Inspector uses index-state `2026-04-15` against CHaP `2026-04-15`;
tx-tools is on `2026-02-17 / 2026-03-23` — older. The `Mempool.applyTx`
signature has been stable since the Shelley era release, so the older
pin is not a risk. Re-verification step in Phase 2: open
`Cardano.Ledger.Shelley.API.Mempool` in the resolved build plan and
confirm the type signature. If a future CHaP bump moves the symbol,
the failure is a compile error, not a runtime divergence.

**Alternatives considered**:

- `applyTxsTransition` from `Cardano.Ledger.Shelley.Rules` — lower-level
  STS interface. Pros: no `MempoolState` wrapper. Cons: skips the
  mempool-level duplicate-detection rule (`whenFailureFreeDefault` —
  see spec.md research note); we'd lose one of the failure paths.
  Rejected.
- `Cardano.Ledger.Api`'s re-export — `cardano-ledger-api` re-exports
  some shelley symbols but not `Mempool.applyTx` at this index. Direct
  `cardano-ledger-shelley` dep is required.

## R2. `NewEpochState ConwayEra` `Default` instance

**Decision**: rely on
`Cardano.Ledger.Shelley.LedgerState.NewEpochState`'s `Default` instance,
which lives in the same module
([cardano-ledger-shelley reference](https://github.com/IntersectMBO/cardano-ledger/blob/master/libs/cardano-ledger-shelley/src/Cardano/Ledger/Shelley/LedgerState.hs)).
Used via `def :: NewEpochState ConwayEra` then mutated with
`microlens` setters for epoch number, pparams, UTxO.

**Rationale**: inspector uses this verbatim
([Validation.hs:405-413](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L405-L413)).
The `Default` instance has been stable since the Shelley refactor.

**New dependency**: `data-default` (for the `def` function — the
`Default` typeclass package on Hackage). Add to the library's
`build-depends`. Already in the transitive closure (microlens-platform,
etc.), but explicit add keeps `cabal check` strict-warnings happy.

## R3. `Globals` constants

**Decision**: copy inspector's `validationGlobals`
([Validation.hs:375-393](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L375-L393))
verbatim. Network-parameterise only the `networkId` field; everything
else is hardcoded:

| Field | Value | Source |
|---|---|---|
| `epochInfo` | `fixedEpochInfo (EpochSize 432000) (mkSlotLength 1)` | Mainnet/preprod era constant; preview differs at 86400 but Phase-1 doesn't compute epoch boundaries, so safe to leave at mainnet shape. |
| `slotsPerKESPeriod` | `129600` | Shelley genesis. |
| `stabilityWindow` | `129600` | `= 3k/f` for k=2160, f=1/20. |
| `randomnessStabilisationWindow` | `172800` | `= 4k/f`. |
| `securityParameter` | `knownNonZeroBounded @2160` | Mainnet k. |
| `maxKESEvo` | `62` | Shelley genesis. |
| `quorum` | `5` | Shelley genesis. |
| `maxLovelaceSupply` | `45 × 10¹⁵` | Cardano cap. |
| `activeSlotCoeff` | `mkActiveSlotCoeff (boundRational (1 % 20))` | Mainnet f. |
| `networkId` | caller-supplied `Network` | The only knob. |
| `systemStart` | `SystemStart (posixSecondsToUTCTime 0)` | Phase-1 doesn't read this; epoch 0 is fine. |

**Rationale**: Phase-1 (UTXOW + LEDGER) reads only `networkId`,
`epochInfo` (for slot→epoch resolution), `stabilityWindow` (for
governance vote tally — Conway-specific), `maxLovelaceSupply` (for
value-conservation check), and `quorum` (for cert checks). The rest
are stake-pool / KES bookkeeping the mempool rules don't touch. Using
mainnet values for all non-`networkId` fields is safe for both
mainnet and testnet validation as long as the tx being validated
doesn't itself violate one of these constants (e.g. minting more than
45 × 10¹⁵ lovelace would trip on mainnet too).

**Caveat noted in Haddock**: if a future spec needs to validate a tx
against a testnet with non-mainnet k or f (e.g. a custom devnet),
this function would need a `Globals` parameter rather than synthesising
from `Network` alone. Out of scope for this PR; recorded for the
upstream ticket
[inspector#73](https://github.com/lambdasistemi/cardano-ledger-inspector/issues/73)
in case the typed kernel grows a `Globals` parameter.

## R4. UTxO JSON shape from `cardano-cli query utxo --output-json`

**Decision**: parse the cardano-cli native JSON shape. Schema (per
`cardano-cli` Conway-era output):

```json
{
  "0123…txhash#0": {
    "address": "addr1q…",
    "value": { "lovelace": 1000000, "policyHex.assetNameHex": 42 },
    "datumhash": "abcd…" | null,
    "inlineDatum": { ... } | null,
    "referenceScript": { ... } | null
  },
  "0123…txhash#1": { ... }
}
```

**Rationale**: callers test this with real captured UTxOs from
`cardano-cli query utxo --whole-utxo --output-json | jq` (or the
filtered variant). Inventing a custom shape forces every caller to
re-encode; parsing the cardano-cli shape directly is zero-cost for
test fixtures and matches the muscle memory of every Cardano
developer.

**Implementation**: live in `test/Cardano/Tx/Validate/LoadUtxo.hs`.
Use `aeson` (already a tx-tools dep). Decode to
`[(TxIn, TxOut ConwayEra)]` directly. Field-by-field translation:

| JSON key | Haskell target |
|---|---|
| `"txhash#index"` (map key) | `TxIn` via `txInFromKey :: Text -> Maybe TxIn` |
| `address` | `Addr` via Bech32 decode |
| `value.lovelace` + asset entries | `MaryValue` |
| `datumhash` | `Datum` `SJust dh` if present, else `SNothing` |
| `inlineDatum` | inline `Datum` if present, overriding `datumhash` |
| `referenceScript` | `ReferenceScript` if present |

Wrapped into `TxOut ConwayEra`. Decoder is local; no need to expose.

**Alternatives considered**:

- CBOR-hex re-capture path (one row per UTxO entry, just CBOR hex of
  the `TxOut`). Pros: faithful, no field-by-field re-encoding bugs.
  Cons: caller has to first decode their cardano-cli output and then
  re-encode to this shape. Rejected for the first version; add later
  if a fixture demands it.
- Blockfrost-style JSON. Out of scope (constitution VI — no
  provider-specific test inputs).

## R5. Cert-state seeding — required for this PR?

**Decision**: **defer**. The first version of `validatePhase1`
omits cert-state seeding. The issue-#8 reproduction has no
withdrawals; the bug class issue #14 cares about (integrity hash,
fee, min-utxo, collateral, validity interval) is fully covered
without cert-state.

**Rationale**: smaller PR, fewer test fixtures, RED+GREEN folds
tighter per constitution VII. Inspector's `seedCertStateRewards`
recipe is documented in
[Validation.hs:851-871](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L851-L871)
and the
[`CertStateRewardEntry`](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L648-L651)
data type; reproducible verbatim when a withdraw-zero fixture lands.

**Follow-up ticket**: file after this PR ships, scope = "add
cert-state seeding to `validatePhase1` for withdraw-zero validation
(SundaeSwap / Indigo / Minswap V2 pattern)." Out of scope here.

**Implication for FR-001 signature**: the signature in spec.md
doesn't carry a `[CertStateRewardEntry]` argument. When the
follow-up lands, we add it as a default-empty optional via an
overloaded helper (`validatePhase1With`) rather than break the
existing surface; the typed-kernel ticket
[inspector#73](https://github.com/lambdasistemi/cardano-ledger-inspector/issues/73)
already names the eventual shape.

---

## Open items for `/speckit.tasks`

None of the items above leave a `[NEEDS CLARIFICATION]` in the spec.
The plan is implementable as-is. The two genuine "happens during
implementation" callouts:

- R1 re-verification: confirm `Mempool.applyTx` signature at the
  pinned CHaP index. Goes in the first vertical commit (compile-only
  step).
- R4 fixture: capture `cardano-cli query utxo` output for the
  issue-#8 reproduction's TxIns. Two captures (pre-fix and post-fix
  reuse the same UTxO since the bug is in the body, not the inputs).
  Goes in the fixture-prep task.

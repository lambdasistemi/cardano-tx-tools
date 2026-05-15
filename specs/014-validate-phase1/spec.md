# Feature Specification: Phase-1 pre-flight for unsigned transactions

**Feature Branch**: `014-validate-phase1`
**Created**: 2026-05-15
**Status**: Draft — awaiting user approval before `/speckit.plan`
**Input**: GitHub issue [lambdasistemi/cardano-tx-tools#14](https://github.com/lambdasistemi/cardano-tx-tools/issues/14)
**Predecessor**: [lambdasistemi/cardano-tx-tools#8](https://github.com/lambdasistemi/cardano-tx-tools/issues/8) / [PR #9](https://github.com/lambdasistemi/cardano-tx-tools/pull/9) — split off FR-003, FR-004, FR-007 from the original `Cardano.Tx.Build` self-validation spec. PR #9 already landed the scaffolding (`PParamsBound`, `Phase1Rejected (ApplyTxError ConwayEra)` on `LedgerCheck`); this spec covers the actual validator.

## Background

PR #9's spec called for `Cardano.Tx.Build` to run ledger Phase-1
validation (`applyTx` from `cardano-ledger-api`) on every body it
returns. Implementation surfaced a complication:
`applyTx` runs the UTXOW STS rule, which folds witness-completeness
checks (`MissingVKeyWitnesses`, native-script signature checks) into
the same pipeline as the static structural checks we care about
(`script_integrity_hash`, fee, min-utxo, collateral, validity
interval, ref-script bytes, language set, …).

PR #9 deferred the entire self-validation contract on the
assumption that mixing the two layers made the helper unusable.
Subsequent research (recorded below) shows that is too strong: the
ledger **accumulates** failures rather than short-circuiting, so an
unsigned tx surfaces every structural problem the body has, plus
witness-completeness noise that callers can recognise and ignore.

The chosen shape is therefore a **pre-flight** — a callable that
takes an **unsigned** `ConwayTx` (the same shape `buildWith`
returns), runs `applyTx`, and surfaces every failure verbatim. The
caller pays no signing or submission cost to discover structural
issues. The `MissingVKeyWitnesses` / native-script-signature
failures present in every result on unsigned input are expected
noise; the caller filters them out at their end (or just notices
them and proceeds to sign).

### Research finding (recorded for posterity)

`applyTx` **accumulates** failures; it does not short-circuit:

- `small-steps` `Predicate` clause: `case cond of Failure errs ->
  modify (first (map orElse errs <>)) >> pure val` — appends to
  accumulator and continues. `runTest` / `runTestOnSignal` are
  non-fatal.
- `Cardano.Ledger.Alonzo.Rules.Utxow` runs eight
  `runTest`/`runTestOnSignal` checks plus `trans @UTXO`
  unconditionally — all failures accumulate into the
  `NonEmpty (PredicateFailure ConwayEra)` that `ApplyTxError`
  carries.
- The only short-circuit is in
  `Cardano.Ledger.Conway.Rules.Mempool`'s
  `whenFailureFreeDefault`: the LEDGER subrule is skipped only when
  duplicate-detection fails (i.e. none of the tx's inputs are in
  the supplied UTxO). Practical implication: when seeding the
  synthetic `MempoolState`, include enough UTxO entries that at
  least one of the tx's inputs is found, otherwise the LEDGER rule
  never runs and the only failure reported is the
  duplicate-detection one.

A single `validatePhase1` call therefore gives the caller every
Phase-1 problem with the tx in one shot, regardless of whether the
tx is signed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Pre-flight catches a structural bug in an unsigned tx (Priority: P1)

A caller has just received an unsigned `ConwayTx` from
`buildWith`. Before they hand it to the signing pipeline (and
before they pay the cost of a node round-trip to discover a
ledger rejection in production), they call `validatePhase1`
against the same `PParams` and the same caller-resolved UTxO they
used to build the tx. The result is an `ApplyTxError ConwayEra`
that lists every Phase-1 failure the ledger detected — including
the witness-completeness failures that any unsigned tx has, and
**including any structural failure** the tx happens to have
(integrity hash mismatch, fee too small, missing collateral,
validity-interval violation, ref-script-bytes exceeded, etc.).

The caller looks at the failure list and decides:
- only witness-completeness constructors → tx is structurally
  sound; proceed to sign and submit.
- structural constructor present → fix and rebuild.

**Why this priority**: this is the contract issue #14 exists to
deliver. Without it, structural bugs surface at the node (slow,
costly, public).

**Independent Test**: load the issue-#8 / PR-#9 mainnet
`swap-cancel` fixture (`test/fixtures/mainnet-txbuild/`), call
`validatePhase1` against the committed
`test/fixtures/pparams.json`, the captured UTxO, and the
fixture's slot. The post-fix body's failure list contains
**only** witness-completeness constructors. The pre-fix body's
failure list contains a `script_integrity_hash`-mismatch
constructor **in addition to** the witness-completeness noise.
No network access.

**Acceptance Scenarios**:

1. **Given** an unsigned Conway tx that `Cardano.Tx.Build` returns
   against `PParams` `pp` and UTxO `u` at slot `s`, **When** the
   caller calls `validatePhase1 net pp u s tx`, **Then** the
   result is `Left (ApplyTxError errs)` where every element of
   `errs` is a witness-completeness constructor (the structural
   side is clean).
2. **Given** the same setup but with the body deliberately
   corrupted (e.g. fee zeroed by post-build mutation), **When**
   `validatePhase1` is called, **Then** the result is
   `Left (ApplyTxError errs)` whose `errs` contains a
   fee-related constructor **alongside** the witness-completeness
   noise.
3. **Given** the post-fix issue-#8 fixture (the build that PR #9
   stopped emitting with a wrong `script_integrity_hash`),
   **When** `validatePhase1` is called, **Then** `errs` contains
   **no** integrity-hash-mismatch constructor — only
   witness-completeness noise. (Locks in that the gate would
   confirm PR #9's fix.)
4. **Given** the pre-fix issue-#8 reproduction (body with the
   wrong integrity hash), **When** `validatePhase1` is called,
   **Then** `errs` contains the integrity-hash-mismatch
   constructor. (Locks in that the gate would have caught the
   original bug pre-signing.)

---

### User Story 2 — Researcher / debugger gets the full list of Phase-1 failures in one call (Priority: P2)

A debugger holds a tx (signed or unsigned) that the production
node rejected with one failure name. They want to know whether
other Phase-1 problems are hiding behind the one the node
reported. They run `validatePhase1` against the same `PParams`
and UTxO and get back the full `NonEmpty PredicateFailure`
collected by the UTXOW STS, without rebuilding.

**Why this priority**: validates the accumulation behaviour of
`applyTx` (research finding above). Useful for incident response.

**Independent Test**: synthesise an unsigned tx with two known
structural problems (e.g. zero fee AND a deliberately wrong
integrity hash) against the same fixture pparams. Confirm
`validatePhase1` returns a `Left` whose payload contains both
structural failure constructors (alongside the witness-completeness
noise).

**Acceptance Scenarios**:

1. **Given** an unsigned tx that violates both fee bounds and has
   a deliberately wrong `script_integrity_hash`, **When**
   `validatePhase1` is called, **Then** the underlying
   `NonEmpty PredicateFailure ConwayEra` contains at least one
   fee-related failure AND the integrity-hash-mismatch failure
   AND the witness-completeness noise — all in one call.

---

### Edge Cases

- **Witness-completeness noise is always present on unsigned
  input.** The helper does NOT filter it. The caller's job is to
  recognise these constructors and decide whether to ignore them.
  Documented as the central trade-off of the unsigned pre-flight
  shape (see Background).
- **Right ()** on unsigned input is essentially impossible (a tx
  with literally zero required signers — no pubkey inputs, no
  pubkey collateral, no native-script signatures expected — is
  the only case). Documented; not a special case in code.
- **Mempool short-circuit on duplicate-detection**: if the
  supplied UTxO contains zero entries for any of the tx's inputs,
  the LEDGER subrule is skipped and the only failure reported is
  the duplicate-detection one. The helper MUST document this and
  the test suite MUST cover it as a defensive negative case.
- **Empty UTxO list**: caller passes `[]`. Behaviour falls out of
  the previous bullet. Documented, not a special case in code.
- **Pre-Conway tx**: out of scope (constitution III). The signature
  is `ConwayTx`; the type system prevents the case.
- **Mainnet vs preprod vs preview `Globals`**: `validatePhase1`
  takes a `NetworkId` (or equivalent boundary value) so a
  preview-tx is not validated against mainnet `Globals` and vice
  versa.
- **`AccountState`**: `applyTx` reads from but does not require a
  realistic `AccountState`. We seed it empty (zero treasury, zero
  reserves) and document that any future feature that depends on
  treasury / reserves state would need this revisited.
- **Already-signed tx**: the helper accepts a signed `ConwayTx`
  too — `applyTx` doesn't care. On a fully-signed tx with no
  structural problems, the result IS `Right ()`. Story 2's
  debugger workflow exploits this; not the primary path.
- **Stake / cert-only Conway tx**: validates without Plutus
  witnesses, no redeemers. Must not falsely require Plutus
  witnesses.
- **Default-offline (constitution VI)**: every test for the
  feature MUST run without network. UTxO is supplied as
  test-fixture data on disk (JSON from `cardano-cli query utxo`
  or CBOR-hex re-capture); `PParams` lives in
  `test/fixtures/pparams.json`; the tx body is a fixture; no
  signing keys are needed at test time.
- **Test helper `loadUtxo`**: the test suite needs to parse
  cardano-cli's JSON UTxO format (and/or a CBOR-hex re-capture
  path). The helper lives in the test directory; it is NOT
  exposed as a library API.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose a public function with the
  shape

    ```haskell
    validatePhase1 ::
        NetworkId ->
        PParamsBound ->
        [(TxIn, TxOut ConwayEra)] ->
        SlotNo ->
        ConwayTx ->
        Either (ApplyTxError ConwayEra) ()
    ```

    where `PParamsBound` is the existing newtype from PR #9 and
    `ConwayTx` is the existing type alias from
    `Cardano.Tx.Ledger`. The exact module path for the new
    function is a `/speckit.plan` decision; the signature is
    fixed here.

- **FR-002**: `validatePhase1` MUST synthesise a `Globals` value
  appropriate for the supplied `NetworkId` (mainnet vs preview vs
  preprod magics), an empty `AccountState`, and a `MempoolState`
  seeded from the supplied UTxO list. The function MUST then
  invoke `Cardano.Ledger.Shelley.API.Mempool.applyTx` (or the
  closest public equivalent in `cardano-ledger-api` at the
  resolved dependency version) and return its result.

- **FR-003**: On `applyTx` failure, `validatePhase1` MUST return
  `Left e` where `e` is the original `ApplyTxError ConwayEra`
  verbatim. No re-classification, no message flattening, no
  filtering of witness-completeness failures, no partial
  information loss. Filtering is the caller's responsibility.

- **FR-004**: `validatePhase1` MUST be pure (no `IO`). All state
  is in its inputs.

- **FR-005**: The function MUST NOT be wired into `buildWith` /
  `build`. It is a standalone callable in the same library;
  callers invoke it explicitly between build and sign.

- **FR-006**: At least one test exercises the happy path on the
  PR-#9 issue-#8 fixture: the corrected unsigned body, run
  through `validatePhase1`, returns a `Left` whose `errs` contains
  **no** structural constructor — only witness-completeness
  noise.

- **FR-007**: At least one test exercises a deliberately
  invalid plan (e.g. zero fee, or `script_integrity_hash`
  manually mutated, or both) and observes the expected
  structural constructor present in the `ApplyTxError`
  alongside the witness-completeness noise.

- **FR-008**: The test suite MUST run with no network access.
  Fixtures (`pparams.json`, UTxO, tx body) live on disk and are
  committed.

- **FR-009**: A `loadUtxo` test helper MUST parse cardano-cli's
  JSON UTxO format. It is implemented in the test directory
  only; it is not part of the public library surface (per
  constitution II — `Cardano.Tx.*` only exposes runtime
  functionality, not test scaffolding).

- **FR-010**: The Haddock for `validatePhase1` MUST document the
  central trade-off: on unsigned input the result is almost
  always `Left`, with the witness-completeness constructors
  expected as noise; callers filter at their end. The docstring
  MUST name the constructors that count as noise so callers know
  what to filter.

- **FR-011**: The work MUST NOT regress any existing passing
  test in `nix flake check` on `main`.

### Key Entities

- **`validatePhase1`**: the new pure callable; pre-flight gate
  that callers use between `buildWith` and signing.
- **`ApplyTxError ConwayEra`**: the ledger's verdict type;
  carries a `NonEmpty PredicateFailure ConwayEra` accumulating
  every Phase-1 failure the UTXOW STS detected.
- **Witness-completeness noise**: the
  `MissingVKeyWitnesses` / native-script-signature failures
  that any unsigned tx produces. Present in every pre-flight
  result; the caller filters them.
- **Structural failure**: any non-witness-completeness
  `PredicateFailure` — script integrity hash mismatch, fee
  bounds, min-utxo, collateral, validity interval, ref-script
  bytes, language-view consistency. The thing the pre-flight
  exists to surface.
- **`PParamsBound`**: existing newtype from PR #9. Reused here;
  not re-introduced.
- **`MempoolState` (seeded)**: the synthetic ledger state
  `validatePhase1` constructs. UTxO = supplied entries; ledger
  state = a fresh Conway state at the supplied slot; account
  state = empty.
- **`Globals` (synthesised)**: ledger constants for the supplied
  `NetworkId` (epoch info, network magic, security parameter,
  active-slots coefficient, max KES evolutions, slot length).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The post-fix issue-#8 unsigned reproduction returns
  a `Left` whose `errs` contains zero structural constructors —
  only witness-completeness noise. (Locks in that the pre-flight
  confirms PR #9's fix.)
- **SC-002**: The pre-fix issue-#8 unsigned reproduction returns
  a `Left` whose `errs` contains the integrity-hash-mismatch
  constructor. (Locks in that the pre-flight would have caught
  the original bug pre-signing.)
- **SC-003**: A negative test with two deliberate structural
  failures (e.g. zero fee + wrong integrity hash) returns a
  `Left` whose `errs` carries both structural constructors —
  locking in the accumulating behaviour.
- **SC-004**: The Haddock for `validatePhase1` enumerates the
  witness-completeness constructors that count as noise so the
  caller's filter logic is greppable.
- **SC-005**: `nix flake check` on the branch passes green.
- **SC-006**: A grep across consumer codebases (starting with
  `amaru-treasury-tx`) finds zero hand-rolled
  `applyTx`-shaped Phase-1 gates added after this PR merges.
  Existing pre-#14 gates may remain — porting them to
  `validatePhase1` is out of scope for this ticket but
  expected to follow in consumer PRs.

## Assumptions

- `cardano-ledger-api`'s `applyTx` (or the closest public
  equivalent at the pinned version) is callable purely with a
  synthesised `Globals` + `MempoolState`. Confirmed by the
  research recorded in the issue comment; will be re-confirmed in
  `/speckit.plan` against the actual import surface.
- `Globals` for mainnet/preview/preprod can be synthesised from
  hard-coded constants for this purpose (the same constants
  `cardano-node` uses for those nets). No new external dependency
  is required.
- The unsigned-tx fixture for the issue-#8 reproduction is the
  body PR #9 emits (post-fix) and the body PR #8's bug emitted
  (pre-fix). Both are committed under `test/fixtures/`.
- `loadUtxo` parsing the cardano-cli JSON format covers the
  primary test workflow; if a CBOR-hex re-capture path turns out
  to be needed for some fixtures, it is added in the same PR.
- Constitution VI (default-offline) is binding for the test
  suite. No LSQ / Blockfrost / HTTPS at test time.
- The new function lives under `Cardano.Tx.*` per constitution II.
  The exact module name (`Cardano.Tx.Validate`?
  `Cardano.Tx.Ledger.Phase1`? extension of `Cardano.Tx.Ledger`?)
  is left to `/speckit.plan`.

## Out of Scope

- Wiring `validatePhase1` into `buildWith` / `build`. Kept as a
  standalone callable; callers invoke explicitly.
- Filtering witness-completeness noise inside `validatePhase1`.
  Caller's responsibility. (A future helper that does the
  filter — `validateStructural` or similar — could live on top of
  `validatePhase1` later; not in this ticket.)
- Phase-2 (Plutus script execution) validation. `evaluateTx` is a
  separate concern; this ticket does not address it.
- Porting existing consumer Phase-1 gates (e.g. in
  `amaru-treasury-tx`) onto `validatePhase1`. That happens in
  follow-up consumer PRs.
- A non-Conway era. `ConwayTx` only (constitution III).
- A network-aware variant that queries a node for the live UTxO.
  Out of scope; the caller resolves the UTxO themselves
  (constitution VI).

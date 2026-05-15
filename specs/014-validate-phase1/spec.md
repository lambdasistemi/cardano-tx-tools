# Feature Specification: Phase-1 self-validation for signed transactions

**Feature Branch**: `014-validate-phase1`
**Created**: 2026-05-15
**Status**: Draft — awaiting user approval before `/speckit.plan`
**Input**: GitHub issue [lambdasistemi/cardano-tx-tools#14](https://github.com/lambdasistemi/cardano-tx-tools/issues/14)
**Predecessor**: [lambdasistemi/cardano-tx-tools#8](https://github.com/lambdasistemi/cardano-tx-tools/issues/8) / [PR #9](https://github.com/lambdasistemi/cardano-tx-tools/pull/9) — split off FR-003, FR-004, FR-007 from the original `Cardano.Tx.Build` self-validation spec. PR #9 already landed the scaffolding (`PParamsBound`, `Phase1Rejected (ApplyTxError ConwayEra)` on `LedgerCheck`); this spec covers the actual validator.

## Background

PR #9's spec called for `Cardano.Tx.Build` to run ledger Phase-1
validation (`applyTx` from `cardano-ledger-api`) on every body it
returns. Implementation surfaced a fundamental impedance mismatch:
`applyTx` runs the UTXOW STS rule, which folds witness-completeness
checks (`MissingVKeyWitnesses`, native-script signature checks) into
the same pipeline as the static structural checks we care about
(`script_integrity_hash`, fee, min-utxo, collateral, validity
interval, ref-script bytes, language set, …).

`buildWith` returns an **unsigned** body — no vkey witnesses
attached; signing is a separate step downstream. `applyTx` on a
fresh build output therefore always fails on
`MissingVKeyWitnesses` regardless of whether the body is
structurally sound.

Self-validation is feasible offline, but only on a **signed**
transaction. That moves the contract from "TxBuild guarantees its
output is Phase-1 valid" to "the same pipeline that signs and
submits a tx has a callable, offline gate that gives the ledger's
verdict before it leaves the host." Issue #14 is that gate.

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
Phase-1 problem with the tx in one shot. The original concern from
issue #14 ("does this short-circuit?") is closed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Signing pipeline rejects a Phase-1-invalid signed tx before submission (Priority: P1)

A caller has signed a Conway transaction with the wallet keys
required by the body. Before they submit to a relay (or pay the
fee for a node round-trip that will reject it), they call
`validatePhase1` against the same `PParams` and the same
caller-resolved UTxO they used to build the tx. If the ledger's
Phase-1 rule accepts the body, the call returns `Right ()`. If it
rejects, the call returns `Left (ApplyTxError ConwayEra)` carrying
every failure the ledger collected — including but not limited to
`script_integrity_hash` mismatches, fee-too-small, missing
collateral, validity-interval violations, ref-script-bytes
exceeded, missing/extra vkey witnesses.

**Why this priority**: this is the contract issue #14 exists to
deliver. Without it, the signing pipeline either submits blindly
and discovers Phase-1 bugs at the node (slow, costly, public) or
each consumer re-implements its own gate.

**Independent Test**: load the issue-#8 / PR-#9 mainnet
`swap-cancel` fixture (`test/fixtures/mainnet-txbuild/`), sign it
with a test keypair whose vkey matches the body's required
signers, call `validatePhase1` with the committed
`test/fixtures/pparams.json` snapshot, the captured UTxO, and the
fixture's slot. Expect `Right ()`. No network access.

**Acceptance Scenarios**:

1. **Given** a Conway tx body that `Cardano.Tx.Build` returns
   against `PParams` `pp` and UTxO `u` at slot `s`, **and** the
   body is signed with the required keys, **When** the caller
   calls `validatePhase1 pp u s tx`, **Then** the result is
   `Right ()`.
2. **Given** the same setup but with the body deliberately
   corrupted (e.g. fee zeroed by post-build mutation), **When**
   `validatePhase1` is called, **Then** the result is
   `Left (ApplyTxError ConwayEra _)` whose payload includes the
   ledger's name for the failure (fee too small).
3. **Given** the post-fix issue-#8 fixture (the build that PR #9
   stopped emitting with a wrong `script_integrity_hash`), signed
   correctly, **When** `validatePhase1` is called, **Then** the
   result is `Right ()` — closing the loop on PR #9's
   reproduction.
4. **Given** the pre-fix issue-#8 reproduction (body with the
   wrong integrity hash), signed correctly, **When**
   `validatePhase1` is called, **Then** the result is `Left _`
   and the `ApplyTxError` payload mentions the integrity-hash
   failure. (This locks in that the gate would have caught the
   original bug.)

---

### User Story 2 — Researcher / debugger gets the full list of Phase-1 failures in one call (Priority: P2)

A debugger holds a signed tx that the production node rejected
with one failure name. They want to know whether other Phase-1
problems are hiding behind the one the node reported. They run
`validatePhase1` against the same `PParams` and UTxO and get back
the full `NonEmpty PredicateFailure` collected by the UTXOW STS,
without rebuilding or re-signing.

**Why this priority**: validates the accumulation behaviour of
`applyTx` (research finding above). Useful for incident response
and for keeping consumer codebases free of bespoke Phase-1
inspection logic, but not the primary path.

**Independent Test**: synthesise a signed tx with two known
problems (e.g. zero fee AND missing required signer) against the
same fixture pparams. Confirm `validatePhase1` returns a `Left`
whose payload contains both failure names.

**Acceptance Scenarios**:

1. **Given** a signed tx that violates both fee bounds and is
   missing a vkey witness the body declares as required, **When**
   `validatePhase1` is called, **Then** the result is `Left _`
   and the underlying `NonEmpty PredicateFailure ConwayEra`
   contains at least one fee-related failure AND at least one
   `MissingVKeyWitnesses` failure.

---

### Edge Cases

- **Mempool short-circuit on duplicate-detection**: if the
  supplied UTxO contains zero entries for any of the tx's inputs,
  the LEDGER subrule is skipped and the only failure reported is
  the duplicate-detection one. The helper MUST document this and
  the test suite MUST cover it as a defensive negative case
  (callers can then choose to fail loudly when this is observed
  rather than ignore it).
- **Empty UTxO list**: caller passes `[]` for the supplied UTxO.
  Behaviour falls out of the previous bullet: the helper does not
  reject the call, but every tx with at least one input will
  short-circuit to the duplicate-detection failure. Documented,
  not a special case in code.
- **Pre-Conway tx**: out of scope (constitution III). The signature
  is `ConwayTx`; the type system prevents the case.
- **Mainnet vs preprod vs preview `Globals`**: `validatePhase1`
  must take a `NetworkId` (or equivalent boundary value) so a
  preview-tx is not validated against mainnet `Globals` and vice
  versa.
- **`AccountState`**: `applyTx` reads from but does not require a
  realistic `AccountState`. We seed it empty (zero treasury, zero
  reserves) and document that any future feature that depends on
  treasury / reserves state would need this revisited.
- **Stake / cert-only Conway tx**: validates without Plutus
  witnesses, no redeemers. Must not falsely require Plutus
  witnesses.
- **Default-offline (constitution VI)**: every test for the
  feature MUST run without network. UTxO is supplied as
  test-fixture data on disk (JSON from `cardano-cli query utxo`
  or CBOR-hex re-capture); `PParams` lives in
  `test/fixtures/pparams.json`; the tx body and signing keys are
  fixtures.
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
    `ConwayTx` is the existing type alias used elsewhere in
    `Cardano.Tx.*`. The exact module path is a `/speckit.plan`
    decision; the signature is fixed here.

- **FR-002**: `validatePhase1` MUST synthesise a `Globals` value
  appropriate for the supplied `NetworkId` (mainnet vs preview vs
  preprod magics), an empty `AccountState`, and a `MempoolState`
  seeded from the supplied UTxO list. The function MUST then
  invoke
  `Cardano.Ledger.Shelley.API.Mempool.applyTx` (or the closest
  public equivalent in `cardano-ledger-api` at the resolved
  dependency version) and return its result.

- **FR-003**: On `applyTx` failure, `validatePhase1` MUST return
  `Left e` where `e` is the original `ApplyTxError ConwayEra`
  verbatim. No re-classification, no message flattening, no
  partial information loss. Consumers that want a single
  failure name pick one off the `NonEmpty` themselves.

- **FR-004**: `validatePhase1` MUST be pure (no `IO`). All state
  is in its inputs.

- **FR-005**: The function MUST NOT be wired into `buildWith` /
  `build` (the rejected design from #8 / #9 — see "Background").
  It is a standalone callable in the same library; signing
  pipelines invoke it post-signing.

- **FR-006**: At least one test exercises the happy path on the
  PR-#9 issue-#8 fixture: the corrected signed body returns
  `Right ()`.

- **FR-007**: At least one test exercises a deliberately
  invalid plan (e.g. zero fee, or `script_integrity_hash`
  manually mutated) and observes the expected
  `ApplyTxError`.

- **FR-008**: The test suite MUST run with no network access.
  Fixtures (`pparams.json`, UTxO, tx body, signing keys) live
  on disk and are committed.

- **FR-009**: A `loadUtxo` test helper MUST parse cardano-cli's
  JSON UTxO format. It is implemented in the test directory
  only; it is not part of the public library surface (per
  constitution II — `Cardano.Tx.*` only exposes runtime
  functionality, not test scaffolding).

- **FR-010**: The work MUST NOT regress any existing passing
  test in `nix flake check` on `main`.

### Key Entities

- **`validatePhase1`**: the new pure callable; gate that
  signing pipelines use before submission.
- **`ApplyTxError ConwayEra`**: the ledger's verdict type;
  carries a `NonEmpty PredicateFailure ConwayEra` accumulating
  every Phase-1 failure the UTXOW STS detected.
- **`PParamsBound`**: existing newtype from PR #9. Reused here;
  not re-introduced.
- **Phase-1 validation (UTXOW + LEDGER)**: the ledger's
  static / structural acceptance check, including script-integrity
  hash, fee, min-utxo, collateral, validity interval, ref-script
  bytes, language-view consistency, AND witness-completeness
  (`MissingVKeyWitnesses`, native-script signatures). Phase-2
  (Plutus script execution) is out of scope.
- **`MempoolState` (seeded)**: the synthetic ledger state
  `validatePhase1` constructs. UTxO = supplied entries; ledger
  state = a fresh Conway state at the supplied slot; account
  state = empty.
- **`Globals` (synthesised)**: ledger constants for the supplied
  `NetworkId` (epoch info, network magic, security parameter,
  active-slots coefficient, max KES evolutions, slot length).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100 % of correctly-signed Conway transactions
  produced by `Cardano.Tx.Build` against `PParams` `pp` and
  UTxO `u` at slot `s` return `Right ()` from
  `validatePhase1 net pp u s`. No false rejections.
- **SC-002**: The pre-fix issue-#8 reproduction (signed body
  with the wrong `script_integrity_hash`) returns `Left _`
  carrying a failure that names the integrity-hash mismatch.
- **SC-003**: The post-fix issue-#8 reproduction (signed body
  with the correct integrity hash) returns `Right ()`.
- **SC-004**: A negative test with two deliberate failures
  (e.g. zero fee + missing required vkey witness) returns
  `Left _` whose `NonEmpty` carries at least two distinct
  failure constructors — locking in the accumulating
  behaviour.
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
- The signing fixture for the issue-#8 reproduction can be
  generated locally with a test keypair whose vkey matches the
  body's required signers. The signed-tx fixture is committed; the
  signing-key fixture is committed (test-only, no real funds).
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

- Wiring `validatePhase1` into `buildWith` / `build` (the
  rejected design — see Background).
- Phase-2 (Plutus script execution) validation. `evaluateTx` is a
  separate concern; this ticket does not address it.
- Porting existing consumer Phase-1 gates (e.g. in
  `amaru-treasury-tx`) onto `validatePhase1`. That happens in
  follow-up consumer PRs.
- A non-Conway era. `ConwayTx` only (constitution III).
- A network-aware variant that queries a node for the live UTxO.
  Out of scope; the caller resolves the UTxO themselves
  (constitution VI).

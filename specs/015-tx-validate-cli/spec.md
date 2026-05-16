# Feature Specification: tx-validate CLI

**Feature Branch**: `015-tx-validate-cli`
**Created**: 2026-05-16
**Status**: Draft — N2C-only scope (Blockfrost deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))
**Input**: User request after [PR #16](https://github.com/lambdasistemi/cardano-tx-tools/pull/16) ("validatePhase1") shipped: provide a new `tx-validate` executable that wraps the library function, driven by N2C against a local `cardano-node`, with the resolver session also supplying the protocol parameters and the tip slot.
**Predecessor**: [spec 014](../014-validate-phase1/spec.md) / [PR #16](https://github.com/lambdasistemi/cardano-tx-tools/pull/16) — landed the library function `Cardano.Tx.Validate.validatePhase1`.

## Background

`validatePhase1` is a pure Haskell function: `Network -> PParamsBound -> [(TxIn, TxOut ConwayEra)] -> SlotNo -> ConwayTx -> Either (ApplyTxError ConwayEra) ()`. To use it from a shell or signing pipeline (e.g. `amaru-treasury-tx`, signing daemons, CI gates) the caller currently has to write Haskell to resolve the UTxO, fetch the `PParams`, pick a slot, then call the function. Repeating that glue in every consumer is exactly what
[spec 014's SC-006](../014-validate-phase1/spec.md#measurable-outcomes) said the library should make unnecessary.

This spec covers the missing executable surface: a CLI that takes a Conway transaction as input, resolves the world it needs (UTxO + `PParams` + tip slot) from a local cardano-node via Node-to-Client (N2C), runs `validatePhase1`, and reports the verdict.

The CLI mirrors the existing `tx-diff` and `cardano-tx-generator` executables in shape, build pipeline, and release artefacts.

## Scope adjustment (2026-05-16)

The first draft of this spec also included a Blockfrost-driven session (User Stories 2 and 3 — CI gates and chained fallback). Implementation surfaced an upstream-shape mismatch: Blockfrost's
[`GET /epochs/latest/parameters`](https://docs.blockfrost.io/) emits a flat snake_case schema (`a0`, `e_max`, `cost_models_raw`, `dvt_p_p_*`, `gov_action_deposit`, …) that the `cardano-ledger-conway`-provided `FromJSON (PParams ConwayEra)` instance cannot consume — the instance expects a cardano-cli-shaped object. Bridging that schema requires ~50 explicit field mappings in a custom decoder, brittle across Blockfrost schema bumps. The honest split:

- **In scope for this PR**: N2C resolver session (`--n2c-socket` + `--network-magic`); the chain has exactly one resolver in this PR.
- **Deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21)**: the Blockfrost resolver session, the `--blockfrost-base` + `--blockfrost-key` flags + `BLOCKFROST_PROJECT_ID` env-var support, the chained-fallback UX (Story 3 below was about chaining N2C + Blockfrost — without a second resolver in v1 it is reduced to "only N2C is supported").

The original FRs and success criteria below are kept; each is annotated with its destination.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Signing daemon catches a structural tx bug before submission (Priority: P1)

A signing pipeline has just received an unsigned Conway transaction from a builder (e.g. `amaru-treasury-tx`). Before paying the signing or submission cost, the pipeline runs `tx-validate` against a local `cardano-node` socket. If the tx is structurally clean, `tx-validate` exits successfully; if a real Phase-1 problem is present (integrity hash mismatch, fee too small, missing collateral, validity interval failure, …), `tx-validate` exits non-zero and the pipeline halts with the ledger's failure verbatim.

**Why this priority**: this is the contract the library was added for. Without an executable surface, every consumer reimplements the same glue.

**Independent Test**: feed `tx-validate` the committed issue-#8 reproduction (post-fix body) against a `pparams.json` snapshot and a producer-tx UTxO. Expect exit 0 and a single human verdict line. Feed it the pre-fix variant; expect exit 1 and a structural failure printed.

**Acceptance Scenarios**:

1. **Given** a structurally-clean unsigned Conway tx on disk, **When** the user runs `tx-validate --input tx.cbor.hex --n2c-socket /path/to/node.socket --network-magic 764824073`, **Then** the executable prints a one-line human verdict ("structurally clean: N expected witness-completeness failures filtered"), exits 0, and produces no other stdout output.
2. **Given** a tx with a structural failure (e.g. integrity-hash mismatch), **When** the user runs `tx-validate` with the same flags, **Then** the executable prints the verdict line **plus** the structural failures (one per line, with the rule name and the ledger's failure constructor + payload), exits 1, and witness-completeness noise is omitted from the output.
3. **Given** the same tx but the user passes `--output json`, **When** the executable runs, **Then** stdout contains a single JSON envelope with `{status, structural_failures, witness_completeness_count, pparams_source, slot_source, utxo_sources}` and the exit code matches the structural status as in (2).

---

### User Story 2 *(deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))* — CI gate validates a treasury transaction against Blockfrost (Priority: P1)

A CI job builds a treasury transaction (e.g. via `amaru-treasury-tx`), then runs `tx-validate` against the public Blockfrost mainnet endpoint instead of a local node. The job has the `project_id` API key in an environment variable. The executable fetches `PParams`, the tip slot, and the UTxO for the tx's inputs from Blockfrost, runs `validatePhase1`, and exits 0 iff the tx is structurally clean.

Out of scope for this PR per the "Scope adjustment" above.

---

### User Story 3 *(deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))* — Developer chains N2C-first, Blockfrost-fallback for resilience (Priority: P2)

Out of scope for this PR: the chain has exactly one resolver (N2C) until [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21) lands.

---

### Edge Cases

- **No resolver supplied**: the user runs `tx-validate --input tx.cbor.hex` without `--n2c-socket`. The executable exits non-zero with a usage message saying the N2C socket flag is required.
- **`--output` value other than `human` / `json`**: the executable exits non-zero with a usage message.
- **Tx CBOR decode failure**: `tx-validate` exits with a `decode-failed` error code, prints the decoder's verbatim message to stderr; the verdict line is NOT printed (we have no tx to validate against).
- **Mempool short-circuit (zero of the tx's inputs are in the resolved UTxO)**: same behaviour as the library — Phase-1 returns the mempool duplicate-detection failure. `tx-validate` prints the verdict and exits 1 with that failure on stdout (human) or in `structural_failures` (json).
- **`--input -` (stdin)**: reads from stdin. Symmetry with `tx-diff`'s `-` convention.
- **Empty input file**: exits with `decode-failed`.
- **Default-offline test discipline (constitution VI)**: the test suite for this feature runs without network. The N2C path is exercised by a mock `Provider` in tests.
- **Network access is opt-in (constitution VI)**: the executable performs N2C calls only when its CLI flags ask for them; there is no environment-only fallback that could surprise an offline caller.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** *(in scope)*: A new executable named `tx-validate` MUST live under `app/tx-validate/`. It MUST be a thin Main wrapper over a public `Cardano.Tx.Validate.Cli` module that handles argument parsing and the resolver-session lifecycle.

- **FR-002** *(in scope, reduced to N2C-only)*: The CLI MUST accept the following flags:

    - `--input PATH | -` (required): path to a Conway tx CBOR hex file, or `-` for stdin.
    - `--n2c-socket PATH` (required): path to a local `cardano-node` Node-to-Client socket.
    - `--network-magic WORD32`: network magic for the supplied socket (defaults to mainnet `764824073`).
    - `--output human|json` (default `human`): output format.
    - `--help`: print usage.

    Blockfrost flags (`--blockfrost-base`, `--blockfrost-key`) deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).

- **FR-003** *(in scope, reduced)*: The CLI MUST resolve the UTxO needed for `validatePhase1` via the N2C resolver (`Cardano.Tx.Diff.Resolver.N2C.n2cResolver`). The input set passed to the resolver MUST be the union of the tx body's `inputsTxBodyL`, `referenceInputsTxBodyL`, and `collateralInputsTxBodyL`.

- **FR-004** *(deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))*: Multi-resolver session and "first on the command line wins" primary-session contract. With one resolver in v1, this is degenerate (N2C is always the primary).

- **FR-005** *(in scope)*: For the N2C session, `PParams` is queried via `Cardano.Node.Client.Provider.queryProtocolParams` and the tip slot via `queryLedgerSnapshot`'s `ledgerTipSlot`; these are the same code paths `amaru-treasury-tx`'s `liveContext` uses.

- **FR-006** *(deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21))*: Blockfrost session fetching `PParams` from `/epochs/latest/parameters` and slot from `/blocks/latest`. The schema mismatch documented in "Scope adjustment" pushes this out.

- **FR-007** *(in scope, simplified)*: Output formats:

    - **human** (default): one verdict line on stdout, followed by one structural-failure line per failure if any. Witness-completeness failures are NOT printed; they are summarised in the verdict line as a count (e.g. "2 witness-completeness failures filtered"). Exit 0 if structurally clean (no failures after filtering); exit 1 if structural failures present; exit ≥2 for resolver / decode / configuration errors.
    - **json**: one JSON object on stdout matching the schema in the contracts file. The exit code is the same as `human`.

- **FR-008** *(in scope)*: All stderr output MUST be diagnostic, not part of the contract. Examples: per-input resolver trace (which resolver resolved which TxIn), resolution failures with `<txId>#<ix>`, N2C handshake errors.

- **FR-009** *(in scope)*: The executable MUST be packaged into the release pipeline alongside `tx-diff` and `cardano-tx-generator`, producing the same artefacts: AppImage / DEB / RPM (Linux x86_64), Darwin bottles (x86_64 + aarch64 via the existing Homebrew tap), and a Docker image. The release-please configuration MUST recognise it (`feat:` ↔ minor bump, etc.).

- **FR-010** *(in scope, simplified)*: The Haddock for `Cardano.Tx.Validate.Cli` MUST document the resolver-session contract (in v1: a single N2C session supplies `PParams` + slot + UTxO; the chained-fallback UX is future work tracked in [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21)) and the exit-code convention (0 / 1 / ≥2).

- **FR-011** *(in scope)*: The test suite for this feature MUST run with no network access (constitution VI). N2C tests use a mock `Provider`-shaped record.

- **FR-012** *(in scope)*: The work MUST NOT regress any existing passing test in `nix flake check` on `main`.

### Key Entities

- **`tx-validate` executable**: the new CLI surface.
- **`Cardano.Tx.Validate.Cli` module**: public-library module that holds the CLI parser, the N2C session lifecycle, the verdict-printing logic.
- **N2C session**: the source of `PParams` + slot + UTxO for one invocation, configured by the user's `--n2c-socket` + `--network-magic` flags.
- **Structural failure**: a `ConwayLedgerPredFailure` that is NOT recognised as witness-completeness noise by the existing `Cardano.Tx.Validate.isWitnessCompletenessFailure` helper.
- **Verdict line**: a single human-readable line on stdout summarising the validation outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** *(in scope)*: A signing pipeline can invoke `tx-validate` and act on the exit code without parsing stdout. Exit 0 ⇔ structurally clean; exit 1 ⇔ structural failure; exit ≥2 ⇔ configuration / resolver / decode error.
- **SC-002** *(in scope, reduced)*: The post-fix issue-#8 fixture (the one PR #16's library test already accepts) validates green through `tx-validate` against the N2C path — either via a mock `Provider` in tests or via a live local-node socket on a synced mainnet host. Live Blockfrost path deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).
- **SC-003** *(in scope, reduced)*: The pre-fix issue-#8 fixture (with the bad integrity hash) returns exit 1 from `tx-validate` against the N2C source, and the verdict + JSON envelope both name `ScriptIntegrityHashMismatch` (or its older variant) as a structural failure.
- **SC-004** *(in scope)*: A grep across consumer codebases (`amaru-treasury-tx`, future signing daemons) finds zero hand-rolled `applyTx`-shaped Phase-1 gates added after this PR merges. (Closes the SC-006 ambition from spec 014.)
- **SC-005** *(in scope)*: `nix flake check` passes green on the branch.
- **SC-006** *(in scope)*: The release pipeline produces and uploads `tx-validate` AppImage / DEB / RPM / Darwin / Homebrew / Docker artefacts on the next tag after this PR merges.
- **SC-007** *(in scope, reduced)*: A first-time user with the documentation tab open can validate a tx against a local cardano-node in a single invocation, without reading any code.

## Assumptions

- The existing `Cardano.Tx.Diff.Resolver` + `Cardano.Tx.Diff.Resolver.N2C` modules cover the UTxO resolution surface this PR needs. They are re-used as-is. If the namespace becomes an irritant for downstream consumers (a non-diff caller importing `Diff.Resolver`), the rename to `Cardano.Tx.Resolver.*` is a separate ticket.
- `cardano-node-clients` exposes `Provider.queryProtocolParams` and `queryLedgerSnapshot` returning a snapshot whose tip slot can be read via `ledgerTipSlot`. These are the calls `amaru-treasury-tx`'s `liveContext` makes.
- The CLI's exit-code convention (0/1/≥2) is documented in `--help`; we do not invent a finer-grained code per error class — `≥2` is just "not a verdict, something else went wrong."
- The new module lives under `Cardano.Tx.Validate.Cli` (extending the namespace from PR #16). The executable lives at `app/tx-validate/Main.hs`.
- Mainnet network magic is the default. Testnet (preprod/preview/devnet) requires explicit `--network-magic`.

## Out of Scope

- **Blockfrost resolver session** — deferred to [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21). Blockfrost's `/epochs/latest/parameters` schema mismatch with `cardano-ledger-conway`'s `FromJSON (PParams ConwayEra)` instance forces a custom decoder; that work lives in the follow-up.
- Multi-resolver chain UX with first-on-the-command-line primary-session rules — same reason; falls out when there's only one resolver.
- Renaming `Cardano.Tx.Diff.Resolver.*` to a non-diff namespace. Out of scope; separate ticket once a second consumer materialises.
- A `tx-validate-server` daemon that serves validation over HTTP. Out of scope; standalone CLI for now.
- Signing or submission. `tx-validate` is read-only by design; the executable never opens an LTxS channel.
- Phase-2 (Plutus script execution) validation. Library-side `validatePhase1` doesn't cover it and this CLI doesn't either.
- Non-Conway eras (constitution III).
- Auto-resolution of producer-tx CBORs as a substitute for live UTxO. The executable does NOT read producer-tx CBOR files; that's a test-only helper from spec 014's `LoadUtxo`. CLI callers always go through a live N2C source.

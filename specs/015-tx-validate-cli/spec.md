# Feature Specification: tx-validate CLI

**Feature Branch**: `015-tx-validate-cli`
**Created**: 2026-05-16
**Status**: Draft — awaiting user approval before `/speckit.plan`
**Input**: User request after [PR #16](https://github.com/lambdasistemi/cardano-tx-tools/pull/16) ("validatePhase1") shipped: provide a new `tx-validate` executable that wraps the library function, driven by either N2C (against a local `cardano-node`) or a Blockfrost-compatible HTTP endpoint, with the resolver session also supplying the protocol parameters and the tip slot.
**Predecessor**: [spec 014](../014-validate-phase1/spec.md) / [PR #16](https://github.com/lambdasistemi/cardano-tx-tools/pull/16) — landed the library function `Cardano.Tx.Validate.validatePhase1`.

## Background

`validatePhase1` is a pure Haskell function: `Network -> PParamsBound -> [(TxIn, TxOut ConwayEra)] -> SlotNo -> ConwayTx -> Either (ApplyTxError ConwayEra) ()`. To use it from a shell or signing pipeline (e.g. `amaru-treasury-tx`, signing daemons, CI gates) the caller currently has to write Haskell to resolve the UTxO, fetch the `PParams`, pick a slot, then call the function. Repeating that glue in every consumer is exactly what
[spec 014's SC-006](../014-validate-phase1/spec.md#measurable-outcomes) said the library should make unnecessary.

This spec covers the missing executable surface: a CLI that takes a Conway transaction as input, resolves the world it needs (UTxO + `PParams` + tip slot) from a single configured **resolver session** (N2C or Blockfrost), runs `validatePhase1`, and reports the verdict.

The CLI mirrors the existing `tx-diff` and `cardano-tx-generator` executables in shape, build pipeline, and release artefacts.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Signing daemon catches a structural tx bug before submission (Priority: P1)

A signing pipeline has just received an unsigned Conway transaction from a builder (e.g. `amaru-treasury-tx`). Before paying the signing or submission cost, the pipeline runs `tx-validate` against a local `cardano-node` socket. If the tx is structurally clean, `tx-validate` exits successfully; if a real Phase-1 problem is present (integrity hash mismatch, fee too small, missing collateral, validity interval failure, …), `tx-validate` exits non-zero and the pipeline halts with the ledger's failure verbatim.

**Why this priority**: this is the contract the library was added for. Without an executable surface, every consumer reimplements the same glue.

**Independent Test**: feed `tx-validate` the committed issue-#8 reproduction (post-fix body) against a `pparams.json` snapshot and a producer-tx UTxO. Expect exit 0 and a single human verdict line. Feed it the pre-fix variant; expect exit 1 and a structural failure printed.

**Acceptance Scenarios**:

1. **Given** a structurally-clean unsigned Conway tx on disk, **When** the user runs `tx-validate --input tx.cbor.hex --n2c-socket /path/to/node.socket --network-magic 764824073`, **Then** the executable prints a one-line human verdict ("structurally clean: N expected witness-completeness failures filtered"), exits 0, and produces no other stdout output.
2. **Given** a tx with a structural failure (e.g. integrity-hash mismatch), **When** the user runs `tx-validate` with the same flags, **Then** the executable prints the verdict line **plus** the structural failures (one per line, with the rule name and the ledger's failure constructor + payload), exits 1, and witness-completeness noise is omitted from the output.
3. **Given** the same tx but the user passes `--output json`, **When** the executable runs, **Then** stdout contains a single JSON envelope with `{status, structural_failures, witness_completeness_count, pparams_source, slot_source, utxo_source}` and the exit code matches the structural status as in (2).

---

### User Story 2 — CI gate validates a treasury transaction against Blockfrost (Priority: P1)

A CI job builds a treasury transaction (e.g. via `amaru-treasury-tx`), then runs `tx-validate` against the public Blockfrost mainnet endpoint instead of a local node. The job has the `project_id` API key in an environment variable. The executable fetches `PParams`, the tip slot, and the UTxO for the tx's inputs from Blockfrost, runs `validatePhase1`, and exits 0 iff the tx is structurally clean.

**Why this priority**: makes the executable usable without a local cardano-node — same usefulness for short-lived CI runs and for anyone without a synced node.

**Independent Test**: against the public Blockfrost mainnet API with a valid `project_id`, validate the committed issue-#8 fixture; expect the same verdict as User Story 1's local-N2C path.

**Acceptance Scenarios**:

1. **Given** a Conway tx on disk and `BLOCKFROST_PROJECT_ID` set in the environment, **When** the user runs `tx-validate --input tx.cbor.hex --blockfrost-base https://cardano-mainnet.blockfrost.io/api/v0`, **Then** the executable picks up the API key from the env, fetches the session data from Blockfrost, runs validation, and produces the same shape of output as Story 1.
2. **Given** the API key is missing (no env var and no `--blockfrost-key` flag), **When** the user runs `tx-validate` with `--blockfrost-base`, **Then** the executable exits non-zero with a single stderr line saying the key is required and where it expects it.
3. **Given** the Blockfrost endpoint returns a 404 for one of the tx's inputs (a UTxO that's been spent / pruned), **When** the executable runs, **Then** stderr lists the unresolved inputs by `<txId>#<ix>` and the executable exits non-zero with a recognisable error (a UTxO resolution failure, not a Phase-1 failure).

---

### User Story 3 — Developer chains N2C-first, Blockfrost-fallback for resilience (Priority: P2)

A developer's local node is partially synced; they want `tx-validate` to try the local node for UTxO first and fall back to Blockfrost for the entries the node can't resolve, with `PParams` + tip slot pinned to the first session that produces them. This matches the existing `tx-diff` resolver-chain UX.

**Why this priority**: small enhancement; the resolver chain semantics already exist in the codebase. Locking the UX as part of this PR keeps the executable consistent with the rest of the toolkit.

**Independent Test**: with a deliberately-incomplete local node (e.g. a snapshot from a few slots back), run `tx-validate` with both `--n2c-socket` and `--blockfrost-base` flags. The executable resolves what it can locally, falls back to Blockfrost for the rest, prints one-line resolver-trace diagnostics to stderr, and reports the validation verdict as if the union of sources had been queried.

**Acceptance Scenarios**:

1. **Given** both `--n2c-socket` and `--blockfrost-base` flags supplied, **When** the executable runs, **Then** N2C is tried first for each input; remaining inputs go to Blockfrost; the resolver-chain trace lists, per still-unresolved input, the resolver names that were tried.
2. **Given** N2C resolves 3 of 4 inputs and Blockfrost resolves the 4th, **When** validation runs, **Then** the verdict reflects the full UTxO (no false short-circuit) and the resolver trace logs the per-input decisions to stderr.

---

### Edge Cases

- **No resolver supplied**: the user runs `tx-validate --input tx.cbor.hex` without `--n2c-socket` or `--blockfrost-base`. The executable exits non-zero with a usage message saying at least one resolver is required.
- **Both resolvers supplied for the session data (`PParams` + slot)**: the **first** configured source on the command line wins; the second is used for UTxO fallback only. Documented in `--help`.
- **`--output` value other than `human` / `json`**: the executable exits non-zero with a usage message.
- **Tx CBOR decode failure**: `tx-validate` exits with a `decode-failed` error code, prints the decoder's verbatim message to stderr; the verdict line is NOT printed (we have no tx to validate against).
- **Mempool short-circuit (zero of the tx's inputs are in the resolved UTxO)**: same behaviour as the library — Phase-1 returns the mempool duplicate-detection failure. `tx-validate` prints the verdict and exits 1 with that failure on stdout (human) or in `structural_failures` (json).
- **`--input -` (stdin)**: reads from stdin. Symmetry with `tx-diff`'s `-` convention.
- **Empty input file**: exits with `decode-failed`.
- **Default-offline test discipline (constitution VI)**: the test suite for this feature runs without network. Live N2C / Blockfrost paths are exercised by a separate optional smoke test (or, ideally, by `nix flake check` with a faked HTTP layer).
- **Network access is opt-in (constitution VI)**: the executable performs HTTP/N2C calls only when its CLI flags ask for them; there is no environment-only fallback that could surprise an offline caller.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A new executable named `tx-validate` MUST live under `app/tx-validate/`. It MUST be a thin Main wrapper over a public `Cardano.Tx.Validate.Cli` module that handles argument parsing and the resolver-session lifecycle.

- **FR-002**: The CLI MUST accept the following flags:

    - `--input PATH | -` (required): path to a Conway tx CBOR hex file, or `-` for stdin.
    - `--n2c-socket PATH`: path to a local `cardano-node` Node-to-Client socket; enables the N2C resolver.
    - `--network-magic WORD32`: network magic for the supplied socket (defaults to mainnet `764824073`).
    - `--blockfrost-base URL`: base URL for a Blockfrost-style HTTP endpoint; enables the Web2 resolver.
    - `--blockfrost-key STRING`: API key; default sourced from `BLOCKFROST_PROJECT_ID` env var; required if `--blockfrost-base` is set and the env var is absent.
    - `--output human|json` (default `human`): output format.
    - `--help`: print usage.

    At least one of `--n2c-socket` or `--blockfrost-base` MUST be supplied.

- **FR-003**: The CLI MUST resolve the UTxO needed for `validatePhase1` from the configured resolver chain (`Cardano.Tx.Diff.Resolver` semantics; see PR #3 / PR #5 for that infrastructure). The input set passed to the chain MUST be the union of the tx body's `inputsTxBodyL`, `referenceInputsTxBodyL`, and `collateralInputsTxBodyL`. The chain order MUST be: N2C first if supplied, then Blockfrost.

- **FR-004**: The CLI MUST source the `PParams` and the tip `SlotNo` from a single primary resolver session — whichever of `--n2c-socket` / `--blockfrost-base` came first on the command line — and MUST NOT mix sources for these two values across resolvers. The UTxO chain MAY mix sources (FR-003).

- **FR-005**: For an N2C primary session, `PParams` is queried via `Cardano.Node.Client.Provider.queryProtocolParams` and the tip slot via `queryLedgerSnapshot`'s `ledgerTipSlot`; these are the same code paths `amaru-treasury-tx`'s `liveContext` uses.

- **FR-006**: For a Blockfrost primary session, `PParams` is fetched from `GET <base>/epochs/latest/parameters` (decoded into `PParams ConwayEra`) and the tip slot from `GET <base>/blocks/latest` (`slot` field).

- **FR-007**: Output formats:

    - **human** (default): one verdict line on stdout, followed by one structural-failure line per failure if any. Witness-completeness failures are NOT printed; they are summarised in the verdict line as a count (e.g. "2 witness-completeness failures filtered"). Exit 0 if structurally clean (no failures after filtering); exit 1 if structural failures present; exit ≥2 for resolver / decode / configuration errors.
    - **json**: one JSON object on stdout matching the schema in the contracts file. The exit code is the same as `human`.

- **FR-008**: All stderr output MUST be diagnostic, not part of the contract. Examples: per-input resolver trace (which resolver resolved which TxIn), resolution failures with `<txId>#<ix>`, HTTP errors with redacted query-string secrets.

- **FR-009**: The executable MUST be packaged into the release pipeline alongside `tx-diff` and `cardano-tx-generator`, producing the same artefacts: AppImage / DEB / RPM (Linux x86_64), Darwin bottles (x86_64 + aarch64 via the existing Homebrew tap), and a Docker image. The release-please configuration MUST recognise it (`feat:` ↔ minor bump, etc.).

- **FR-010**: The Haddock for `Cardano.Tx.Validate.Cli` MUST document the resolver-session contract (primary session wins for `PParams` + slot; UTxO chain is union with primary-first ordering) and the exit-code convention (0 / 1 / ≥2).

- **FR-011**: The test suite for this feature MUST run with no network access (constitution VI). HTTP requests in tests MUST be intercepted by a stub. N2C tests use the existing N2C-mock infrastructure that `tx-diff` already relies on (see `Cardano.Tx.Diff.Resolver.N2C` tests).

- **FR-012**: The work MUST NOT regress any existing passing test in `nix flake check` on `main`.

### Key Entities

- **`tx-validate` executable**: the new CLI surface.
- **`Cardano.Tx.Validate.Cli` module**: public-library module that holds the CLI parser, the resolver-session lifecycle, the verdict-printing logic.
- **Resolver session**: the term for "the source of `PParams` + slot + UTxO for one invocation." Configured by the user's flags. The primary session is fixed by the first source on the command line; the secondary, if any, only contributes to UTxO resolution.
- **Structural failure**: a `ConwayLedgerPredFailure` that is NOT recognised as witness-completeness noise by the existing `Cardano.Tx.Validate.isWitnessCompletenessFailure` helper.
- **Verdict line**: a single human-readable line on stdout summarising the validation outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A signing pipeline can invoke `tx-validate` and act on the exit code without parsing stdout. Exit 0 ⇔ structurally clean; exit 1 ⇔ structural failure; exit ≥2 ⇔ configuration / resolver / decode error.
- **SC-002**: The post-fix issue-#8 fixture (the one PR #16's library test already accepts) validates green through `tx-validate` against any of: (a) committed `pparams.json` + producer-tx CBORs via N2C-mock, (b) live N2C against a synced mainnet node, (c) live Blockfrost mainnet. All three return exit 0.
- **SC-003**: The pre-fix issue-#8 fixture (with the bad integrity hash) returns exit 1 from `tx-validate` against any of the three sources in SC-002, and the verdict + JSON envelope both name `ScriptIntegrityHashMismatch` (or its older variant) as a structural failure.
- **SC-004**: A grep across consumer codebases (`amaru-treasury-tx`, future signing daemons) finds zero hand-rolled `applyTx`-shaped Phase-1 gates added after this PR merges. (Closes the SC-006 ambition from spec 014.)
- **SC-005**: `nix flake check` passes green on the branch.
- **SC-006**: The release pipeline produces and uploads `tx-validate` AppImage / DEB / RPM / Darwin / Homebrew / Docker artefacts on the next tag after this PR merges.
- **SC-007**: A first-time user with the documentation tab open can validate a tx against Blockfrost in a single invocation, with `BLOCKFROST_PROJECT_ID` set in their shell, without reading any code.

## Assumptions

- The existing `Cardano.Tx.Diff.Resolver`, `Cardano.Tx.Diff.Resolver.N2C`, and `Cardano.Tx.Diff.Resolver.Web2` modules cover the UTxO resolution surface this feature needs. They are re-used as-is. If the namespace becomes an irritant for downstream consumers (a non-diff caller importing `Diff.Resolver`), the rename to `Cardano.Tx.Resolver.*` is a separate ticket.
- `cardano-node-clients` exposes `Provider.queryProtocolParams` and `queryLedgerSnapshot` returning a snapshot whose tip slot can be read via `ledgerTipSlot`. These are the calls `amaru-treasury-tx`'s `liveContext` makes.
- Blockfrost's `/epochs/latest/parameters` returns a JSON object whose Aeson decoder produces a valid `PParams ConwayEra` for Conway. If a field shifts in a future Conway-era parameters schema, the executable surfaces it as a configuration error with a clear "schema drift" message; bumping `cardano-ledger-conway` to track the schema is a follow-up.
- The CLI's exit-code convention (0/1/≥2) is documented in `--help`; we do not invent a finer-grained code per error class — `≥2` is just "not a verdict, something else went wrong."
- The new module lives under `Cardano.Tx.Validate.Cli` (extending the namespace from PR #16). The executable lives at `app/tx-validate/Main.hs`.
- Mainnet network magic is the default. Testnet (preprod/preview/devnet) requires explicit `--network-magic`.

## Out of Scope

- Renaming `Cardano.Tx.Diff.Resolver.*` to a non-diff namespace. Out of scope; separate ticket once a second consumer materialises.
- A `tx-validate-server` daemon that serves validation over HTTP. Out of scope; standalone CLI for now.
- Signing or submission. `tx-validate` is read-only by design; the executable never opens an LTxS channel.
- Phase-2 (Plutus script execution) validation. Library-side `validatePhase1` doesn't cover it and this CLI doesn't either.
- Non-Conway eras (constitution III).
- Auto-resolution of producer-tx CBORs as a substitute for live UTxO. The executable does NOT read producer-tx CBOR files; that's a test-only helper from spec 014's `LoadUtxo`. CLI callers always go through a live or HTTP source.
- Caching / batching of Blockfrost queries beyond what the existing Web2 resolver already does. Performance tuning is out of scope; if it bites in production we file a follow-up.

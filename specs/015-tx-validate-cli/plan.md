# Implementation Plan: tx-validate CLI

**Branch**: `015-tx-validate-cli` | **Date**: 2026-05-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/015-tx-validate-cli/spec.md`

## Summary

Add a `tx-validate` executable that wraps `Cardano.Tx.Validate.validatePhase1`
behind a CLI mirroring the existing `tx-diff` / `cardano-tx-generator` pattern.
Drive validation via a **resolver session** that supplies `PParams` + tip slot
from the first source on the command line, and resolves the tx's UTxO via the
existing `Cardano.Tx.Diff.Resolver` chain (N2C-first, then Blockfrost). Output
is either human (verdict + structural failures, one per line) or a JSON
envelope, switchable via `--output`. Exit codes are `0` (structurally clean),
`1` (structural failure), `≥2` (configuration / resolver / decode error).

Ship release artefacts (AppImage / DEB / RPM / Darwin / Homebrew / Docker) on
day 1 alongside `tx-diff` and `cardano-tx-generator`.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (constitution Operational Constraints).
**Primary Dependencies**:

- `cardano-tx-tools` library (for `validatePhase1` + `isWitnessCompletenessFailure`).
- `cardano-tx-tools:n2c-resolver` (existing) — `Cardano.Tx.Diff.Resolver.N2C.n2cResolver`.
- `Cardano.Tx.Diff.Resolver` + `.Web2` from the main library (already in scope).
- `cardano-node-clients`'s `Provider` for the N2C primary session: `queryProtocolParams`, `queryUTxOByTxIn`, `queryLedgerSnapshot` (`ledgerTipSlot`).
- `http-client` + `http-client-tls` for the Blockfrost primary session (same `Manager` the `Web2` resolver already builds).
- `aeson` for the JSON output envelope and for decoding Blockfrost's `/epochs/latest/parameters` + `/blocks/latest`.
- `optparse-applicative` for the argument parser (same library `tx-diff` uses).

**Storage**: N/A. The executable is a request/response shell over the live resolver session.

**Testing**: `hspec` via a new `tx-validate-tests` test-suite (mirrors `tx-generator-tests` shape). Live N2C / Blockfrost are NOT exercised at test time (constitution VI); HTTP requests are stubbed via the `Web2FetchTx`-shaped record-of-functions abstraction the resolver already exposes, and N2C tests use the same mock provider `tx-diff`'s unit tests reuse.

**Target Platform**: `nix flake check` on `x86_64-linux`; Darwin path covered via the existing Homebrew bundler. The release pipeline produces Linux + Darwin artefacts.

**Project Type**: Single Haskell library + executable (`app/tx-validate/`).

**Performance Goals**: Not load-bearing. Most of the wall-clock is the N2C / Blockfrost round-trip; the validation step is one ledger STS evaluation.

**Constraints**: Default-offline test discipline (constitution VI); HTTPS at runtime via the existing CA-cert wrapper pattern (`pkgs.makeWrapper` + `pkgs.cacert`).

**Scale/Scope**: One new module (`Cardano.Tx.Validate.Cli`), one new executable (`app/tx-validate/Main.hs`), one new test-suite. ~300 LOC of new code spread across parser + session lifecycle + verdict-printing + tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. One-Way Dependency On Node-Clients | ✅ | The N2C glue lives in the existing `Cardano.Tx.Diff.Resolver.N2C` sublibrary, which already imports `cardano-node-clients`. `Cardano.Tx.Validate.Cli` itself does NOT import `cardano-node-clients`; it consumes `Provider` only via the resolver chain, keeping the main library Node-Clients-free. |
| II. Module Namespace Discipline | ✅ | New module is `Cardano.Tx.Validate.Cli`. Executable is `tx-validate` under `app/tx-validate/`. No `Cardano.Node.Client.*` introduced. |
| III. Conway-Only Era | ✅ | Reuses `ConwayTx` from spec 014; the JSON output schema names Conway-era failure constructors. No multi-era widening. |
| IV. Hackage-Ready Quality | ✅ | New module ships with Haddock; the `werror` flag covers the executable + sublibrary too. `cabal check` keeps passing because the new dep list is the union of existing deps + `optparse-applicative` (already present elsewhere). |
| V. Strict Warnings | ✅ | New stanzas inherit `import: warnings`. |
| VI. Default-Offline Semantics | ✅ | The executable performs HTTP / N2C **only** when its CLI flags ask for it. No environment-only fallback. Tests run without network; HTTP is stubbed; N2C uses the existing mock provider. |
| VII. TDD With Vertical Bisect-Safe Commits | ✅ | One commit per behavior slice (parser, session-driver, verdict-printer, release-plumbing). RED + GREEN folded per commit. |
| Resolver Architecture (Operational) | ✅ | This feature consumes the existing `Resolver` chain unchanged. It does NOT add a new resolver type; it adds a *session driver* that owns one of the chain's resolvers for the primary-session role (PParams + slot). |

No violations to track in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/015-tx-validate-cli/
├── plan.md              # This file
├── research.md          # Phase 0 output (this command)
├── data-model.md        # Phase 1 output (this command)
├── quickstart.md        # Phase 1 output (this command)
├── contracts/
│   ├── cli.md           # CLI flag contract + exit-code convention
│   └── json-output.md   # JSON envelope schema
├── checklists/
│   └── requirements.md  # Created during /speckit.specify
├── spec.md              # /speckit.specify output
└── tasks.md             # /speckit.tasks output (NOT created here)
```

### Source Code (repository root)

```text
src/Cardano/Tx/Validate/
├── Cli.hs                       # NEW — argument parser, session driver,
│                                 # verdict printer (human + JSON)
└── (Validate.hs unchanged)

app/tx-validate/
└── Main.hs                      # NEW — thin entry over Cli

test/
└── Cardano/Tx/Validate/
    └── CliSpec.hs               # NEW — argument-parsing, output-shape,
                                  # mocked-N2C-and-HTTP coverage

nix/
└── (linux-release.nix unchanged)

flake.nix                        # MODIFIED — add txValidate wrapper +
                                  # mkTxValidateDarwinHomebrewBundle +
                                  # tx-validate-linux-release-artifacts +
                                  # tx-validate Docker image +
                                  # apps.tx-validate
cardano-tx-tools.cabal           # MODIFIED — register new module +
                                  # new executable stanza + new
                                  # test-suite stanza
```

**Structure Decision**: a new module + a new executable + a new test-suite. The existing resolver / n2c-resolver / web2-resolver surface is unchanged. The Phase-1 library function from spec 014 is unchanged.

## Phase 0 — Research

Eight unknowns to resolve; full discussion in [research.md](./research.md):

1. **`Provider` accessors for `PParams` + tip slot at the pinned `cardano-node-clients`** — confirm `queryProtocolParams`, `queryLedgerSnapshot`, `ledgerTipSlot` are exposed. Inspector and `amaru-treasury-tx` use them; we re-verify against the SRP pin currently in `cabal.project`.
2. **Blockfrost `/epochs/latest/parameters` JSON shape** — confirm Aeson decoding into `PParams ConwayEra` via the existing `FromJSON` instance.
3. **Blockfrost `/blocks/latest` JSON shape** — confirm the `slot` field is a number.
4. **`Web2FetchTx`-shaped abstraction for the new HTTP endpoints** — decide whether the new `/epochs/latest/parameters` + `/blocks/latest` fetchers live alongside `httpFetchTx` in `Cardano.Tx.Diff.Resolver.Web2` or in a new `Cardano.Tx.Validate.Cli.Blockfrost` test-friendly record. Recommendation: latter (keeps Validate.Cli's tests independent of Diff's HTTP stubs).
5. **Primary-session lifecycle** — for N2C: `withLocalNodeBackend`-shaped bracket (LSQ + LTxS mux). For Blockfrost: stateless `Manager`. Decision: a `data SessionDriver = SessionDriver { withSession :: forall a. (Session -> IO a) -> IO a }` that the parser produces from the primary `--n2c-socket` or `--blockfrost-base` choice.
6. **Resolver chain ordering** — the existing `resolveChain :: [Resolver] -> Set TxIn -> IO (Map TxIn (TxOut), Map TxIn [Text])` does what we need verbatim; we just supply the chain `[n2cResolver, web2Resolver]` (with each entry present only if its flag was supplied).
7. **JSON output schema stability** — decide the envelope shape. The spec's FR-007 names the top-level keys; [contracts/json-output.md](./contracts/json-output.md) pins them.
8. **Day-1 release plumbing** — symlink-join with `pkgs.makeWrapper` (HTTPS CA cert), Linux release-artefacts via `nix/linux-release.nix`, Darwin Homebrew bundle via `mkDarwinHomebrewBundle`, Docker image via `nix/docker-image.nix`.

## Phase 1 — Design & Contracts

### CLI surface (FR-002)

See [contracts/cli.md](./contracts/cli.md). The parser is built on `optparse-applicative` (same library as `tx-diff`); the option model is:

```haskell
data TxValidateCliOptions = TxValidateCliOptions
    { txValidateCliInput   :: InputSource          -- PATH or stdin
    , txValidateCliN2c     :: Maybe N2cConfig      -- enable N2C resolver
    , txValidateCliWeb2    :: Maybe Web2Config     -- enable Web2 resolver
    , txValidateCliOutput  :: OutputFormat         -- Human | Json
    , txValidateCliPrimary :: PrimarySession       -- which one came first
    }

data InputSource     = InputFile FilePath | InputStdin
data OutputFormat    = Human | Json
data PrimarySession  = PrimaryN2c | PrimaryWeb2
data N2cConfig       = N2cConfig { socket :: FilePath, magic :: NetworkMagic }
data Web2Config      = Web2Config { base :: Text, apiKey :: Maybe Text }
```

The parser keeps the original `argv` so the primary-session winner is positional. (FR-004's "first on the command line" requirement is a positional contract, not a precedence rule, so we resolve it at parse time.)

### JSON envelope (FR-007)

See [contracts/json-output.md](./contracts/json-output.md). Top-level:

```json
{
  "status": "structurally_clean" | "structural_failure" | "mempool_short_circuit",
  "exit_code": 0 | 1,
  "structural_failures": [
    { "rule": "UTXOW", "constructor": "ScriptIntegrityHashMismatch", "detail": "…" }
  ],
  "witness_completeness_count": 2,
  "pparams_source": "n2c" | "blockfrost",
  "slot_source": "n2c" | "blockfrost",
  "utxo_sources": { "<txId>#<ix>": "n2c" | "blockfrost" }
}
```

### Data model

See [data-model.md](./data-model.md). Three new typed surfaces — all in `Cardano.Tx.Validate.Cli`:

- `TxValidateCliOptions` (option record from the parser)
- `Session` (carries primary-source `PParams` + slot + resolver chain handle)
- `Verdict` (the typed verdict before it's rendered to human / JSON)

### Quickstart

See [quickstart.md](./quickstart.md). Three invocation patterns:

1. **Local N2C**: `tx-validate --input tx.cbor.hex --n2c-socket ~/.cardano-node/socket --network-magic 764824073`
2. **Blockfrost**: `BLOCKFROST_PROJECT_ID=… tx-validate --input tx.cbor.hex --blockfrost-base https://cardano-mainnet.blockfrost.io/api/v0`
3. **Chained**: both flags; first on the command line wins for `PParams` + slot.

### Agent context update

Will run `.specify/scripts/bash/update-agent-context.sh claude` after this plan lands to refresh `CLAUDE.md`.

## Complexity Tracking

None. Constitution Check passes outright.

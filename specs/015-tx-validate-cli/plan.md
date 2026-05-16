# Implementation Plan: tx-validate CLI

**Branch**: `015-tx-validate-cli` | **Date**: 2026-05-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/015-tx-validate-cli/spec.md`

## Summary

Add a `tx-validate` executable that wraps `Cardano.Tx.Validate.validatePhase1`
behind a CLI mirroring the existing `tx-diff` / `cardano-tx-generator`
pattern. In this PR, validation is driven exclusively via N2C against a local
`cardano-node` — the session supplies `PParams`, the tip slot, and the
caller-resolved UTxO. Blockfrost-side validation is deferred to
[#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21) per the
spec's "Scope adjustment" section.

Output is either human (verdict + structural failures, one per line) or a JSON
envelope, switchable via `--output`. Exit codes are `0` (structurally clean),
`1` (structural failure), `≥2` (configuration / resolver / decode error).

Ship release artefacts (AppImage / DEB / RPM / Darwin / Homebrew / Docker) on
day 1 alongside `tx-diff` and `cardano-tx-generator`.

## Technical Context

**Language/Version**: Haskell, GHC 9.12.3 via `haskell.nix` (constitution Operational Constraints).
**Primary Dependencies**:

- `cardano-tx-tools` library (for `validatePhase1` + `isWitnessCompletenessFailure`).
- `cardano-tx-tools:n2c-resolver` (existing) — `Cardano.Tx.Diff.Resolver.N2C.n2cResolver`.
- `Cardano.Tx.Diff.Resolver` from the main library (already in scope).
- `cardano-node-clients`'s `Provider` for the N2C session: `queryProtocolParams`, `queryUTxOByTxIn`, `queryLedgerSnapshot` (`ledgerTipSlot`).
- `aeson` for the JSON output envelope.
- `optparse-applicative` for the argument parser (same library `tx-diff` uses).

**Storage**: N/A. The executable is a request/response shell over the live N2C session.

**Testing**: `hspec` via a new `tx-validate-tests` test-suite (mirrors `tx-generator-tests` shape). Live N2C is NOT exercised at test time (constitution VI); tests use a mock `Provider`-shaped value injected into the session driver.

**Target Platform**: `nix flake check` on `x86_64-linux`; Darwin path covered via the existing Homebrew bundler. The release pipeline produces Linux + Darwin artefacts.

**Project Type**: Single Haskell library + executable (`app/tx-validate/`).

**Performance Goals**: Not load-bearing. Most wall-clock is the N2C round-trip; validation is one ledger STS evaluation.

**Constraints**: Default-offline test discipline (constitution VI). The executable does HTTPS at runtime only if a future Blockfrost variant lands; the N2C-only v1 needs no CA-cert wrapper (`txValidate` mirrors `txDiff` for forward-compat anyway).

**Scale/Scope**: One new module (`Cardano.Tx.Validate.Cli`), one new executable (`app/tx-validate/Main.hs`), one new test-suite. ~200 LOC of new code (the Blockfrost-side complexity is out of scope).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. One-Way Dependency On Node-Clients | ✅ | The N2C glue lives in the existing `Cardano.Tx.Diff.Resolver.N2C` sublibrary. `Cardano.Tx.Validate.Cli` itself imports `cardano-node-clients` ONLY for the `Provider` type alias + the four query functions; that's the same surface `cardano-tx-tools:n2c-resolver` already imports. The main `Cardano.Tx.*` library stays Node-Clients-free. |
| II. Module Namespace Discipline | ✅ | New module is `Cardano.Tx.Validate.Cli`. Executable is `tx-validate` under `app/tx-validate/`. No `Cardano.Node.Client.*` introduced. |
| III. Conway-Only Era | ✅ | Reuses `ConwayTx` from spec 014; the JSON output schema names Conway-era failure constructors. |
| IV. Hackage-Ready Quality | ✅ | New module ships with Haddock; the `werror` flag covers the executable + sublibrary too. `cabal check` keeps passing. |
| V. Strict Warnings | ✅ | New stanzas inherit `import: warnings`. |
| VI. Default-Offline Semantics | ✅ | The executable performs N2C **only** when `--n2c-socket` is supplied. No environment-only fallback. Tests run without network; N2C uses a mock `Provider`. |
| VII. TDD With Vertical Bisect-Safe Commits | ✅ | One commit per behavior slice (parser, session-driver, verdict-printer, release-plumbing). RED + GREEN folded per commit. |
| Resolver Architecture (Operational) | ✅ | This feature consumes the existing `Resolver` chain unchanged. It does NOT add a new resolver type; it adds a *session driver* that owns the N2C resolver for the session role (PParams + slot + UTxO). |

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
├── Cli.hs                       # NEW — argument parser, N2C session driver,
│                                 # verdict printer (human + JSON)
└── (Validate.hs unchanged)

app/tx-validate/
└── Main.hs                      # NEW — thin entry over Cli

test/
└── Cardano/Tx/Validate/
    └── CliSpec.hs               # NEW — argument-parsing, output-shape,
                                  # mocked-N2C coverage

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

Resolved unknowns; full discussion in [research.md](./research.md):

1. **`Provider` accessors for `PParams` + tip slot at the pinned `cardano-node-clients`** — confirm `queryProtocolParams`, `queryLedgerSnapshot`, `ledgerTipSlot` are exposed.
2. **N2C session lifecycle** — `withLocalNodeBackend`-shaped bracket: open LSQ + LTxS channel, query, build resolver, run action, tear down.
3. **JSON output schema stability** — locked in [contracts/json-output.md](./contracts/json-output.md).
4. **Day-1 release plumbing** — symlink-join with `pkgs.makeWrapper` (for forward-compat with the future Blockfrost path), Linux release-artefacts via `nix/linux-release.nix`, Darwin Homebrew bundle via `mkDarwinHomebrewBundle`, Docker image via `nix/docker-image.nix`.

The Blockfrost-related unknowns (R2/R3/R4 of the original plan) are now in [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21)'s research.

## Phase 1 — Design & Contracts

### CLI surface (FR-002)

See [contracts/cli.md](./contracts/cli.md). The parser uses `optparse-applicative`:

```haskell
data TxValidateCliOptions = TxValidateCliOptions
    { txValidateCliInput   :: InputSource
    , txValidateCliN2c     :: N2cConfig
    , txValidateCliOutput  :: OutputFormat
    }

data InputSource  = InputFile FilePath | InputStdin
data OutputFormat = Human | Json
data N2cConfig    = N2cConfig { socket :: FilePath, magic :: NetworkMagic }
```

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
  "pparams_source": "n2c",
  "slot_source": "n2c",
  "utxo_sources": { "<txId>#<ix>": "n2c" }
}
```

The `pparams_source` / `slot_source` / `utxo_sources` fields will all be `"n2c"` in v1; the schema preserves them for forward-compat with [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21)'s Blockfrost path.

### Data model

See [data-model.md](./data-model.md). Three new typed surfaces, all in `Cardano.Tx.Validate.Cli`:

- `TxValidateCliOptions`
- `Session`
- `Verdict`

### Quickstart

See [quickstart.md](./quickstart.md). One invocation pattern in v1:

```bash
tx-validate --input tx.cbor.hex --n2c-socket "$CARDANO_NODE_SOCKET_PATH"
```

### Agent context update

Will run `.specify/scripts/bash/update-agent-context.sh claude` after this plan lands to refresh `CLAUDE.md`.

## Complexity Tracking

None. Constitution Check passes outright.

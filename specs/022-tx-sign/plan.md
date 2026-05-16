# Implementation Plan: tx-sign

**Spec**: [spec.md](./spec.md)
**Approach**: verbatim port from
`/code/amaru-treasury-tx-issue-141` (head of `feat/141-version-and-update-banner`,
which is descended from the merged 128 vault series), renamed into the
`Cardano.Tx.Sign.*` namespace. Each ported module is a vertical commit
that compiles and is bisect-safe; the new executable + cabal/flake
wiring is the final code commit.

## Design

### Module rename map

Source → destination:

| amaru-treasury-tx                       | cardano-tx-tools                  |
|-----------------------------------------|-----------------------------------|
| `Amaru.Treasury.Vault.Age`              | `Cardano.Tx.Sign.Vault.Age`       |
| `Amaru.Treasury.Vault.Witness`          | `Cardano.Tx.Sign.Vault`           |
| `Amaru.Treasury.Tx.Witness`             | `Cardano.Tx.Sign.Witness`         |
| `Amaru.Treasury.Tx.AttachWitness`       | `Cardano.Tx.Sign.AttachWitness`   |
| `Amaru.Treasury.Tx.Envelope`            | `Cardano.Tx.Sign.Envelope`        |
| `Amaru.Treasury.IntentJSON.Common`*     | `Cardano.Tx.Sign.Hex`             |
| `Amaru.Treasury.Cli.Passphrase`         | `Cardano.Tx.Sign.Cli.Passphrase`  |
| `Amaru.Treasury.Cli.Vault`              | `Cardano.Tx.Sign.Cli.Vault`       |
| `Amaru.Treasury.Cli.Witness`            | `Cardano.Tx.Sign.Cli.Witness`     |

`*` only the helpers used by `Tx.Witness`
(`decodeHexBytesAny`, `parseGuardKeyHash`) are ported; the rest of
`IntentJSON.Common` is treasury-specific and not lifted.

`Cli.Common.{GlobalOpts,resolveNetworkName}` are inlined into the
`tx-sign` `Main.hs` because the full `Cli.Common` pulls in
`Amaru.Treasury.Backend` / `SwapWizard` which are out of scope.

### Executable shape

```text
tx-sign --network <preview|preprod|mainnet>
  vault create --signing-key-stdin | --signing-key-paste | --signing-key-file FILE
               --label TEXT
               --out FILE
               [--passphrase-fd N]
               [--scrypt-work-factor N]

tx-sign witness --tx FILE
                --vault FILE
                --identity TEXT
                --out FILE
                [--passphrase-fd N]
```

### Library layout

```text
src/Cardano/Tx/Sign/
  Vault.hs           -- in-memory schema, identity resolution
  Vault/Age.hs       -- age scrypt encrypt/decrypt boundary
  Witness.hs         -- detached vkey witness creation
  AttachWitness.hs   -- internal helper (unsigned tx decode)
  Envelope.hs        -- cardano-cli text-envelope encoding
  Hex.hs             -- bech32/hex decoding helpers
  Cli.hs             -- top-level parser composition
  Cli/Vault.hs       -- vault create subcommand
  Cli/Witness.hs     -- witness subcommand
  Cli/Passphrase.hs  -- safe passphrase intake
```

`Cli` modules live under `Cardano.Tx.Sign.Cli` but are part of the
main library (not a sub-library) so the executable is a thin
`Main.hs`.

### Cabal stanza

Add to `cardano-tx-tools.cabal`:

```cabal
executable tx-sign
  import:           warnings
  hs-source-dirs:   app/tx-sign
  main-is:          Main.hs
  default-language: GHC2021
  build-depends:
    , base
    , cardano-tx-tools
    , optparse-applicative
    , text
```

The library stanza gains new `exposed-modules` for the `Sign.*` tree
and `build-depends` additions:

- `age` (encrypted vault boundary)
- `crypton` (Ed25519 derivation from `addr_xsk` material)
- `bech32` (decoding `addr_xsk` strings)
- `memory` (`ByteArray` for age inputs)
- `optparse-applicative` (CLI parsers)
- `unix` (TTY echo control)
- `directory`, `filepath` (atomic file rewrite)

Index-state (`2026-02-17T10:15:41Z`) matches amaru-treasury-tx, so
the same versions resolve.

### Flake + release wiring

- `flake.nix`: add `apps.tx-sign` and `packages.tx-sign` entries
  parallel to `tx-diff`. The bundlers / `hsBinaries` list grows by
  one.
- `nix/release.nix` (or whatever the existing release-artifact derivation
  is named): add `tx-sign` so AppImage / DEB / RPM / Darwin pkg
  builders see it. Existing helpers in `scripts/release/` are
  parameterised by executable name.
- `.github/workflows/release.yml`: add a `tx-sign` matrix entry with
  a `usage-grep` line that uniquely identifies the help output
  (`Create or use an encrypted Cardano signing-key vault`).
- `.github/workflows/darwin-release.yml`: add to its matrix as well.

### Smoke / fixtures

Port `scripts/smoke/vault-witness` → `scripts/smoke/tx-sign` with
`exe="$(cabal list-bin exe:tx-sign -O0)"` and the executable name
swapped. Port `test/fixtures/118-vault-witness/` → keep filename
intact (`tx-sign` fixture set) since those are signing-key payloads
that are not treasury-specific.

The smoke is wired into `justfile` (`just smoke-sign`) and added to
`just ci`.

### Docs

- `CHANGELOG.md`: new "Unreleased" section bullet (release-please /
  cabal-release picks it up).
- `README.md` "What's here" gets one bullet.
- `docs/` gets `tx-sign.md` and is linked from `mkdocs.yml`.

## Risk / Edge Cases

- **Conway-only key derivation**: vault stores Ed25519 signing-key
  material; the source repo supports `cardano-cli .skey` JSON, raw
  hex, and `addr_xsk` extended keys. All three must keep working
  after the rename — the smoke covers them.
- **No echo for passphrase**: `Cli/Passphrase` uses `unix`'s
  terminal mode flags. macOS support carried over verbatim from the
  source repo, which already runs on Darwin CI.
- **age library upper bound**: `cabal-check` requires upper bounds.
  The source cabal uses `^>= 1.0` shape; copy verbatim.
- **flake index-state pins resolved versions**: any age / crypton
  version drift between repos would surface here. The two cabal
  files share the same index-state (`2026-02-17T10:15:41Z`), so the
  same versions resolve.
- **`-Werror` + `-Wmissing-export-lists`**: cardano-tx-tools uses
  `-Werror` plus `-Wmissing-export-lists`. The source modules already
  pass both.

## Proof / Test strategy

- **Unit tests** under `test/Sign/` exercise:
  - vault round-trip (encrypt → decrypt with the right passphrase
    returns the original bytes; wrong passphrase returns an error
    that does not leak the passphrase).
  - witness creation against a fixture unsigned Conway tx returns a
    well-formed Conway vkey witness, and the resulting signed tx
    deserialises.
  - identity / required-signer mismatch is rejected with a typed
    error before any cryptographic work.
- **Smoke** (`scripts/smoke/tx-sign`) is the end-to-end gate: builds
  the exe, creates a vault from each accepted signing-key shape,
  emits a witness, and verifies the signed tx with
  `cardano-cli transaction view` (or a local equivalent).
- **Bisect safety**: each module-port commit must compile against
  `cabal-fmt -c` and `nix flake check --no-eval-cache`. The cabal
  changes for the new modules go in the same commit as the modules
  themselves (no module-without-stanza intermediate state).

## Commit slices

1. `chore(022): port Cardano.Tx.Sign.Hex` — tiny helper module +
   cabal entry, no behavior change exposed yet.
2. `chore(022): port Cardano.Tx.Sign.Envelope` — pure helper; lives
   under the library.
3. `feat(022): port Cardano.Tx.Sign.AttachWitness` — internal helper
   for tx decode, ported but not yet exposed as CLI.
4. `feat(022): port Cardano.Tx.Sign.Vault{,/Age}` — vault schema +
   age boundary; cabal gains `age`, `crypton`, `memory`.
5. `feat(022): port Cardano.Tx.Sign.Witness` — detached witness
   creation; depends on slices 1-4.
6. `feat(022): port Cardano.Tx.Sign.Cli.*` — Passphrase, Vault,
   Witness CLI parsers/runners; depends on slice 5.
7. `feat(022): add tx-sign executable + flake/release wiring` —
   `app/tx-sign/Main.hs`, flake apps, release.yml matrix entry,
   darwin-release.yml matrix entry, justfile recipe, smoke script,
   fixtures, CHANGELOG, README, docs page.

Slices 1–7 are bisect-safe individually because each adds only the
modules whose dependencies are already present.

## Gate

Local gate (`llm/reviews/local-022-tx-sign/gate.sh`):

```bash
set -euo pipefail
cd /code/cardano-tx-tools-issue-22
nix develop --quiet -c bash -c 'just build && just unit && just cabal-check && cabal-fmt -c cardano-tx-tools.cabal && find . -type f -name "*.hs" -not -path "*/dist-newstyle/*" -exec fourmolu -m check {} +'
nix flake check --no-eval-cache
scripts/smoke/tx-sign
```

# Tasks: tx-sign

**Plan**: [plan.md](./plan.md)
**Convention**: every behavior-changing slice is a single bisect-safe
commit including any RED unit test it ships with. Tests live under
`test/Sign/` and are wired into the existing `unit-tests` cabal
suite.

## T001 — Port `Cardano.Tx.Sign.Hex` (slice 1)

- Create `src/Cardano/Tx/Sign/Hex.hs` containing only the helpers used
  downstream: `decodeHexBytesAny`, `parseGuardKeyHash` (renamed to
  `parseKeyHash`), plus the local helpers they call
  (`mkHash28`, `decodeHexBytes`).
- Re-export through the library: add to `exposed-modules`.
- No new build-depends (already on `bech32`, `base16-bytestring`,
  `text`, `bytestring`).
- RED proof: add `test/Sign/HexSpec.hs` with golden cases for the two
  exported helpers (positive + negative). Wire into `unit-tests`.

Commit: `chore(022): port Cardano.Tx.Sign.Hex`

## T002 — Port `Cardano.Tx.Sign.Envelope` (slice 2)

- Create `src/Cardano/Tx/Sign/Envelope.hs` verbatim, swap module
  header.
- Add to `exposed-modules`.
- RED proof: `test/Sign/EnvelopeSpec.hs` with the same envelope
  round-trip golden that lived next to the source module.

Commit: `chore(022): port Cardano.Tx.Sign.Envelope`

## T003 — Port `Cardano.Tx.Sign.AttachWitness` (slice 3)

- Create `src/Cardano/Tx/Sign/AttachWitness.hs` verbatim, swap module
  header.
- Add to `exposed-modules`.
- Imports of `Amaru.Treasury.IntentJSON.Common` rewritten to
  `Cardano.Tx.Sign.Hex`.
- RED proof: `test/Sign/AttachWitnessSpec.hs` covering the existing
  golden — unsigned tx + N detached vkey witnesses → signed tx with
  preserved body bytes.

Commit: `feat(022): port Cardano.Tx.Sign.AttachWitness`

## T004 — Port `Cardano.Tx.Sign.Vault.Age` and `Cardano.Tx.Sign.Vault` (slice 4)

- Create `src/Cardano/Tx/Sign/Vault/Age.hs` (encryption boundary).
- Create `src/Cardano/Tx/Sign/Vault.hs` (in-memory schema, identity
  resolution).
- cabal: add `age`, `crypton`, `memory` to library `build-depends`.
- RED proof: `test/Sign/VaultSpec.hs` covering:
  - encrypt → decrypt round-trip with correct passphrase.
  - wrong passphrase returns a redacted error.
  - JSON schema round-trip for the cleartext payload across the
    supported `SigningSource` variants (skey JSON, raw hex,
    `addr_xsk`).

Commit: `feat(022): port Cardano.Tx.Sign.Vault and Vault.Age`

## T005 — Port `Cardano.Tx.Sign.Witness` (slice 5)

- Create `src/Cardano/Tx/Sign/Witness.hs`, swap imports from
  `Amaru.Treasury.{IntentJSON.Common,Tx.AttachWitness,Tx.Envelope,Vault.Witness}`
  to the new paths.
- Add to `exposed-modules`.
- RED proof: `test/Sign/WitnessSpec.hs` covering:
  - witness creation against a fixture unsigned Conway tx returns a
    well-formed vkey witness and a valid signed tx when attached.
  - vault identity that does not match any required signer fails
    with a typed mismatch error and does not perform a signing
    operation.

Commit: `feat(022): port Cardano.Tx.Sign.Witness`

## T006 — Port `Cardano.Tx.Sign.Cli.*` (slice 6)

- Create `src/Cardano/Tx/Sign/Cli/Passphrase.hs` verbatim, swap
  header.
- Create `src/Cardano/Tx/Sign/Cli/Vault.hs`, swap imports to the new
  module paths; replace the `Cli.Common.GlobalOpts` /
  `resolveNetworkName` references with the same two helpers exported
  from a new `Cardano.Tx.Sign.Cli` top module (or local module).
- Create `src/Cardano/Tx/Sign/Cli/Witness.hs`, same swap.
- Create `src/Cardano/Tx/Sign/Cli.hs` that composes the two
  subcommands and exposes `runTxSign :: [String] -> IO ()` plus
  `GlobalOpts`, `globalOptsP`, `resolveNetworkName` inlined from the
  source repo.
- cabal: add `optparse-applicative`, `unix`, `directory`, `filepath`
  to library `build-depends` if not already present.
- No new RED proof beyond what slices 1–5 already cover (the Cli
  layer is a thin parser composed of already-tested runners). Add a
  small `test/Sign/CliSpec.hs` that asserts `--help` returns 0 and
  contains both subcommand names.

Commit: `feat(022): port Cardano.Tx.Sign.Cli modules`

## T007 — Add `tx-sign` executable + flake / release wiring (slice 7)

- `app/tx-sign/Main.hs` calls `Cardano.Tx.Sign.Cli.runTxSign =<<
  getArgs`.
- cabal: new `executable tx-sign` stanza.
- `flake.nix`: add `apps.tx-sign` and `packages.tx-sign`; extend the
  `hsBinaries` list.
- `nix/release.nix` (or equivalent): include `tx-sign` in the
  release-bundle inputs alongside `tx-diff` and
  `cardano-tx-generator`.
- `.github/workflows/release.yml`: add the matrix entry. The
  `usage-grep` line is `tx-sign vault create`.
- `.github/workflows/darwin-release.yml`: add the matrix entry.
- `justfile`: add `smoke-sign` recipe; wire into `ci`.
- `scripts/smoke/tx-sign`: ported smoke (sig-key payloads from
  `test/fixtures/118-vault-witness/`).
- `test/fixtures/118-vault-witness/` → `test/fixtures/tx-sign/` (or
  keep the existing name; pick the one that is most stable for
  release-asset paths).
- `CHANGELOG.md`: bullet under "Unreleased".
- `README.md`: bullet under "What's here".
- `docs/tx-sign.md` + `mkdocs.yml` entry.

Commit: `feat(022): add tx-sign executable, release wiring, docs`

## T008 — Local gate green (non-code)

- Run `nix develop --quiet -c just ci`.
- Run `nix flake check --no-eval-cache`.
- Run `scripts/smoke/tx-sign`.
- Fix any breakage by editing the responsible slice in-place (stgit
  flow) and re-running.

## T009 — Push, open draft PR, monitor CI

- Push branch `022-tx-sign`.
- Open draft PR against `main` with a thorough description (tour of
  changes per workflow rule).
- Label `feat`, assign `paolino`, link issue #22.
- Poll CI until green (60s minimum interval per workflow rule).
- Mark ready for review.

## T010 — Release

- After PR merge, the Release Planner cron-or-push-driven workflow
  opens a release PR (or pick one up if already open) that bumps
  cabal version. Confirm it includes the new tx-sign entry in the
  release artifacts. Merge it.
- Verify the `Linux Release` and `darwin-release` workflows fire on
  the new tag and produce `tx-sign-*` artifacts.

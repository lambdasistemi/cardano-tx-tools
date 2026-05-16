# Feature Specification: tx-sign — vault-backed signing CLI

**Feature Branch**: `022-tx-sign`
**Created**: 2026-05-16
**Issue**: [#22](https://github.com/lambdasistemi/cardano-tx-tools/issues/22)
**Source**: `amaru-treasury-tx` issue
[#128](https://github.com/lambdasistemi/amaru-treasury-tx/issues/128) and
spec `specs/118-vault-witness/`.

## Background

`cardano-tx-tools` already builds unsigned Conway transactions
(`Cardano.Tx.Build`) and validates them
(`Cardano.Tx.Validate.validatePhase1`). It does not yet ship the
final signing step. Operators that hand a `.skey` JSON to
`cardano-cli transaction sign` keep plaintext key material on disk;
operators that integrate `tx-build` into automation need a
signing path that never exits through a plaintext file.

`amaru-treasury-tx` implemented this as two CLI subcommands in
spec `specs/118-vault-witness/`:

- `vault create` — import one Cardano payment signing key into an
  age-encrypted vault file.
- `witness` — unlock a vault in memory and emit one detached vkey
  witness for an unsigned Conway transaction CBOR hex.

The logic is generic over Conway transactions; nothing in vault or
witness creation is treasury-specific. This feature ports that code
into `cardano-tx-tools` as a new executable `tx-sign` so every
downstream user of the library gets a vault-backed signing flow.

## User Scenarios

### User Story 1 — Create an encrypted vault (P1)

**Given** Cardano payment signing-key material — a `cardano-cli`
`.skey` JSON, an `addr_xsk` bech32 string, or raw 32-byte hex —
**when** the operator runs `tx-sign vault create --signing-key-stdin
--label core --out core.vault.age` with a passphrase supplied through
an inherited file descriptor or a no-echo TTY prompt, **then** the
command writes one age-encrypted vault file, derives non-secret
metadata (label, network, payment key hash), and never writes a
cleartext payload to disk.

**Acceptance**:

1. Vault file decrypts back to the original signing-key material with
   the same passphrase.
2. Vault metadata records `label`, `network`, and the payment key
   hash.
3. `--signing-key-paste` reads with terminal echo disabled.
4. The passphrase is never accepted as an argv value; no automation
   fd ⇒ no-echo TTY prompt with confirmation.

### User Story 2 — Create a detached witness from a vault (P1)

**Given** an unsigned Conway transaction CBOR hex (from `tx-build`)
and an encrypted vault, **when** the operator runs `tx-sign witness
--tx unsigned.cbor.hex --vault core.vault.age --identity core --out
core.witness` with the passphrase supplied through an inherited file
descriptor, **then** the command unlocks the vault in memory, creates
one detached vkey witness for the transaction, and exits 0.

**Acceptance**:

1. The witness decodes as a Conway vkey witness.
2. The resulting witness can be attached to the original transaction
   to yield a valid signed Conway transaction.
3. The vault's payment key hash matches at least one of the
   transaction's `requiredSigners` / inferred required signers; the
   command rejects vault/transaction mismatches with a clear error.
4. The cleartext signing key never appears on disk during the
   command's lifetime.

## Non-Functional Requirements

- **Module namespace**: all new modules under `Cardano.Tx.Sign.*`
  (constitution principle II).
- **Era**: Conway only (constitution principle III).
- **Dep direction**: `Cardano.Tx.Sign.*` may import from
  `Cardano.Tx.*` but not the other way around. No node-client deps
  in the exposed library.
- **Release**: the executable is wired into the
  `.github/workflows/release.yml` matrix so Linux + Darwin artifacts
  are produced on the next tag.

## Out of Scope

- A user-facing `attach-witness` subcommand (the module is ported as
  an internal helper).
- Generalising vault / witness logic beyond Conway.
- Migrating the existing `amaru-treasury-tx` codebase to depend on
  `tx-sign` (separate follow-up).
- Hardware-wallet signing.
- Multi-identity vaults beyond what the source repo already supports.

## References

- Source spec: <https://github.com/lambdasistemi/amaru-treasury-tx/blob/main/specs/118-vault-witness/spec.md>
- Source PR: <https://github.com/lambdasistemi/amaru-treasury-tx/pull/128>

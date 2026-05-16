# cardano-tx-tools

Four command-line tools and a Haskell library for working with
Conway-era Cardano transactions: **diff** two unsigned bodies,
**sign** with an encrypted vault, **validate** against the ledger
Phase-1 rule, and **generate** a workload of Conway transactions
for soak testing. Each tool is a single self-contained executable;
the library is the same code, exposed for in-process callers.

Documentation: <https://lambdasistemi.github.io/cardano-tx-tools/>.

## The tools

| Tool | What it does | One-line example |
|------|--------------|------------------|
| [`tx-diff`](https://lambdasistemi.github.io/cardano-tx-tools/tx-diff/) | Structural diff between two Conway transactions, keyed by ledger identity (TxIn, address+asset, vkey hash, redeemer purpose). Plutus datums and redeemers decoded against an optional blueprint schema. | `tx-diff a.cbor.hex b.cbor.hex` |
| [`tx-sign`](https://lambdasistemi.github.io/cardano-tx-tools/tx-sign/) | Age-encrypted signing-key vault and detached vkey witness creation. Cleartext keys never touch disk; passphrase never on `argv`. | `tx-sign --network mainnet witness --tx unsigned.cbor.hex --vault core.vault.age --out core.witness.hex` |
| [`tx-validate`](https://lambdasistemi.github.io/cardano-tx-tools/tx-validate/) | Conway Phase-1 pre-flight against a local `cardano-node` via Node-to-Client. Exit code is the contract: `0` clean, `1` structural failure, `≥2` configuration/resolver error. | `tx-validate --input unsigned.cbor.hex --n2c-socket "$CARDANO_NODE_SOCKET_PATH"` |
| [`cardano-tx-generator`](https://lambdasistemi.github.io/cardano-tx-tools/cardano-tx-generator/) | Long-running daemon that drives a configurable mix of Conway transactions against a node for soak / fuzz testing. | `cardano-tx-generator --config preprod.yaml` |

## A worked workflow

The four CLIs compose. A typical signing pipeline:

```bash
# 1. Build / receive an unsigned tx (out of scope; e.g. amaru-treasury-tx).
unsigned=tx.cbor.hex

# 2. Pre-flight against the live ledger.  Exit 0 means it's
# structurally sound (only witness-completeness failures remain,
# which signing will resolve).
tx-validate --input "$unsigned" --n2c-socket "$CARDANO_NODE_SOCKET_PATH" \
    || { echo "Phase-1 rejected; do not sign"; exit 1; }

# 3. Optionally diff against a known-good golden.
tx-diff golden.cbor.hex "$unsigned"

# 4. Sign the body with an encrypted vault.
tx-sign --network mainnet witness \
    --tx "$unsigned" \
    --vault core.vault.age \
    --identity core_development \
    --out core.witness.hex

# 5. Attach the witness and submit (cardano-cli; out of scope).
cardano-cli conway transaction assemble \
    --tx-body-file "$unsigned" \
    --witness-file core.witness.hex \
    --out-file signed.tx.json
```

## Install

Pre-built artifacts attach to every
[GitHub Release](https://github.com/lambdasistemi/cardano-tx-tools/releases).
Pick the one for your platform:

```bash
# AppImage (any Linux) — single self-contained binary
chmod +x tx-validate-<version>-x86_64-linux.AppImage
./tx-validate-<version>-x86_64-linux.AppImage --help

# Debian / Ubuntu
sudo apt install ./tx-validate-<version>-x86_64-linux.deb

# Fedora / RHEL
sudo dnf install ./tx-validate-<version>-x86_64-linux.rpm

# macOS (and Linux) via Homebrew
brew install lambdasistemi/tap/tx-validate

# Docker
docker pull ghcr.io/lambdasistemi/cardano-tx-tools/tx-validate:<version>

# From source via Nix
nix run github:lambdasistemi/cardano-tx-tools#tx-validate -- --help
```

Substitute the executable name (`tx-diff`, `tx-sign`,
`cardano-tx-generator`) as needed. Each CLI prints an upgrade
banner on stderr when a newer release is available; silence it
with `<EXE>_NO_UPDATE_CHECK=1`.

## The library

Same code, exposed under `Cardano.Tx.*` for in-process callers
(e.g. another Haskell signing pipeline embedding the validator).
Notable entry points:

| Module | Role |
|--------|------|
| `Cardano.Tx.Build` | Monadic DSL for assembling Conway transactions |
| `Cardano.Tx.Balance` | Fee balancing + collateral selection |
| `Cardano.Tx.Evaluate` | Redeemer re-evaluation against the final body |
| `Cardano.Tx.Validate.validatePhase1` | Ledger Phase-1 pre-flight (`Mempool.applyTx`) |
| `Cardano.Tx.Diff` | Structural diff (used by `tx-diff`) |
| `Cardano.Tx.Blueprint` | Schema-aware Plutus datum/redeemer decoding |
| `Cardano.Tx.Sign.*` | Vault + witness primitives (used by `tx-sign`) |
| `Cardano.Tx.Generator.*` | Generator engine (used by `cardano-tx-generator`) |

The main library has **no** node-client dependency. N2C access
lives in an opt-in `n2c-resolver` sub-library; this lets pure
consumers (tests, in-process callers) build against the API
without pulling in the `cardano-node-clients` mux + ouroboros
stack. Dependency direction is one-way: `cardano-tx-tools →
cardano-node-clients`.

## Develop

The flake-managed dev shell carries every tool the CI uses
(`cabal`, `cabal-fmt`, `fourmolu`, `hlint`, `just`, `mkdocs`):

```bash
nix develop --quiet -c just build
nix develop --quiet -c just ci          # build + tests + lint + format
nix flake check --no-eval-cache         # full local gate (mirrors CI)
```

Specs and per-feature design notes live under
[`specs/`](specs/); each numbered feature has its own
`spec.md` / `plan.md` / `tasks.md` produced via the
[Spec-Driven Development](https://github.com/github/spec-kit) workflow.

## License

[Apache 2.0](LICENSE).

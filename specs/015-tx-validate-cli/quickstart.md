# Quickstart: running `tx-validate`

**Feature**: 015-tx-validate-cli
**Date**: 2026-05-16

## Install

After this PR merges and the next tag fires, install via your platform of choice:

```bash
# Homebrew (macOS + Linux)
brew install lambdasistemi/tap/tx-validate

# Debian / Ubuntu
sudo apt install ./tx-validate_<version>_amd64.deb

# Fedora / RHEL
sudo dnf install ./tx-validate-<version>.x86_64.rpm

# AppImage (any Linux)
chmod +x tx-validate-<version>-x86_64.AppImage
./tx-validate-<version>-x86_64.AppImage --help

# Docker
docker pull ghcr.io/lambdasistemi/tx-validate:<version>
```

Or run from source:

```bash
nix run github:lambdasistemi/cardano-tx-tools#tx-validate -- --help
```

## Invocation (v1 — local cardano-node via N2C)

```bash
tx-validate \
    --input tx.cbor.hex \
    --n2c-socket "$CARDANO_NODE_SOCKET_PATH" \
    --network-magic 764824073        # mainnet; omit for default
```

Exit `0` if structurally clean, `1` if a structural failure was found. The verdict + failure lines go to stdout.

> **Blockfrost-side invocation** (no local node required) is deferred to
> [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21). Until
> that ships, you need access to a local cardano-node socket.

## Reading the output

### Human (default)

```
$ tx-validate --input ok.cbor.hex --n2c-socket "$CARDANO_NODE_SOCKET_PATH"
structurally clean: 2 witness-completeness failures filtered
$ echo $?
0
```

```
$ tx-validate --input broken.cbor.hex --n2c-socket "$CARDANO_NODE_SOCKET_PATH"
structural failure: 1 structural; 2 witness-completeness filtered
  UTXOW.ScriptIntegrityHashMismatch: expected 41a7cd57… got 03e9d7ed…
$ echo $?
1
```

### JSON

```
$ tx-validate --input ok.cbor.hex \
    --n2c-socket "$CARDANO_NODE_SOCKET_PATH" \
    --output json
```

```json
{
  "status": "structurally_clean",
  "exit_code": 0,
  "structural_failures": [],
  "witness_completeness_count": 2,
  "pparams_source": "n2c",
  "slot_source": "n2c",
  "utxo_sources": {
    "59e10ca5…#0": "n2c",
    "59e10ca5…#2": "n2c",
    "f5f1bdfa…#0": "n2c"
  }
}
```

Schema details: [contracts/json-output.md](./contracts/json-output.md).

## Pipeline integration

Use the exit code; do not parse stdout. Examples:

```bash
# Halt the pipeline if not structurally clean.
tx-validate --input tx.cbor.hex --n2c-socket "$CARDANO_NODE_SOCKET_PATH" \
    || exit 1

# CI gate: validate before signing in a treasury workflow.
tx-validate --input "$tx_path" \
    --n2c-socket "$CARDANO_NODE_SOCKET_PATH" \
    --output json > tx-validate.json
case $? in
    0) echo "clean; signing"; sign_and_submit "$tx_path" ;;
    1) echo "structural failure"; jq . tx-validate.json; exit 1 ;;
    *) echo "tx-validate config / resolver error: $?"; exit $? ;;
esac
```

## Common gotchas

- **No local node?** v1 requires `--n2c-socket`. Blockfrost path tracked in [#21](https://github.com/lambdasistemi/cardano-tx-tools/issues/21).
- **Stale UTxO snapshot**: if your local node has already consumed the inputs the tx references (e.g. it saw a competing tx) you'll get `mempool_short_circuit`. Resolve by rebuilding the tx against a fresher UTxO set.
- **Preview vs preprod**: the library does not distinguish them per spec 014's R3 caveat. Use `--network-magic` for the right testnet magic; everything else is mainnet-shaped.
- **Stdin**: `--input -` reads CBOR hex from stdin until EOF.

# cardano-tx-tools

Seven command-line tools and a Haskell library for working with
Conway-era Cardano transactions: **diff** two unsigned bodies,
**inspect** one body as a structured named report, **emit** an
RDF graph, **sign** with an encrypted vault, **validate** against
the ledger Phase-1 rule, and **generate** a workload of Conway
transactions for soak testing. Each tool is a single self-contained
executable; the library is the same code, exposed for in-process
callers.

Documentation: <https://lambdasistemi.github.io/cardano-tx-tools/>.

## The tools

| Tool | What it does | One-line example |
|------|--------------|------------------|
| [`tx-diff`](https://lambdasistemi.github.io/cardano-tx-tools/tx-diff/) | Structural diff between two Conway transactions, keyed by ledger identity (TxIn, address+asset, vkey hash, redeemer purpose). Plutus datums and redeemers decoded against an optional blueprint schema. | `tx-diff a.cbor.hex b.cbor.hex` |
| [`tx-inspect`](https://lambdasistemi.github.io/cardano-tx-tools/tx-inspect/) | Render one Conway transaction as a structured, human-readable report. Optional [rewriting-rules YAML](https://lambdasistemi.github.io/cardano-tx-tools/rewriting-rules/) drives two stages: **collapse** repeated shapes into named buckets, then **rename** payment addresses and script hashes to address-book names. Same loader and per-leaf renderer `tx-diff` uses. | `tx-inspect tx.cbor.hex --rules rules/amaru-treasury.yaml` |
| [`tx-sign`](https://lambdasistemi.github.io/cardano-tx-tools/tx-sign/) | Age-encrypted signing-key vault and detached vkey witness creation. Cleartext keys never touch disk; passphrase never on `argv`. | `tx-sign --network mainnet witness --tx unsigned.cbor.hex --vault core.vault.age --out core.witness.hex` |
| [`tx-validate`](https://lambdasistemi.github.io/cardano-tx-tools/tx-validate/) | Conway Phase-1 pre-flight against a local `cardano-node` via Node-to-Client. Exit code is the contract: `0` clean, `1` structural failure, `≥2` configuration/resolver error. | `tx-validate --input unsigned.cbor.hex --n2c-socket-path "$CARDANO_NODE_SOCKET_PATH"` |
| [`tx-graph`](https://lambdasistemi.github.io/cardano-tx-tools/tx-graph/) | Emits a Conway transaction (or a whole lattice of them) as RDF — the operator-entity overlay (from a rules file in Turtle or YAML sugar), the transaction body (inputs / outputs / certs / mints / withdrawals / collateral / proposals), and their cross-references in canonical Turtle or JSON-LD. Pure transformation: input is a positional CBOR or a `--in-dir DIR` of CBORs (the lattice); the lattice resolves itself in-memory, no node or UTxO file needed. | `tx-graph --rules rules.yaml --in-dir lattice/cbor --out-dir lattice` |
| [`tx-fetch`](https://lambdasistemi.github.io/cardano-tx-tools/tx-fetch/) | Closure-walking Conway CBOR fetcher. Resolves seed transaction ids over Blockfrost's `/txs/<hash>/cbor` endpoint, walks each tx's spending / reference / collateral input parents to `--depth`, hash-verifies every CBOR against its requested `TxId`, and writes one `<txid>.cbor` per tx into `<out-dir>/cbor/`. Pairs with `tx-graph --in-dir` to produce a Turtle lattice. | `tx-fetch --out-dir lattice --depth 1 <seed-txid>...` (requires `BLOCKFROST_PROJECT_ID`) |
| [`cardano-tx-generator`](https://lambdasistemi.github.io/cardano-tx-tools/cardano-tx-generator/) | Long-running daemon that drives a configurable mix of Conway transactions against a node for soak / fuzz testing. | `cardano-tx-generator --config preprod.yaml` |

Blueprint-aware decoding is shared by `tx-diff` and `tx-graph`.
When a `rules.yaml` registers a CIP-57 blueprint for a script,
Plutus datum and redeemer fields are decoded into typed predicates
instead of remaining only as opaque CBOR bytes; decode failures stay
non-fatal and surface as `cardano:decodeError` triples.

## A worked workflow

The CLIs compose. A typical signing pipeline:

```bash
# 1. Build / receive an unsigned tx (out of scope; e.g. amaru-treasury-tx).
unsigned=tx.cbor.hex

# 2. Pre-flight against the live ledger.  Exit 0 means it's
# structurally sound (only witness-completeness failures remain,
# which signing will resolve).
tx-validate --input "$unsigned" --n2c-socket-path "$CARDANO_NODE_SOCKET_PATH" \
    || { echo "Phase-1 rejected; do not sign"; exit 1; }

# 3. Inspect the tx as a structured, named report (collapse + rename
# driven by a rewriting-rules YAML).
tx-inspect "$unsigned" --rules rules/amaru-treasury.yaml

# 4. Optionally diff against a known-good golden — the same rules
# file applies to both sides of the diff.
tx-diff --collapse-rules rules/amaru-treasury.yaml golden.cbor.hex "$unsigned"

# 4b. Emit RDF; a registered CIP-57 blueprint turns datum fields
#     into typed predicates such as :SwapOrder_recipient.
tx-graph --rules rules/swap-v2.yaml "$unsigned" > graph.ttl
grep -E 'SwapOrder_recipient|_0_pubKeyHash' graph.ttl

# 4c. Or fetch a whole closure first and emit ttls over the lattice:
tx-fetch --out-dir lattice --depth 1 <seed-txid> ...
tx-graph --rules rules/swap-v2.yaml --in-dir lattice/cbor --out-dir lattice

# 5. Sign the body with an encrypted vault.
tx-sign --network mainnet witness \
    --tx "$unsigned" \
    --vault core.vault.age \
    --identity core_development \
    --out core.witness.hex

# 6. Attach the witness and submit (cardano-cli; out of scope).
cardano-cli conway transaction assemble \
    --tx-body-file "$unsigned" \
    --witness-file core.witness.hex \
    --out-file signed.tx.json
```

A blueprint-typed datum in `graph.ttl` looks like:

```turtle
_:outputDatum1 a cardano:Datum ;
  cardano:hasHash _:hash_datum_c9bc91a9f2f9d50c ;
  :SwapOrder_recipient _:outputDatum1_recipient .

_:outputDatum1_recipient :_0_pubKeyHash _:outputDatum1_recipient_pubKeyHash .
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

# macOS (and Linux) via Homebrew — formula per executable:
#   tx-diff, tx-validate, tx-inspect, tx-sign, tx-graph, tx-fetch, cardano-tx-generator
brew install lambdasistemi/tap/tx-validate

# Docker
docker pull ghcr.io/lambdasistemi/cardano-tx-tools/tx-validate:<version>

# From source via Nix
nix run github:lambdasistemi/cardano-tx-tools#tx-validate -- --help
```

Substitute the executable name (`tx-diff`, `tx-inspect`,
`tx-sign`, `tx-graph`, `tx-fetch`, `cardano-tx-generator`) as needed. Each CLI prints
an upgrade banner on stderr when a newer release is available (currently
`tx-diff` and `tx-inspect`); silence it with `<EXE>_NO_UPDATE_CHECK=1`.

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
| `Cardano.Tx.Graph.Rules.Load` | Operator rules loader (Turtle + YAML sugar), used by `tx-graph` |
| `Cardano.Tx.Graph.Emit` | Body emitter: walks `Cardano.Tx.Diff.conwayDiffProjection` to render a Conway tx + resolved UTxO + operator-entity overlay as Turtle or JSON-LD, used by `tx-graph` |
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

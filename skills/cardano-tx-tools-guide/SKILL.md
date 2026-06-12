---
name: cardano-tx-tools-guide
description: >-
  Repository guide for lambdasistemi/cardano-tx-tools — the Haskell package of
  eight CLIs and libraries for Conway-era Cardano transactions. Load this when
  working in this repo or answering questions about it: the tools tx-diff,
  tx-inspect, tx-graph, tx-view, tx-fetch, tx-validate, tx-sign, and
  cardano-tx-generator; reading/diffing/inspecting a Conway tx body (CBOR hex,
  raw CBOR, or cardano-cli JSON envelope); the rewriting-rules YAML grammar
  (--rules / --collapse-rules, collapse + rename stages); CIP-57 blueprint
  decoding; emitting Turtle/JSON-LD RDF graphs and projecting packaged views
  (cli-tree, asset-flow, entity-occurrences, json-ld); age-encrypted signing-key
  vaults and detached vkey witnesses; Phase-1 validation via Node-to-Client
  (N2C) against a local cardano-node; Blockfrost closure fetching
  (BLOCKFROST_PROJECT_ID); the n2c-resolver and tx-generator-lib sub-libraries;
  Cardano.Tx.* modules; conwayDiffProjection; the WithdrawalsNotInRewardsCERTS
  false positive (issue #61); building/testing with nix develop, just, and
  cabal; or the mkdocs docs site.
---

# cardano-tx-tools guide

One Haskell package (`cardano-tx-tools.cabal`, v0.2.3.0) with four libraries and
eight executables. Apache-2.0. GHC 9.12.3 via `haskell.nix`.

## Repository map

| Path | Purpose |
|------|---------|
| `app/<exe>/Main.hs` | CLI entry point per executable (`tx-diff`, `tx-inspect`, `tx-graph`, `tx-view`, `tx-fetch`, `tx-validate`, `tx-sign`, `cardano-tx-generator`) |
| `src/Cardano/Tx/` | **Main library.** `Diff` (structural diff + `conwayDiffProjection`), `Diff/Cli`, `Diff/Scan` (Cardanoscan URLs), `Diff/Resolver`, `Diff/Resolver/Web2` (Blockfrost HTTP resolver), `Rewrite` (collapse + rename rules), `Blueprint` (CIP-57 decode), `Validate` + `Validate/Cli` (Phase-1), `View` + `View/*` (4 projections), `Graph/Emit` + `Graph/Emit/*` (Turtle/JSON-LD), `Graph/Rules/Load` (rules loader), `Sign/*` (`Vault`, `Vault/Age`, `Witness`, `AttachWitness`, `Envelope`, `Hex`, `Cli`, `Cli/*`) |
| `src-tx-build/Cardano/Tx/` | **`tx-build` sub-library**: `Build`, `Balance`, `Evaluate`, `Ledger`, `Inputs`, `Scripts`, `Deposits`, `Credentials`, `Witnesses` |
| `lib-n2c-resolver/Cardano/Tx/Diff/Resolver/N2C.hs` | **`n2c-resolver` sub-library** — opt-in Node-to-Client read access (the only lib that links `cardano-node-clients` for reads) |
| `lib-tx-generator/Cardano/Tx/Generator/*.hs` | **`tx-generator-lib`** — daemon engine (`Daemon`, `Server`, `Build`, `Selection`, `Population`, `Fanout`, `Persist`, `Snapshot`, `Types`) |
| `rules/amaru-treasury.yaml` | Example rewriting-rules file (collapse + rename) |
| `views/*.rq` | Packaged SPARQL view contracts: `cli-tree`, `asset-flow`, `entity-occurrences`, `json-ld`, plus `no-stub-triples` (a test gate, not a user view) |
| `scripts/{smoke,release,tx-lattice}` | Smoke tests, release helpers, the lattice-demo driver |
| `test/` | `unit-tests`, `e2e-tests`, `tx-generator-tests`, `tx-validate-tests` + fixtures |
| `docs/`, `mkdocs.yml` | MkDocs site (per-tool pages, `architecture.md`, rewriting-rules grammar, May-2026 lattice demo, prior-art) |
| `specs/` | Per-feature `spec.md` / `plan.md` / `tasks.md` (Spec-Driven Development) |
| `flake.nix`, `justfile`, `cabal.project` | Build tooling |

## Build, test, run

```bash
nix develop --quiet -c just build      # cabal build all -O0
nix develop --quiet -c just unit       # unit tests (just unit MATCH to filter)
nix develop --quiet -c just ci         # build + tests + smoke + lint + fmt check
nix flake check --no-eval-cache        # full gate, mirrors CI
nix develop --quiet -c just format     # fourmolu + cabal-fmt
nix develop --quiet -c just build-docs # mkdocs build --strict
cabal haddock cardano-tx-tools         # API reference
```

Run any tool from source: `nix run .#tx-inspect -- --help` (each executable has
a matching flake app and package). Smoke a single tool: `just smoke-sign`,
`just smoke-inspect`, `just smoke-diff`.

## Navigating the code

- The decoder that accepts CBOR hex / raw CBOR / `cardano-cli` JSON envelope is
  `decodeConwayTxInput` in `src/Cardano/Tx/Diff.hs`; `tx-diff`, `tx-inspect`,
  and `tx-validate` all use it.
- `tx-diff`, `tx-inspect`, and `tx-graph` all walk the one structural
  projection `Cardano.Tx.Diff.conwayDiffProjection`.
- Rewriting-rules parsing/application is `Cardano.Tx.Rewrite`
  (`parseRewriteRulesYaml`, `applyRewriteRules`), shared by `tx-inspect --rules`
  and `tx-diff --collapse-rules`. The engine always runs `collapse` then
  `rename`, regardless of YAML key order.
- Phase-1 logic is `Cardano.Tx.Validate.validatePhase1`; the
  `WithdrawalsNotInRewardsCERTS` false positive (issue #61) is handled in
  `Cardano.Tx.Validate` by keeping missing reward accounts absent so the ledger
  surfaces the failure faithfully.
- Signing primitives are under `Cardano.Tx.Sign.*`; the signing-key source
  decoder (`.skey` JSON or `addr_xsk` bech32 only) is `decodeSigningKeySourceText`
  in `src/Cardano/Tx/Sign/Cli/Vault.hs`.

## Using the tools

Verified CLI surfaces (flags as implemented in `app/*/Main.hs` and
`src/Cardano/Tx/*/Cli.hs`):

```bash
# tx-diff: TX_A TX_B positional; exit 1 when the diff has changes.
tx-diff [--render tree|paths] [--tree-art ascii|unicode] \
  [--collapse-rules FILE] [--blueprint FILE ...] \
  [--resolve-n2c SOCKET --network-magic N] \
  [--resolve-web2 URL [--web2-api-key-file PATH]] TX_A TX_B

# tx-inspect: one required positional TX (a file path).
tx-inspect [--render tree|paths] [--tree-art ascii|unicode] [--rules FILE] \
  [--n2c-socket-path SOCKET --network-magic N] \
  [--web2-url URL [--web2-api-key-file PATH]] \
  [--links cardanoscan [--network mainnet|preprod|preview]] TX

# tx-validate: exit 0 clean / 1 structural failure / >=2 config-resolver error.
tx-validate --input PATH|- --n2c-socket-path PATH \
  [--network-magic WORD32] [--output human|json] [--version]

# tx-sign: global --network BEFORE the subcommand.
tx-sign --network mainnet|preprod|preview|devnet vault create \
  (--signing-key-stdin | --signing-key-paste | --signing-key-file PATH) \
  --label LABEL --out PATH [--vault-passphrase-fd FD] [--force]
tx-sign --network mainnet witness --tx PATH --vault PATH --identity LABEL \
  [--out PATH] [--vault-passphrase-fd FD] [--expected-key-hash HASH]

# tx-graph: positional CBOR(s) or --in-dir; stdout for a single input.
tx-graph [--rules FILE] [--in-dir DIR] [--out-dir DIR] \
  [--format turtle|json-ld] [CBOR... | -]

# tx-fetch: needs BLOCKFROST_PROJECT_ID; writes <out-dir>/cbor/<txid>.cbor.
tx-fetch --out-dir DIR [--network mainnet|preprod|preview] [--depth N] TXID...

# tx-view: project a tx-graph graph through a packaged view.
tx-view --graph FILE [--view cli-tree|asset-flow|entity-occurrences|json-ld] [--out FILE]

# cardano-tx-generator: individual flags (no --config file).
cardano-tx-generator --relay-socket PATH --control-socket PATH --state-dir DIR \
  --master-seed-file PATH --faucet-skey-file PATH --network-magic INT [...]
```

Update banner: `tx-diff`, `tx-inspect`, `tx-sign`, `tx-validate`, and
`cardano-tx-generator` print an upgrade banner on stderr; silence with
`<EXE>_NO_UPDATE_CHECK=1`. `tx-graph`, `tx-fetch`, and `tx-view` have no banner.

## Answering questions

- "What does X tool do / what flags?" → the per-tool docs page
  (`docs/<tool>.md`) and the README **Usage** table; CLI ground truth is
  `app/<tool>/Main.hs`.
- "How do the pieces fit together?" → `docs/architecture.md` and the README
  **Architecture** diagram.
- "What's the rewriting-rules format?" → `docs/rewriting-rules.md`; parser is
  `Cardano.Tx.Rewrite` / `Cardano.Tx.Diff` (`FromJSON` instances).
- "How do I install / release?" → README **Install**; `.github/workflows/`
  (`release.yml`, `darwin-release.yml`, `publish-images.yaml`) and `flake.nix`.
- "Library API?" → README **The library** table and `cabal haddock`.
- "End-to-end RDF lattice demo?" → `docs/may-2026-amaru-lattice/`
  (`run-the-report.md`, `blockfrost-provider.md`) and `scripts/tx-lattice`.
- Library/CLI boundary policy (no node-client in the main lib; cq-rdf consumed
  at the CLI boundary) → README **What is this** and `docs/architecture.md`.

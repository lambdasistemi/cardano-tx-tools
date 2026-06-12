# Repository Agent Guide

## What this repo is

`cardano-tx-tools` is a single Haskell package (`cardano-tx-tools.cabal`,
version 0.2.3.0) that provides eight command-line tools and the libraries
behind them for working with Conway-era Cardano transactions: `tx-diff`
(structural diff), `tx-inspect` (named report), `tx-graph` (RDF emit), `tx-view`
(packaged graph views), `tx-fetch` (closure CBOR fetcher), `tx-validate`
(Phase-1 pre-flight), `tx-sign` (age-vault witness signing), and
`cardano-tx-generator` (soak-test daemon). The same logic is exposed as a
library under `Cardano.Tx.*`. See the [README](README.md) and the docs site at
<https://lambdasistemi.github.io/cardano-tx-tools/>.

## How to work here

Everything runs through the Nix dev shell (GHC 9.12.3 via `haskell.nix`) and
`just`:

- Build: `nix develop --quiet -c just build` (`cabal build all -O0`)
- Unit tests: `nix develop --quiet -c just unit` (optionally `just unit MATCH`)
- Full local gate (build + tests + smoke + lint + format check):
  `nix develop --quiet -c just ci`
- Flake check (mirrors CI): `nix flake check --no-eval-cache`
- Format: `nix develop --quiet -c just format` (fourmolu + cabal-fmt)
- Smoke a single tool: `just smoke-sign`, `just smoke-inspect`, `just smoke-diff`
- Run a tool from source: `nix run .#tx-inspect -- --help` (every executable —
  `tx-diff`, `tx-inspect`, `tx-sign`, `tx-validate`, `tx-graph`, `tx-fetch`,
  `tx-view`, `cardano-tx-generator` — has a matching flake app and package)
- Build the docs site: `nix develop --quiet -c just build-docs`
  (`mkdocs build --strict`); serve with `just serve-docs`
- API reference: `cabal haddock cardano-tx-tools`

Scope discipline (constitution): the main library has no node-client
dependency; Node-to-Client access lives only in the `n2c-resolver` sub-library
and in `tx-generator-lib`. Keep that dependency direction one-way.

Per-feature design notes (`spec.md` / `plan.md` / `tasks.md`) live under
`specs/`, produced via the Spec-Driven Development workflow.

## Skills

Activatable procedures live under `skills/`. Load the one whose description
matches your task:

- `skills/cardano-tx-tools-guide/` — repository map, exact build/test/run
  commands, where each tool's logic lives, verified CLI usage for all eight
  executables, and where to find answers to the questions users ask about this
  project.

# cardano-tx-tools Constitution

## Core Principles

### I. One-Way Dependency On Node-Clients

This repository depends on
[`cardano-node-clients`](https://github.com/lambdasistemi/cardano-node-clients)
for `Provider`, `Submitter`, the `ConwayTx` type alias, and N2C
mini-protocol access. The reverse arrow MUST never hold: nothing in
`cardano-node-clients` may import from `Cardano.Tx.*`. A
`source-repository-package` pin during the staged migration period
is acceptable; long-term we depend on a released version of
`cardano-node-clients` only.

### II. Module Namespace Discipline

All exposed modules live under `Cardano.Tx.*`. The legacy
`Cardano.Node.Client.*` namespace inherited from the previous
location is renamed in the migration. New modules MUST NOT introduce
a `Node.Client.*` path; that namespace belongs to mini-protocol code
in `cardano-node-clients`.

### III. Conway-Only Era

This repository targets Conway transactions only. Pre-Conway eras
are out of scope. When a new ledger era ships, the migration is
in-place (drop Conway types, add the new era's types) rather than
keeping multiple eras side-by-side.

### IV. Hackage-Ready Quality

Every package must be Hackage-ready at all times:

- `cabal check` passes with no errors or warnings.
- Haddock docstrings on every exported function and type.
- Module headers in the canonical `{- | Module … -}` form.
- Complete metadata: homepage, bug-reports, license, category.
- Version bounds on all dependencies.
- `README.md` and `CHANGELOG.md` listed in `extra-doc-files`.

### V. Strict Warnings, No `-Werror` Escape Hatches

The canonical warning set is `-Wall -Werror -Wunused-imports
-Wmissing-export-lists -Wname-shadowing -Wredundant-constraints`,
with `-Werror` gated behind a `werror` cabal flag for downstream
build flexibility (matching the
[cardano-node-clients pattern](https://github.com/lambdasistemi/cardano-node-clients/blob/main/cardano-node-clients.cabal)).
Nix builds set the flag to `true`.

### VI. Default-Offline Semantics

Every tool in this repo (starting with `tx-diff`) MUST default to a
fully offline mode where it operates only on the transactions
provided on disk. Network access — N2C sockets, Blockfrost-style
HTTP endpoints, anything else — is strictly opt-in and gated behind
explicit flags. No silent fallback to remote sources.

### VII. TDD With Vertical Bisect-Safe Commits

RED+GREEN folds into one reviewed commit per behavior change. No
WIP, fixup, or "added tests" follow-up commits. Each commit on
`main` is a complete vertical slice that compiles, tests green, and
preserves the bisect-safety contract.

## Operational Constraints

### Build And Test Toolchain

- GHC 9.12.3 via `haskell.nix` (`compiler-nix-name = "ghc9123"`).
- `nix flake check --no-eval-cache` is the local gate; CI mirrors it
  by running `nix run --quiet .#<name>` per registered app.
- Tool versions inside the haskell.nix `tools` dict are NOT pinned
  (use `{ }`) so GHC bumps don't break the dev shell.
- Lint stack: `fourmolu`, `hlint`, `cabal-fmt`. Format check uses
  `fourmolu -m check`, not the in-place `fourmolu -i`.

### Release Hygiene

- Conventional Commits format. `feat:` ↔ minor, `fix:` ↔ patch,
  `feat!:` / `BREAKING CHANGE:` ↔ major.
- Linear git history on `main`; merge via rebase, never merge
  commits or squash-of-many.
- Released binaries that perform HTTPS MUST bundle a CA store via
  `pkgs.makeWrapper` setting `SSL_CERT_FILE`; Docker images include
  `pkgs.cacert` in `copyToRoot`.

### Resolver Architecture

For input resolution and any future "resolve a referenced
on-chain entity" feature, callers express resolvers as
`Resolver`-record-of-functions chains with explicit name and
priority. The chain enforces try-order (cheap-and-local first,
paid-and-remote last) and exposes per-input `unresolved-by [names]`
diagnostics to stderr. New resolvers MUST slot into this chain
rather than being wired in ad-hoc inside the diff core.

## Development Workflow

- Every feature goes through the Spec Kit workflow:
  `/speckit.specify → /speckit.plan → /speckit.tasks →
  /speckit.implement`. Even "obvious" changes pay the spec-first
  cost; the artifact catches edge cases before code is written.
- Pull requests are opened as drafts; CI runs on every push;
  reviewers are blocked from approving until `nix flake check` is
  green on the head commit.
- `WIP.md` per worktree is allowed and `.gitignore`'d; long-form
  investigation notes go in `.llm/` (also gitignored).

## Governance

This constitution is the gating contract for every plan, task list,
and code review. Changes to it MUST land in their own PR, with a
short rationale in the PR description and a paragraph in
`CHANGELOG.md` so downstream consumers can detect the policy change
in their release feed.

**Version**: 1.0.0 | **Ratified**: 2026-05-15

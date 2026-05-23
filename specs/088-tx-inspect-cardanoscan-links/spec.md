# Feature Specification: tx-inspect — Cardanoscan URL mapper for inspect-tree leaves with opt-in CLI flag

**Feature Branch**: `88-tx-inspect-cardanoscan-links`
**Created**: 2026-05-23
**Status**: Draft
**Input**: GitHub issue #88 — "tx-inspect: library API for mapping inspect-tree leaves to Cardanoscan URLs, with opt-in CLI flag"

## Goal

Ship a pure, library-level mapping from inspect-tree leaf elements
to Cardanoscan URLs, and surface it in `tx-inspect` behind an
opt-in `--links=cardanoscan` flag. The library piece is the
contract; the CLI wiring is the observable proof.

## Clarifications

### Session 2026-05-23

- Q: What is the API shape for the library mapper? → A: Pure mapper
  over a leaf-id ADT (`InspectLeaf` constructors per leaf class) and
  a total function `cardanoscanUrl :: Network -> InspectLeaf -> Url`.
- Q: Which leaves does the first slice cover? → A: Transaction hash,
  tx-input references (tx hash + output index — link to the producing
  tx; index highlighting is out of scope), output addresses (payment
  bech32) and stake addresses (bech32), policy ids and asset
  fingerprints.
- Q: How does the CLI surface this? → A: Opt-in `--links=cardanoscan`
  flag. Default behavior unchanged. Network is inferred from the
  N2C provider already in use.
- Q: Which networks must the URL host distinguish? → A: Mainnet
  (`cardanoscan.io`), preprod (`preprod.cardanoscan.io`), preview
  (`preview.cardanoscan.io`). Unknown magics are a typed error from
  the network constructor — not from the mapper, which remains
  total over `Network`.

## P1 user story

As a library consumer of `cardano-tx-tools`, I call `cardanoscanUrl`
on an `InspectLeaf` value and receive a network-correct Cardanoscan
URL for that leaf.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Library consumer maps a leaf to a Cardanoscan URL (Priority: P1)

A tool author building on top of `cardano-tx-tools` walks the
inspect projection, classifies a leaf, and asks the library for the
canonical Cardanoscan URL:

```haskell
import Cardano.Tx.Diff.Scan (
    InspectLeaf (..),
    Network (..),
    cardanoscanUrl,
 )

cardanoscanUrl Mainnet (InspectTxHash "abc...") :: Url
-- => "https://cardanoscan.io/transaction/abc..."
```

The function is total — every `InspectLeaf` constructor on every
supported `Network` produces a well-formed URL. The library does no
I/O and does not commit to a particular renderer; the caller is free
to splice URLs into a tree, a table, JSON, or anything else.

**Why this priority**: This is the contract. Every other surface
(`tx-inspect --links=cardanoscan`, future `tx-diff` integration,
external consumers) reads from it. Issue #88 names it the paramount
user story.

**Independent Test**: A QuickCheck property over `(Network,
InspectLeaf)` pairs renders every value to a URL that parses back to
scheme + host + path with no malformed output. Per-variant golden
strings pin the exact URL shape on mainnet and one testnet.

**Acceptance Scenarios**:

1. **Given** any `InspectLeaf` constructor and any supported
   `Network`, **When** `cardanoscanUrl` is called, **Then** it
   returns a `Url` whose host is the Cardanoscan host for that
   network and whose path encodes the leaf (`/transaction/<hash>`,
   `/address/<bech32>`, `/stakekey/<bech32>`, `/tokenPolicy/<policy>`,
   `/token/<fingerprint>`) — no `Nothing`, no exception.

### User Story 2 — Operator renders an inspect tree with Cardanoscan links (Priority: P1)

A treasury reviewer wants clickable Cardanoscan links next to the
scannable leaves of the inspect output:

```bash
tx-inspect tx.cbor --rules rules/amaru-treasury.yaml --links=cardanoscan
```

The rendered tree carries each scannable leaf alongside its
Cardanoscan URL (e.g. `addr1q... [https://cardanoscan.io/address/
addr1q...]`). The default (`--links` absent) is unchanged byte-for-
byte. Network is inferred from the N2C provider tx-inspect already
opens.

**Why this priority**: This is the shipped operator surface. The
Command-Recovery Rule applies: the CLI is the P1 here, not the
smoke.

**Independent Test**: `scripts/smoke/tx-inspect` runs
`tx-inspect --links=cardanoscan` against a fixture tx and grep-
asserts that the rendered output contains at least one
`cardanoscan.io` URL for each leaf class (tx hash, tx-in,
address, stake address, policy id, asset fingerprint) the fixture
exercises.

**Acceptance Scenarios**:

1. **Given** a Conway tx whose body has at least one tx hash, tx-in,
   payment address, stake address, policy id, and asset fingerprint,
   **When** the reviewer runs `tx-inspect <tx> --links=cardanoscan`,
   **Then** the rendered tree contains a `cardanoscan.io` (or
   `preprod.cardanoscan.io` / `preview.cardanoscan.io`) URL for each
   of those leaf classes, no other behavior changes, and exit code
   is 0.
2. **Given** the same transaction, **When** the reviewer omits
   `--links`, **Then** the rendered output is byte-for-byte
   identical to the pre-#88 output (the existing inspect goldens
   continue to pass unchanged).

## Functional Requirements

- **FR-001 (Leaf ADT)**. The library exposes an `InspectLeaf` ADT
  covering: `InspectTxHash TxHash`, `InspectTxIn TxHash Word64`,
  `InspectPaymentAddress Bech32`, `InspectStakeAddress Bech32`,
  `InspectPolicyId PolicyId`, `InspectAssetFingerprint Bech32` (CIP-14
  `asset1...`). Constructors are exported.
- **FR-002 (Network ADT)**. The library exposes `Network = Mainnet |
  Preprod | Preview`. A constructor from `NetworkMagic` is
  provided; unknown magics produce a typed error. The error type is
  exported.
- **FR-003 (Mapper totality)**. `cardanoscanUrl :: Network ->
  InspectLeaf -> Url` is total — no `Maybe`, no partiality. Every
  constructor maps to a URL on every network.
- **FR-004 (URL shape, mainnet)**. On `Mainnet` the host is
  `cardanoscan.io` (HTTPS) and the path is:
    * `/transaction/<hash>` for `InspectTxHash` and `InspectTxIn`
    * `/address/<bech32>` for `InspectPaymentAddress`
    * `/stakekey/<bech32>` for `InspectStakeAddress`
    * `/tokenPolicy/<policy-hex>` for `InspectPolicyId`
    * `/token/<asset-fingerprint>` for `InspectAssetFingerprint`
- **FR-005 (URL shape, testnets)**. On `Preprod` and `Preview` the
  host is `preprod.cardanoscan.io` and `preview.cardanoscan.io`
  respectively; paths are identical to mainnet.
- **FR-006 (CLI flag)**. `tx-inspect` accepts `--links=<linker>`
  where `<linker> = cardanoscan` is the only supported value in this
  ticket. Absence of the flag keeps the default rendering unchanged.
  Other values produce a parser error.
- **FR-007 (Network selection — corrected in slice S2)**. The
  network is supplied by the new `--network=<m|p|pv>` flag and
  defaults to `mainnet`. The original `infer from N2C` shape was
  withdrawn during planning: `tx-inspect` runs in unresolved-render
  mode (no N2C) as a first-class path, and forcing N2C-open
  whenever `--links` is set would regress that path. Explicit
  `--network=preprod` / `--network=preview` select the matching
  Cardanoscan host. Other values produce a parser error. The
  `parseNetworkMagic` function and its typed
  `UnsupportedNetworkMagic` error remain exported by the library
  for callers that *do* hold a magic — e.g. the `tx-validate`
  surface — and may be used by a future tx-inspect enhancement
  that infers the default. The behavior and the parser error are
  documented in `tx-inspect --help`.
- **FR-008 (Tree annotation)**. When the flag is set, every leaf
  whose `ConwayDiffValue` constructor (or the existing rename
  layer's leaf identification) classifies it as one of the
  `InspectLeaf` variants in FR-001 is annotated in the rendered
  output with its Cardanoscan URL. Leaves outside those classes are
  unchanged.
- **FR-009 (Default unchanged)**. When the flag is absent, the
  rendered output is byte-for-byte identical to the pre-#88 output
  for the same input. Existing inspect goldens pass unchanged.
- **FR-010 (Extension point)**. The library leaves room for
  additional linkers (`cexplorer`, `cardanoexplorer`, …) by typing
  the URL emitter as a function of `InspectLeaf` (a `LeafLinker`
  type alias is acceptable). No second linker ships in this ticket.

## Non-functional / quality attributes

- **NFR-001 (Purity)**. The library mapping does no I/O and lives in
  a pure module. Imports are restricted to bytestring / text /
  url-encoding primitives plus the existing ledger leaf types.
- **NFR-002 (URL well-formedness)**. Every URL the mapper returns
  parses back to scheme + host + path (verified by QuickCheck
  property).
- **NFR-003 (No default change)**. Existing inspect goldens MUST
  pass unchanged. The CHANGELOG entry for this ticket calls out
  that the flag is strictly opt-in.

## Deliverables

| Artifact | Surface | Notes |
|---|---|---|
| `src/Cardano/Tx/Diff/Scan.hs` (new module) | source | `InspectLeaf`, `Network`, typed `NetworkMagic` error, `LeafLinker`, `cardanoscanUrl`. |
| `cardano-tx-tools.cabal` exposure | source | New module exposed under the library stanza. |
| Unit tests | `test/unit/Cardano/Tx/Diff/ScanSpec.hs` | Per-variant golden URL strings (mainnet + one testnet); QuickCheck round-trip property. |
| `tx-inspect` CLI flag | `app/tx-inspect/Main.hs` | `--links=cardanoscan` parser, network inference, annotation pass. |
| `scripts/smoke/tx-inspect` | smoke surface | Extend the existing smoke to invoke the operator command with `--links=cardanoscan` and grep-assert URLs for each exercised leaf class. |
| `docs/tx-inspect.md` | mkdocs | Document the new flag, the inferred-network rule, and the typed error on unsupported magics. |
| `docs/assets/asciinema/tx-inspect.cast` (+ `scripts/tx-inspect.sh`) | asciinema | Re-record so the cast demonstrates `--links=cardanoscan` against the existing fixture. Verify the preview URL loads the cast (env-overridable `site_url` already wired). |
| `README.md` | top-level docs | If the README lists tx-inspect flags, append `--links=cardanoscan`. Otherwise no change. |
| `CHANGELOG.md` | release notes | Single bullet under the next unreleased section. |
| `.github/workflows/release.yml` / `darwin-release.yml` / `darwin-dev-homebrew.yml` | release pipelines | **No new wiring** — `tx-inspect` is already shipped; the flag is additive within the same binary. (Verified by `git grep -l 'tx-inspect' .github/`.) |

The release pipelines row is enumerated explicitly so the
deliverables-coverage check passes the analyzer — every surface the
canonical peer (`tx-inspect` itself) lives on is considered, and the
no-op rationale is recorded.

## Non-goals / Out of scope

- **Other explorers.** The `LeafLinker` extension point exists but no
  second linker (`cexplorer`, `cardanoexplorer`, …) ships in this
  ticket.
- **HTML / JSON / OSC 8 hyperlink renderers** for `tx-inspect`. The
  flag annotates the existing text tree only. Terminal-hyperlink
  upgrades are a future ticket.
- **Output-index highlighting** on tx-in links. The link points at
  the producing transaction page; opening the specific output via
  `#ix=…` or similar is out of scope.
- **`tx-diff` CLI integration.** The shared substrate change (if any)
  is unavoidable but no new `tx-diff` flag ships in this ticket.
- **Default-output changes.** The flag is strictly opt-in. Goldens
  remain stable.
- **Address-book rename interaction.** When a leaf is renamed by the
  existing rewrite layer, the URL still resolves against the
  original on-chain identifier (rename is presentation; the link is
  ground truth). The behavior is unchanged from a leaf's perspective
  — the rename layer continues to produce the displayed text; the
  scan layer reads the underlying ledger leaf.

## Command-recovery

**Command-recovery:** yes
Operator command:

```bash
tx-inspect <tx-input> [--rules <yaml>] --links=cardanoscan
```

The shipped command is the P1 user story for User Story 2. The
smoke proves the command path; it does not replace the command.

## Glossary

- **Leaf**. A value-bearing node of the inspect projection — a
  `ConwayDiffValue` whose constructor identifies the leaf class.
- **Cardanoscan**. The explorer at `cardanoscan.io` (and its
  preprod / preview hosts). One of several Cardano block explorers;
  the only one wired in this ticket.
- **CIP-14 asset fingerprint**. The bech32 `asset1...` identifier
  derived from policy id + asset name; the canonical user-pasteable
  identifier for a native asset.

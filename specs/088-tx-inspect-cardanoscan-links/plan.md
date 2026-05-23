# Implementation Plan: tx-inspect Cardanoscan link mapper (#88)

**Spec**: [spec.md](./spec.md). **Issue**: #88. **PR**: #89.

## Orchestration model

Solo. The orchestrator drives every slice itself, RED → GREEN per
slice, one bisect-safe commit per slice, every commit observes
`./gate.sh` green.

## Design at a glance

```
                       (pure)
+----------------------------+         +-----------------------+
|  Cardano.Tx.Diff.Scan      |         | Cardano.Tx.Diff       |
|  ------------------------- |         | --------------------- |
|  data InspectLeaf =        |         | data ConwayDiffValue  |
|    InspectTxHash | TxIn |  |  bridge | (existing, unchanged) |
|    PaymentAddress |        |  <------|                       |
|    StakeAddress |          |  classifyConwayLeaf             |
|    PolicyId |              |                                 |
|    AssetFingerprint        |                                 |
|                            |  HumanRenderOptions gains       |
|  data Network = Mainnet |  |    humanLeafLinker ::           |
|    Preprod | Preview       |      Maybe (ConwayDiffValue ->  |
|                            |             Maybe Url)          |
|  cardanoscanUrl ::         |                                 |
|    Network -> InspectLeaf  |  collectValueTrie consults the  |
|      -> Url                |  linker; on Just url it appends |
|                            |  ` [url]` to the rendered leaf  |
|  classifyConwayLeaf ::     |                                 |
|    ConwayDiffValue ->      |                                 |
|      Maybe InspectLeaf     |                                 |
|                            |                                 |
|  scanLinker ::             |                                 |
|    Network ->              |                                 |
|      ConwayDiffValue ->    |                                 |
|        Maybe Url           |                                 |
+----------------------------+         +-----------------------+

                    +-----------------+
                    | tx-inspect CLI  |
                    | --------------- |
                    | --links=cardano-|
                    |   scan          |
                    | --network=...   |
                    |                 |
                    | wires           |
                    |   scanLinker    |
                    |   into          |
                    |   HumanRender-  |
                    |   Options       |
                    +-----------------+
```

### Module boundaries

- **`Cardano.Tx.Diff.Scan`** (new). Pure. Owns `InspectLeaf`,
  `Network`, the typed `UnsupportedNetworkMagic`, `cardanoscanUrl`,
  `classifyConwayLeaf`, and `scanLinker`. Depends on existing leaf
  types from `Cardano.Tx.Diff` (the `ConwayDiffValue` ADT) — that
  is a sibling import inside the same package, no cycle. No I/O.
- **`Cardano.Tx.Diff`** (existing). Gains one field on
  `HumanRenderOptions`: `humanLeafLinker :: Maybe LeafLinker`
  where `type LeafLinker = ConwayDiffValue -> Maybe Url`. The
  trie walker (`collectValueTrie` and friends) consults the linker
  at every atomic-leaf insertion. The renamed-leaf branch also
  consults the linker against the original `ConwayDiffValue` (the
  link is ground truth; rename is presentation).
- **`app/tx-inspect/Main.hs`** (existing). Gains `--links` (default
  off) and `--network=mainnet|preprod|preview` (default `mainnet`).
  When `--links=cardanoscan` is set, the linker is wired:
  `Just (scanLinker network)`. When absent, `Nothing` — output is
  byte-for-byte identical to today.

### Network-source decision (planning-phase correction)

The spec FR-007 said "infer from the N2C provider in use." On
closer reading, tx-inspect does **not** always have an N2C provider
open — the existing smoke runs with no resolver flag and no
`--socket`, and unresolved renders are a first-class mode. Forcing
N2C to be open whenever `--links` is set would regress the
unresolved-render path.

**Decision**: a separate `--network=<m|p|pv>` flag, default
`mainnet`, is the source of truth for the explorer host. The
N2C-inference path is a follow-up enhancement (open a new issue if
desired; not required by #88's acceptance criteria, which only
demand that the right host appear for each network — not that the
network be auto-detected). The spec is corrected in the same
slice that introduces the flag.

Behavior:

- `--links=cardanoscan` without `--network` → `mainnet`.
- `--links=cardanoscan --network=preprod` → `preprod.cardanoscan.io`.
- `--network=...` alone (no `--links`) → ignored (no annotation
  pass), and the parser allows it for future use.

### Rendering surface

The leaf-link annotation lands at the trie node level: each
atomic leaf node carries its rendered text and (when the linker
returns `Just url`) a trailing ` [url]`. Tree art and indentation
are unchanged. Path-shape (`RenderPaths`) output is also annotated
the same way (one URL per matched value line); the same
`collectValueTrie` walks for both shapes today.

### Test surface

- **Unit (Scan)**. Per-variant golden URLs on mainnet and on
  `Preprod`. QuickCheck property: every `(Network, InspectLeaf)`
  renders to a URL whose `Network.URI` parse is `Just` with non-
  empty scheme + host + path.
- **Unit (Inspect render)**. A focused render test passes a fake
  `LeafLinker` (returns `Just "URL[<leaf>]"`) and asserts the
  rendered tree carries the marker next to the matched leaves and
  is otherwise unchanged. Lives alongside existing inspect specs.
- **Goldens (existing inspect/diff)**. Run unchanged. The default
  output path is asserted byte-stable by the fact that
  `humanLeafLinker = Nothing` short-circuits annotation.
- **Smoke**. New Assertion 9 in `scripts/smoke/tx-inspect`: invoke
  `tx-inspect --rules <amaru-rules> <amaru-swap-1> --links=
  cardanoscan --network=mainnet` and grep-assert at least one
  `https://cardanoscan.io/transaction/`, `/address/`,
  `/tokenPolicy/`, `/token/`, and `/stakekey/` URL appears.
  (Stake-key only if the Amaru fixture exercises one; if not, the
  per-class assertion drops to "every class present in the
  fixture has a URL" — the unit + property test covers totality
  across classes.)

### Live-boundary diagnostic

*"What system boundary does this exercise that the unit suite
cannot?"* — Almost none. URL rendering is pure; the only
boundary the smoke exercises that units do not is the **CLI
argument parser** for `--links` and `--network` and their
interaction with existing flags. The smoke assertion is the
right place; no operator follow-up needed.

## Slices (bisect-safe, vertical)

Each slice is one commit. Each commit observes `./gate.sh` green.

### Slice S1 — Scan library + unit tests

Adds the pure module and its full unit/property coverage. No CLI
change, no render-time hook. Build must be green; existing tests
keep passing. **The library module is unreachable from production
code at this point** — that wiring lands in S2 — so this slice is
proof-by-tests.

- `src/Cardano/Tx/Diff/Scan.hs` — new module: `InspectLeaf`,
  `Network`, `UnsupportedNetworkMagic`, `LeafLinker` (newtype or
  type alias TBD by the implementation), `cardanoscanUrl`,
  `classifyConwayLeaf`, `scanLinker`, `parseNetworkMagic`.
- `cardano-tx-tools.cabal` — expose `Cardano.Tx.Diff.Scan` under
  the library stanza.
- `test/unit/Cardano/Tx/Diff/ScanSpec.hs` — per-variant URL
  goldens (mainnet + preprod), QuickCheck round-trip property,
  one `classifyConwayLeaf` smoke against a stock `ConwayDiffValue`
  per class.
- `cardano-tx-tools.cabal` — register the new spec in
  `unit-tests` `other-modules`.

Commit shape: `feat(scan): add Cardano.Tx.Diff.Scan with
cardanoscanUrl mapper. Tasks: T001, T002, T003, T004.`

### Slice S2 — Render-time hook + CLI flag + smoke assertion

Wires the library into the renderer and the CLI. This is the
slice that delivers the operator-facing P1.

- `src/Cardano/Tx/Diff.hs` — add `humanLeafLinker :: Maybe
  LeafLinker` to `HumanRenderOptions`; update
  `defaultHumanRenderOptions`; consult the linker in
  `collectValueTrie` (both the renamed-leaf branch and the
  atomic-leaf branch). Annotation shape: `<rendered> [<url>]`.
- `src/Cardano/Tx/Diff.hs` (re-exports) — also re-export
  `LeafLinker` from `Cardano.Tx.Diff` so callers don't need a
  second import for the hook type.
- `app/tx-inspect/Main.hs` — add `--links=cardanoscan` and
  `--network=mainnet|preprod|preview` parsers; default
  `--network=mainnet`; on `--links=cardanoscan` install
  `Just (scanLinker network)` in `HumanRenderOptions`.
- `app/tx-inspect/Main.hs` — `--help` text documents the flags
  and the mainnet default.
- `test/unit/.../InspectSpec.hs` (or sibling) — a focused render
  test that installs a fake linker (`\_ -> Just "URL"`) and
  asserts the marker appears next to expected leaves and is
  absent from non-leaf rows.
- `scripts/smoke/tx-inspect` — new Assertion 9: `--links=
  cardanoscan --network=mainnet` against the Amaru swap-1 fixture
  grep-asserts at least one `https://cardanoscan.io/transaction/`,
  `/address/`, `/tokenPolicy/`, and `/token/` URL.
- `test/fixtures/.../inspect.verbatim.unresolved.txt`,
  `inspect.collapse-only.txt`, `inspect.rename-only.unresolved.txt`,
  `inspect.amaru.both.txt` — re-checked unchanged (default
  output stays byte-stable when the flag is absent).
- Update the `spec.md` FR-007 paragraph with the planning-phase
  correction noted above (in this slice, so the spec matches the
  implementation it ships with).

Commit shape: `feat(tx-inspect): add --links=cardanoscan and
--network flags with render-time leaf linker. Tasks: T005, T006,
T007, T008, T009, T010.`

### Slice S3 — Operator docs

Updates the mkdocs page so an operator can discover the flags
without reading the changelog.

- `docs/tx-inspect.md` — describe `--links=cardanoscan` and
  `--network`, the mainnet default, and the typed parser error
  on unsupported `--network` values. Note the rename-vs-link
  ground-truth rule (renames are presentation; links are real
  ledger leaves).
- `CHANGELOG.md` — one bullet under the next unreleased section.

Commit shape: `docs(tx-inspect): document --links=cardanoscan and
--network. Tasks: T011, T012.`

### Slice S4 — Asciinema cast refresh

Re-records the cast against the new surface. Verifies the
preview URL loads the cast (env-overridable `site_url` already
wired in the repo per the deliverables row).

- `docs/assets/asciinema/scripts/tx-inspect.sh` — extend the demo
  script to invoke `--links=cardanoscan` against the existing
  fixture so the recorded session shows the new behavior.
- `docs/assets/asciinema/tx-inspect.cast` — regenerated cast.
- Verify mkdocs preview build is green (`gate.sh` doesn't cover
  mkdocs; the verification is by inspecting the docs preview
  job in CI after push, and by running `mkdocs build --strict`
  locally where the toolchain is available).

Commit shape: `chore(docs): re-record tx-inspect asciinema cast
with --links demo. Tasks: T013.`

### Slice S5 — Finalize

- `chore: drop gate.sh (ready for review)` — `git rm gate.sh` +
  `gh pr ready`.

## Risks / Edge cases / Open notes

- **Renamed-leaf links**. A leaf renamed by the existing rename
  layer (e.g. `amaru.swap-order` instead of a script-hash) still
  resolves the URL against the original `ConwayDiffValue`. This
  is the natural fall-through in `collectValueTrie`'s renamed
  branch; documented and explicitly covered by an Amaru smoke
  grep assertion.
- **Asset fingerprint**. Cardanoscan uses the CIP-14 `asset1...`
  fingerprint for `/token/`. The renderer's leaves carry policy
  id and asset name separately; the `classifyConwayLeaf` function
  computes the CIP-14 bech32 inside `Cardano.Tx.Diff.Scan`. (No
  new dependency: the existing project pulls `bech32` via the
  ledger stack.)
- **Default-network choice**. Mainnet is the dominant operator
  case (treasury work). Operators inspecting a testnet tx pass
  `--network=preprod` or `--network=preview` explicitly. The
  parser fails fast on any other value (typed `optparse-
  applicative` reader).
- **OSC 8 / terminal-aware hyperlinks**. Out of scope per
  spec; the bracketed-URL annotation works in any text-aware
  renderer (CI logs, terminals without OSC 8, GitHub diffs,
  `less`, etc.) and is the safer default.
- **Goldens drift risk**. Mitigated structurally: the renderer
  only annotates when `humanLeafLinker = Just _`, and the default
  is `Nothing`. Every existing golden runs through the default
  path. Slice S2 cross-checks the existing goldens explicitly.

## Process notes

- TDD per slice: write the failing test(s), observe failing,
  implement, observe passing, run `./gate.sh`, commit.
- Every behavior-changing commit body carries a `Tasks: T###`
  trailer.
- `tasks.md` checkbox updates ride with the slice commit via
  `git commit --amend`.
- No `speckit-implement`. No subagents.
- Plan corrections after the first behavior-changing slice land
  as forward `docs:` / `chore:` commits, not in-place rewrites.

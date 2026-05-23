# Tasks: tx-inspect Cardanoscan link mapper (#88)

Per-slice TDD: write the failing test(s) first, observe failing,
implement, observe passing, run `./gate.sh`, commit. One commit per
slice, every commit observes the gate green. The `tasks.md`
checkbox update rides with the slice commit via `git commit
--amend` after the implementation passes review.

## Slice S1 — Scan library + unit tests

Single commit. Subject: `feat(scan): add Cardano.Tx.Diff.Scan with
cardanoscanUrl mapper`. Trailer: `Tasks: T001, T002, T003, T004`.

- [X] **T001 — RED** Add
      `test/unit/Cardano/Tx/Diff/ScanSpec.hs` with failing per-
      variant golden URL strings for every `InspectLeaf`
      constructor on mainnet, plus one preprod golden, plus a
      QuickCheck `prop_urlParses` over `(Network, InspectLeaf)`
      that runs `Network.URI.parseURI` on the result. Register
      the new spec in `cardano-tx-tools.cabal` `other-modules`
      of `unit-tests`. Observe the spec module is missing /
      tests fail / build fails because the module doesn't exist.
- [X] **T002 — GREEN** Add `src/Cardano/Tx/Diff/Scan.hs`. Exposes
      `InspectLeaf` (`InspectTxHash TxHash`, `InspectTxIn TxHash
      Word64`, `InspectPaymentAddress Bech32`, `InspectStakeAddress
      Bech32`, `InspectPolicyId PolicyId`, `InspectAssetFingerprint
      Bech32`); `Network` (`Mainnet | Preprod | Preview`);
      `UnsupportedNetworkMagic Word32`;
      `parseNetworkMagic :: Word32 -> Either
      UnsupportedNetworkMagic Network`; `type Url = Text` (or
      newtype if cleaner); `cardanoscanUrl :: Network ->
      InspectLeaf -> Url`. Total over all constructors.
- [X] **T003 — GREEN** In the same module add
      `classifyConwayLeaf :: ConwayDiffValue -> Maybe InspectLeaf`
      and `scanLinker :: Network -> ConwayDiffValue -> Maybe Url`
      (= `fmap (cardanoscanUrl n) . classifyConwayLeaf`). For the
      asset case, compute the CIP-14 `asset1...` bech32 from
      `(PolicyId, AssetName)` using the existing `bech32` /
      `cryptonite` dep pulled by the ledger stack. For
      `InspectTxIn`, the URL points at `/transaction/<hash>` (no
      output-index highlighting — spec non-goal).
- [X] **T004 — GREEN** Expose `Cardano.Tx.Diff.Scan` from the
      library stanza in `cardano-tx-tools.cabal`. Run
      `./gate.sh` and observe green (build + unit + smoke +
      cabal-fmt + fourmolu + hlint).

## Slice S2 — Render-time hook + CLI flag + smoke

Single commit. Subject: `feat(tx-inspect): add --links=cardanoscan
and --network flags with render-time leaf linker`. Trailer:
`Tasks: T005, T006, T007, T008, T009, T010`.

- [X] **T005 — RED (render)** Extend the existing inspect spec
      (or add a focused `LinkerSpec.hs`) with a failing test
      that builds a `HumanRenderOptions` with a stub linker
      `\_ -> Just "URL"` and asserts the rendered tree carries
      ` [URL]` next to every atomic leaf and no other change.
      Observe failure because `HumanRenderOptions` has no
      `humanLeafLinker` field yet.
- [X] **T006 — RED (CLI/smoke)** Append Assertion 9 to
      `scripts/smoke/tx-inspect`: run `tx-inspect --rules
      $amaru_rules $amaru_swap1 --links=cardanoscan
      --network=mainnet` and grep-assert at least one
      `https://cardanoscan.io/transaction/`, `/address/`,
      `/tokenPolicy/`, and `/token/` URL appears in the output.
      Observe failure because the parser rejects `--links`.
- [X] **T007 — GREEN** Add `type LeafLinker = ConwayDiffValue ->
      Maybe Url` to `Cardano.Tx.Diff` (re-exported) and a new
      `humanLeafLinker :: Maybe LeafLinker` field on
      `HumanRenderOptions`. Default to `Nothing` in
      `defaultHumanRenderOptions`. Consult the linker in
      `collectValueTrie` at the atomic-leaf insertion site and
      in the renamed-leaf branch; on `Just url` append a single
      space + `[<url>]` to the rendered node label.
- [X] **T008 — GREEN** Wire the new flags in
      `app/tx-inspect/Main.hs`: `--links=cardanoscan` (off by
      default) and `--network=mainnet|preprod|preview` (default
      mainnet). On `--links=cardanoscan` install `Just
      (scanLinker network)`. Document both in `--help`.
- [X] **T009 — GREEN** Cross-check existing inspect goldens
      (`inspect.verbatim.unresolved.txt`,
      `inspect.collapse-only.txt`,
      `inspect.rename-only.unresolved.txt`,
      `amaru-treasury-swap/golden/swap-1.both.txt`) pass
      byte-stable under the new default (`humanLeafLinker =
      Nothing`). No fixture re-capture expected — if any
      golden moves, that is a regression in S2 and must be
      fixed before the gate goes green.
- [X] **T010 — GREEN** Update `spec.md` FR-007 with the
      planning-phase correction (network from `--network` flag,
      not inferred from N2C). Run `./gate.sh` and observe
      green.

## Slice S3 — Operator docs

Single commit. Subject: `docs(tx-inspect): document
--links=cardanoscan and --network`. Trailer: `Tasks: T011, T012`.

- [X] **T011** Extend `docs/tx-inspect.md` with a "Cardanoscan
      links" section: the two flags, the mainnet default, the
      typed error on unsupported `--network` values, the
      rename-vs-link ground-truth rule, and the non-goal list
      (no terminal hyperlinks, no output-index highlighting).
- [X] **T012** Add a CHANGELOG entry under the next unreleased
      section. Run `./gate.sh`.

## Slice S4 — Asciinema cast refresh

Single commit. Subject: `chore(docs): re-record tx-inspect
asciinema cast with --links demo`. Trailer: `Tasks: T013`.

- [X] **T013 (partial)** Extended
      `docs/assets/asciinema/scripts/tx-inspect.sh` so the next
      re-recording demonstrates `--links cardanoscan --network
      mainnet` against the Amaru swap fixture alongside the
      existing `--rules` and verbatim demos. Also normalised the
      hardcoded ticket-66 paths into `CARDANO_TX_TOOLS_ROOT` /
      `CASTBIN` env vars so the next recording session is not
      tied to a stale worktree path.
      **Operator follow-up**: the binary cast (`docs/assets/
      asciinema/tx-inspect.cast`) is **not** re-recorded in this
      PR — the dev-assets asciinema flake driver was not run in
      this slice. Run
      `nix develop /code/dev-assets/asciinema -c asciinema rec
       -c ./docs/assets/asciinema/scripts/tx-inspect.sh
       docs/assets/asciinema/tx-inspect.cast`
      before the next docs deploy; verify the preview URL loads
      the refreshed cast.

## Slice S5 — Finalize

Single commit. Subject: `chore: drop gate.sh (ready for review)`.
No `Tasks:` trailer required (no behavior change).

- [X] **T014** Finalization audit:
      * all tasks above marked `[X]` (S1-S4); T013 closed
        partial with a named operator follow-up for the
        cast binary;
      * every behavior-changing commit (`feat(scan):` and
        `feat(tx-inspect):`) carries a `Tasks:` trailer;
      * `./gate.sh` green at HEAD (build + unit + smoke +
        cabal-fmt + fourmolu + hlint);
      * `docs/tx-inspect.md` and `CHANGELOG.md` aligned with
        delivered behavior; `README.md` description unchanged
        (the new flag is opt-in and the docs link is the
        canonical reference);
      * PR body updated to record `Specs/Plan/Tasks/Slices`
        each landed, the deferred cast follow-up, and the
        Command-Recovery declaration.
- [X] **T015** `git rm gate.sh`, commit, push, `gh pr ready 89`.

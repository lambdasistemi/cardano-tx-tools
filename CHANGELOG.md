# Changelog

## Unreleased

### Features

* **058:** `Cardano.Tx.Graph.Emit` — Conway transaction body emitter
  closing the body-emitter half of epic #46's Wave 2. Walks
  `Cardano.Tx.Diff.conwayDiffProjection` over a `(ConwayTx, ResolvedUTxO,
  [EntityDecl])` triple and renders the joint RDF graph as canonical
  Turtle (byte-diff anchor) or JSON-LD (set-equivalent triple set). Body
  leaves covered: inputs, outputs, addresses with payment + stake
  credentials, fee, mint (Mint + Policy + AssetClass clusters),
  withdrawal, certificates (StakeDelegation + VoteDelegation
  PubKeyCerts with Pool + DRep targets), collateral inputs, and
  TreasuryWithdrawal proposals (as `cardano:Datum + decodedAs`
  envelopes — forward-compatible with #50's CIP-57 blueprint decode).
  Credentials resolve against the operator-entity overlay via a typed
  `(LeafType, ByteString) → BnodeName` lookup; uncovered credentials
  fall through to a deterministic raw-bytes naming scheme
  (`_:cred_<rolePrefix>_<bytes-prefix>`, prefix = 16 hex chars per
  research R3). The `Cardano.Tx.Graph.Emit.Vocab` registry is the
  single-source-of-truth for every `cardano:` Phase A IRI the emitter
  writes; `VocabTraceabilitySpec` asserts per-emit URI namespacing
  (cardano + rdfs + fixture-local prefixes only; no foreign-namespace
  IRIs leak) across all 11 fixtures. Anchored by a 33-invariant
  cross-fixture spec and an 11/11 byte-diff golden against the
  regenerated `expected.ttl` (the artisan files merged in #45 are
  obsoleted by the regen and their narrative content migrated to a
  new per-fixture `NOTES.md` markdown file). `ReproducibilitySpec`
  asserts byte-equal output across two emit runs per fixture (SC-004
  closes the determinism contract).
* **058:** `tx-graph` executable extends with `--tx`, `--utxo`, `--out`,
  `--format` flags. Flag-presence dispatch over three modes: overlay-only
  (existing `--rules` invocation; #48 back-compat preserved), body-only
  (`--tx`, optionally `--utxo`), and joint (`--tx --utxo --rules`).
  `--format turtle|json-ld` selects the serializer; `--out FILE`
  defaults to stdout. CBOR decoding via the ledger's `decodeFullAnnotator`;
  UTxO JSON via aeson. Structured errors with single-line stderr
  rendering follow the `renderRulesLoadError` pattern from #48.
* **058:** `Cardano.Tx.Graph.Rules.Load.RulesLoadResult` gains a new
  field `rulesEntities :: [EntityDecl]` exposing the deduped in-memory
  entity list the loader already computes. Additive at the record
  level (`rulesOverlayTurtle` + `rulesWarnings` consumers unaffected);
  the body emitter consumes the new field directly without re-parsing
  overlay Turtle.
* **058:** The 11 `test/fixtures/rewrite-redesign/<NN>-*/expected.ttl`
  files are **regenerated** from the body emitter's output (Q-001 →
  A-001 of #58 PR). Loader-deterministic blank-node names, ledger-
  authoritative `bytesHex`, ledger-derived fee, and machine-uniform
  section headers replace the artisan layout merged in #45. The
  artisan narrative migrates to a new per-fixture
  `test/fixtures/rewrite-redesign/<NN>-*/NOTES.md` markdown file.
  `EmitGoldenSpec` byte-diffs the emitter output against the
  regenerated files (11/11 GREEN; SC-001 closes).
* **048:** `Cardano.Tx.Graph.Rules.Load` — operator-rules loader for Turtle
  + YAML sugar with `owl:imports` / `imports:` composition, deterministic
  blank-node + entity-IRI naming (slug-everywhere; one bnode per shared
  `(leafType, bytesHex)` identity), structured validation errors with
  file + line provenance, cycle detection, and `DuplicateEntityAcrossFiles`
  warnings. Companion executable `tx-graph` (with `--rules <file>` flag)
  prints the canonical operator-entity overlay on stdout. Anchors the
  Wave-2 entry point for epic #46; per-fixture `expected.entities.ttl`
  byte-diff goldens cover all 11 `rewrite-redesign` fixtures. **#58
  ships the body-emitter half of the Wave 2 contract** (above) — the
  `--utxo`, `--out`, `--tx`, `--format` flags previously deferred have
  landed.

### Maintenance

* **048:** Constitution-compliance sweep — `cabal check` is now clean
  across every stanza (PvP upper bounds added) and `-Werror` is gated
  behind a manual `werror` cabal flag enabled from `cabal.project` and
  the haskell.nix build. `./gate.sh` runs `cabal check` + `cabal haddock`
  alongside the existing build / unit / cabal-fmt / fourmolu / hlint
  steps.

## [0.1.5.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.1.4.0...v0.1.5.0) (2026-05-18)

### Features

* **032:** tx-inspect baseline — add renderConwayTxHuman + parse RewriteRules + wire executable ([e43a3c7](https://github.com/lambdasistemi/cardano-tx-tools/commit/e43a3c7d92f3b159a6f442aa0b370ba66c705015))
* **032:** apply collapse rules from RewriteRules in tx-inspect ([f51237d](https://github.com/lambdasistemi/cardano-tx-tools/commit/f51237d9122a9266f01fe794e47ef649709e30cf))
* **032:** apply rename rules to payment addresses and script hashes in tx-inspect ([c6feef5](https://github.com/lambdasistemi/cardano-tx-tools/commit/c6feef5121ea0b9d59c7c2ced76de2458fb20921))
* **032:** add Amaru treasury swap fixtures and shared-substrate goldens ([88f7b80](https://github.com/lambdasistemi/cardano-tx-tools/commit/88f7b80b261e296359958e6fd6874147c66cdf3e))
* **032:** resolve Amaru InspectSpec inputs and suppress empty TxOut leaves ([5e444cd](https://github.com/lambdasistemi/cardano-tx-tools/commit/5e444cdc15f3e870e14c06efded48b0c7b04262b))

## [0.1.4.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.1.3.0...v0.1.4.0) (2026-05-17)

### Features

* **022:** port tx-sign vault + witness from amaru-treasury-tx ([1203f29](https://github.com/lambdasistemi/cardano-tx-tools/commit/1203f298e24335630a6e3029dfbf73b3b5ee847c))
* **015:** cabal wiring + Cardano.Tx.Validate.Cli scaffold + Session ([015cd55](https://github.com/lambdasistemi/cardano-tx-tools/commit/015cd554518270a0c97daba6f2cc6edc27912626))
* **015:** parser + verdict + human renderer + Main + US1 happy path ([7f10cb9](https://github.com/lambdasistemi/cardano-tx-tools/commit/7f10cb9549a9aef3a82241b49bbbaa4cb5a10764))
* **015:** pre-fix body surfaces structural failure (SC-003) ([f99f711](https://github.com/lambdasistemi/cardano-tx-tools/commit/f99f711b7c2b949f5baff71278e63852ee300bc6))
* **015:** JSON envelope renderer + --output json wiring ([4af0c22](https://github.com/lambdasistemi/cardano-tx-tools/commit/4af0c225a0da8c7faa33ba75331e853f6468b2d4))
* **015:** release plumbing for tx-validate (AppImage / DEB / RPM / Darwin / Docker) ([741b8ab](https://github.com/lambdasistemi/cardano-tx-tools/commit/741b8ab934feebbd5afce56a5e372874d3d68620))
* **015:** wire github-release-check into tx-validate ([9b5c1b4](https://github.com/lambdasistemi/cardano-tx-tools/commit/9b5c1b4a5488609ac202b7739d1d2ed09dfb4d88))
* **015:** add --version flag to tx-validate ([5633c68](https://github.com/lambdasistemi/cardano-tx-tools/commit/5633c683dd6fb6568f3184d47c3992bf85ff8f43))
* **tx-validate:** adopt withCli + versionOption from github-release-check sublibrary ([b6d97f7](https://github.com/lambdasistemi/cardano-tx-tools/commit/b6d97f7724f7d16f578b51c82b3e19d19325d8a4))
* **tx-diff:** adopt withCli + versionOption from github-release-check sublibrary ([a8813a0](https://github.com/lambdasistemi/cardano-tx-tools/commit/a8813a06957f4cf04298bc3a45111f239dd54a1d))
* **cardano-tx-generator:** adopt withCli; inline --version short-circuit ([c638564](https://github.com/lambdasistemi/cardano-tx-tools/commit/c6385649c0b79fb01588252becb76a63641bf6d8))
* **tx-sign:** adopt withCli + versionOption from github-release-check sublibrary ([4dee555](https://github.com/lambdasistemi/cardano-tx-tools/commit/4dee555d9a5194bb99927d4060d86370dd34cc07))

## [0.1.3.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.1.2.0...v0.1.3.0) (2026-05-16)

### Features

* **014:** loadUtxo test helper resolves UTxO from producer-tx CBORs ([9c9d72e](https://github.com/lambdasistemi/cardano-tx-tools/commit/9c9d72e91839a4fa90a359c5d89279f7c722b53b))
* **014:** validatePhase1 kernel + post-fix happy-path test ([5c1f899](https://github.com/lambdasistemi/cardano-tx-tools/commit/5c1f89936b72de34025ea456158925146b2189b1))
* **014:** lift isWitnessCompletenessFailure onto the public surface ([a26a056](https://github.com/lambdasistemi/cardano-tx-tools/commit/a26a0560c3fab60b229dfcc9bfbe3352dbfc6ce7))
* **014:** pre-fix integrity-hash mutation locks SC-002 ([121da26](https://github.com/lambdasistemi/cardano-tx-tools/commit/121da26ce136371d9030f0160d8aa1c273b04fcd))
* **014:** zero-fee mutation locks FR-007 negative test ([8265218](https://github.com/lambdasistemi/cardano-tx-tools/commit/8265218d2235022a3fcadf364529d098b637f494))
* **014:** two-failure accumulating case locks SC-003 ([b5acea9](https://github.com/lambdasistemi/cardano-tx-tools/commit/b5acea99614c30e6bfd9a97f5288d292c54fc4b3))
* **014:** empty-UTxO mempool short-circuit edge case ([c4aeb1a](https://github.com/lambdasistemi/cardano-tx-tools/commit/c4aeb1a16df2733df8332d6e66d1aa0fe168d34b))

## [0.1.2.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.1.1.0...v0.1.2.0) (2026-05-15)

### Features

* import 6 e2e tests from cardano-node-clients (#11) ([e528dbe](https://github.com/lambdasistemi/cardano-tx-tools/commit/e528dbeb6816e552f790fcbfd745f1d25394a945))

### Bug Fixes

* **008:** derive language set from body, not caller; hash matches ledger ([c056219](https://github.com/lambdasistemi/cardano-tx-tools/commit/c0562192258ebceda6d654b207667f49656fa94a))

## [0.1.1.0](https://github.com/lambdasistemi/cardano-tx-tools/releases/tag/v0.1.1.0) (2026-05-15)

### Features

* bootstrap project scaffold ([2e5f954](https://github.com/lambdasistemi/cardano-tx-tools/commit/2e5f95458b0b5e58394f5aaa529408b61909c7e7))
* migrate lib-tx-build under Cardano.Tx.* ([3bf9d52](https://github.com/lambdasistemi/cardano-tx-tools/commit/3bf9d520fe660bc28448e942ebfa33c83238bc7d))
* migrate Blueprint, TxDiff stack, Evaluate, and tx-diff exe ([8325820](https://github.com/lambdasistemi/cardano-tx-tools/commit/8325820f03090b0dafbbc229b1c317c0cfcde697))
* port the tx-diff release pipeline from cardano-node-clients ([ce1d978](https://github.com/lambdasistemi/cardano-tx-tools/commit/ce1d978face3fde3ef96cf9f9b92173cb9e8f947))
* drop cardano-node-clients from the main library dependency ([22d0001](https://github.com/lambdasistemi/cardano-tx-tools/commit/22d0001edfeb41ce05dbff0513c0b9674292ec08))
* migrate cardano-tx-generator daemon under Cardano.Tx.Generator.* ([16f8e43](https://github.com/lambdasistemi/cardano-tx-tools/commit/16f8e4379042f034aed1711656cb305c923269b3))


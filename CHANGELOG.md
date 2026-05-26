# Changelog

## Unreleased

### Features

* **tx-fetch:** new executable. Closure-walking Conway CBOR fetcher. Resolves seed transaction ids over Blockfrost's `/txs/<hash>/cbor` endpoint, walks each tx's spending / reference / collateral input parents to `--depth`, hash-verifies every fetched CBOR against its requested `TxId`, and writes one `<out-dir>/cbor/<txid>.cbor` per tx plus `<out-dir>/seeds.txt`. Ships through the same release pipeline as the other tools (Linux AppImage / DEB / RPM, Darwin Homebrew). Closes part of [#115](https://github.com/lambdasistemi/cardano-tx-tools/issues/115).
* **114:** `tx-graph` CLI collapsed to a pure `(rules + [cbor]) → ttl` transformation. New `--in-dir DIR` reads a lattice of CBOR files and emits one `<txid>.ttl` per input, resolving each tx's inputs against the in-memory closure. Old `--utxo` / `--closure-dir` / `--n2c-socket-path` flags removed; `--tx PATH` becomes a positional argument. Closes [#114](https://github.com/lambdasistemi/cardano-tx-tools/issues/114).
* **051:** Packaged `tx-view` SPARQL view contracts for `cli-tree`, `asset-flow`, `entity-occurrences`, and `json-ld`, with the CLI surface locked to `--graph`, `--view`, and `--out`. Closes [#51](https://github.com/lambdasistemi/cardano-tx-tools/issues/51).
* **graph:** CIP-57 blueprint `"dataType": "map"` support in `Cardano.Tx.Blueprint`. New `SchemaMap BlueprintSchema BlueprintSchema` variant on `BlueprintSchemaKind`; parser reads `keys` + `values` sub-schemas; decoder materialises `PLC.Map` payloads as `OpenArray [OpenObject {"key" -> k, "value" -> v}, …]`; `resolveBlueprintSchema` recurses into key + value sub-schemas with the existing cycle detection. `parseBlueprintDefinitions` now surfaces parse failures via `BlueprintParseError` instead of silently dropping the failed entry (the silent drop hid the missing-map-support gap through every #50 slice — fixtures 12..14 happened not to use map-typed definitions). Live-fire on a real Conway treasury disburse (SundaeSwap treasury-contracts at commit `ad4316d0`) now emits `:TreasurySpendRedeemer_amount` typed predicates against the 5 Spend redeemers; pre-fix output was 5 `cardano:decodeError "BlueprintDefinitionMissing \"Pairs<…>\""` literals. Per-entry triple emission on the `OpenArray [OpenObject {key, value}]` shape (the typed-emit walker's OpenArray-of-OpenObject case) and the DSL-reconstructed real-Conway fixtures are deferred to sibling slices tracked via [#90](https://github.com/lambdasistemi/cardano-tx-tools/issues/90). Closes [#80](https://github.com/lambdasistemi/cardano-tx-tools/issues/80) ([#87](https://github.com/lambdasistemi/cardano-tx-tools/pull/87)).
* **090:** DSL-reconstructed real Conway amaru-treasury disburse fixtures `15-amaru-disburse-network-compliance` and `17-amaru-disburse-contingency` under `test/fixtures/rewrite-redesign/`. Pin current `SchemaMap` typed amount predicate behavior on the two real-Conway disburses while the typed-emit walker extension over the `OpenArray [OpenObject {key, value}]` shape (per-entry triple emission) remains deferred to a sibling slice. Closes [#90](https://github.com/lambdasistemi/cardano-tx-tools/issues/90).
* **tx-inspect:** new `--links cardanoscan` flag (opt-in) annotates every Cardanoscan-classifiable leaf in the rendered tree with its [Cardanoscan](https://cardanoscan.io) URL. `--network mainnet|preprod|preview` picks the explorer host; default is `mainnet`. Default output is byte-stable when the flag is absent. (#88)
* **lib:** new pure module `Cardano.Tx.Diff.Scan` exposes `cardanoscanUrl :: Network -> InspectLeaf -> Url`, total over all leaf constructors (tx hash, tx-in, payment / stake address, policy id, CIP-14 asset fingerprint), plus `parseNetworkMagic`, `classifyConwayLeaf`, and `scanLinker`. (#88)
* **095:** Typed-emit walker extension for SchemaMap-decoded `OpenArray [OpenObject {"key", "value"}, …]` values. The walker now mints one positional entry bnode per element under `:_<i>` and emits `:key` + `:value` triples on each entry through the existing `OpenValue` object path; non-matching arrays and objects with the wrong field shape keep the existing opaque bnode. `OpenValue` is unchanged (no `OpenMap` constructor); fixtures `15-amaru-disburse-network-compliance` and `17-amaru-disburse-contingency` regenerate to expose the per-entry triples under their `:TreasurySpendRedeemer_amount` child bnodes. Closes [#95](https://github.com/lambdasistemi/cardano-tx-tools/issues/95).

### Deferred / known limitations

* **098:** Follow-on [#98](https://github.com/lambdasistemi/cardano-tx-tools/issues/98) tracks deferred legacy 044 `expected.txt` byte-equivalence for the `cli-tree` view; #51 ships graph-derived view-side goldens for the packaged `tx-view` views.

## [0.2.2.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.2.1.0...v0.2.2.0) (2026-05-22)

### Features

* **050:** Emit.Blueprint — pure decoder + IRI minter (no emit wiring yet) ([17ed01c](https://github.com/lambdasistemi/cardano-tx-tools/commit/17ed01cdfb4035310691e2a02700bdf8e12b9459))
* **050:** emit accepts blueprint index; walker consults Emit.Blueprint ([8421a21](https://github.com/lambdasistemi/cardano-tx-tools/commit/8421a218a8fb594812976652c04b84a75d317072))
* **050:** fixture 12-blueprint-typed — typed SwapOrder datum emission ([9a715c1](https://github.com/lambdasistemi/cardano-tx-tools/commit/9a715c112925ac3ae74183eb5f7d826655f47540))
* **050:** fixture 13-blueprint-passthrough — no-blueprint path stays opaque ([cc5c839](https://github.com/lambdasistemi/cardano-tx-tools/commit/cc5c8395eb81b3d41aeae356faf449eefd56b91b))
* **050:** fixture 14-blueprint-decode-fail — decodeError literal + stderr warn ([39753c5](https://github.com/lambdasistemi/cardano-tx-tools/commit/39753c5ed7bba94f1592652b81a74920140530b7))
* **050:** refresh canonical-vocab pin to kmaps@5108855 + thread blueprint registry through strict vocab gate ([0d7d9ad](https://github.com/lambdasistemi/cardano-tx-tools/commit/0d7d9adaf3ed75c6eb1e987d01e612f734cd4dd3))

### Bug Fixes

* **tx-inspect:** render output native assets ([f41c357](https://github.com/lambdasistemi/cardano-tx-tools/commit/f41c3575fed0d38489ca23a4da935b9c5866678b))

## [0.2.1.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.2.0.0...v0.2.1.0) (2026-05-22)

### Features

* **build:** auto-compensate payTo outputs to ledger min-UTxO (#81) ([0b658f1](https://github.com/lambdasistemi/cardano-tx-tools/commit/0b658f1753e81b568fa360b39c0e558c982452c2))

### Bug Fixes

* **build:** assign payTo output index from the running counter ([587076b](https://github.com/lambdasistemi/cardano-tx-tools/commit/587076b053b58b193a126b745acb282cf8cc8b0e))

## [0.2.0.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.1.6.0...v0.2.0.0) (2026-05-20)

### Breaking Changes

* tx-graph N2C parity + cross-tool --n2c-socket-path rename ([7813a3b](https://github.com/lambdasistemi/cardano-tx-tools/commit/7813a3b0da678a961d5e224717a683aa17698d27))

### Features

* **release:** ship tx-graph in Linux release pipeline ([3730dee](https://github.com/lambdasistemi/cardano-tx-tools/commit/3730dee939824b373ee1a5541370b1cac4c81778))
* **docs:** asciinema casts for tx-graph, tx-validate, tx-inspect ([ea9b854](https://github.com/lambdasistemi/cardano-tx-tools/commit/ea9b854bcd7af77608e56cc740e6e13e873d2d8d))
* **release:** ship tx-graph on Darwin aarch64 + dev Homebrew tap ([77d9e94](https://github.com/lambdasistemi/cardano-tx-tools/commit/77d9e940b9cdca1903872b091e510092e2b531e6))
* **release:** harmonize CD across all 6 exes — factor + extend, in one matrix ([543a2c7](https://github.com/lambdasistemi/cardano-tx-tools/commit/543a2c7b06df4769b5be1ca62437f10dd7515146))

### Bug Fixes

* **docs:** use env-overridable site_url so asciinema casts resolve on PR previews ([ebd54e0](https://github.com/lambdasistemi/cardano-tx-tools/commit/ebd54e081eb166eab684dac3ed474ad3ea587f51))
* **ci:** clean site/ after docs build to prevent self-hosted runner contamination ([b6ee495](https://github.com/lambdasistemi/cardano-tx-tools/commit/b6ee4957a7be412c05e711a6876e0942a7cb7ab5))
* **docs:** re-record tx-graph cast — overlay-only, no truncation ([acea368](https://github.com/lambdasistemi/cardano-tx-tools/commit/acea368842394e4b15423359b429a6889538eb5d))
* **docs:** keep epic link on one line so Markdown doesn't parse '#46' as a heading ([651d11a](https://github.com/lambdasistemi/cardano-tx-tools/commit/651d11ad6eef55c0cfd668d0e6d0c2c8f2dcd363))
* **release:** Darwin bundle for the wrapped-Linux-exes group, BSD-grep -- ([7eaebb8](https://github.com/lambdasistemi/cardano-tx-tools/commit/7eaebb898f64b8ca9219cfa1e9aff3b0291dbb3f))

## [0.1.6.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.1.5.0...v0.1.6.0) (2026-05-20)

### Features

* **graph:** scaffold Cardano.Tx.Graph.Rules.Load module ([2758f64](https://github.com/lambdasistemi/cardano-tx-tools/commit/2758f64503b810b2765c093c83d0dfc0f96a4a16))
* **graph:** YAML parser for entities (from-address, script, asset) ([1dc2ab1](https://github.com/lambdasistemi/cardano-tx-tools/commit/1dc2ab154698e0f72b4917105703dbb1ce9db63b))
* **graph:** canonical Turtle serializer + 7 basic-shape goldens ([c512591](https://github.com/lambdasistemi/cardano-tx-tools/commit/c51259182a3310f76154ec66ef1a99c0563bfeec))
* **graph:** compound-key entities (keys+bytes) and fixture 04 golden ([c882350](https://github.com/lambdasistemi/cardano-tx-tools/commit/c8823501aee05a43855c81256b575853d945b5b6))
* **graph:** shared-identity + blueprints/collapse + 3 complex-shape goldens ([49f4683](https://github.com/lambdasistemi/cardano-tx-tools/commit/49f46839a9e1c423cadc0f2aae3cc2519fc00d93))
* **graph:** structural Turtle parser for rules subset ([f8e8c94](https://github.com/lambdasistemi/cardano-tx-tools/commit/f8e8c94116a9d1ce290b973b70f4e463ab98bf26))
* **graph:** owl:imports composition + DFS resolver ([cb1cb8c](https://github.com/lambdasistemi/cardano-tx-tools/commit/cb1cb8c12c3ec5c87a1a8b2011d9a6a07ad99e8f))
* **graph:** cycle detection in rules import graph ([7826979](https://github.com/lambdasistemi/cardano-tx-tools/commit/78269797a2d5f703c17e2170d3bae72aa5573680))
* **graph:** structured validation errors with file+line ([359c9f8](https://github.com/lambdasistemi/cardano-tx-tools/commit/359c9f8018a9f9d47fe6328853f135096ab0bf1a))
* **graph:** warn on cross-file duplicate entities ([260c44d](https://github.com/lambdasistemi/cardano-tx-tools/commit/260c44d92aa8a60e4bd8e179bc64d19c08c6d551))
* **graph:** tx-graph executable --rules wiring ([47f03fa](https://github.com/lambdasistemi/cardano-tx-tools/commit/47f03fa60c3c2aedf1ca8fd84517db0e6b0849bc))
* **graph:** expose rulesEntities on RulesLoadResult ([9091098](https://github.com/lambdasistemi/cardano-tx-tools/commit/909109810b0109bf1877c2fe744ccd74340d6189))
* **graph:** scaffold Cardano.Tx.Graph.Emit module ([42049aa](https://github.com/lambdasistemi/cardano-tx-tools/commit/42049aafcbc183773dc0da42cd881cddf9e33196))
* **graph:** tx-graph --tx/--utxo/--out/--format flags ([8d60d05](https://github.com/lambdasistemi/cardano-tx-tools/commit/8d60d059b6aa11226f0d1d520fa5c5ed581d8c58))
* **graph:** credential lookup + raw-bytes bnode naming ([27dba5e](https://github.com/lambdasistemi/cardano-tx-tools/commit/27dba5e0bba6953ee0c3ef13b333996791e2d0e3))
* **graph:** body emitter + fixture 02 byte-diff + vocab traceability ([485be85](https://github.com/lambdasistemi/cardano-tx-tools/commit/485be85124b6a7974c5be52eebf62b6abd185ff1))
* **graph:** enable fixture 03 byte-diff (regen-only; no new leaves) ([f1054bf](https://github.com/lambdasistemi/cardano-tx-tools/commit/f1054bf878d59a73959e142022f404f58f8f10d9))
* **graph:** mint + withdrawal leaves; fixtures 04, 05, 08 ([fd8cf42](https://github.com/lambdasistemi/cardano-tx-tools/commit/fd8cf428e60f0250a7d1daaa9a6f5fa7880f7baf))
* **graph:** cert + pool + drep leaves; fixtures 06, 07 ([6e87fab](https://github.com/lambdasistemi/cardano-tx-tools/commit/6e87fab0ebacd17d61d797be4e3f725e6c066970))
* **graph:** enable fixture 09 byte-diff (regen-only; no new leaves) ([7fa3a9f](https://github.com/lambdasistemi/cardano-tx-tools/commit/7fa3a9f0f5c3939ee1bbfd2007e239c42139b191))
* **graph:** collateral + treasury-withdrawal proposal leaves; fixtures 01, 10, 11 ([a354d01](https://github.com/lambdasistemi/cardano-tx-tools/commit/a354d012e31d9d77b0144f1bb637eb293ec55937))
* **graph:** JSON-LD serializer + equivalence spec ([3ae472a](https://github.com/lambdasistemi/cardano-tx-tools/commit/3ae472a5c51d3928291ea59c5f4c4dfce57a3668))

### Bug Fixes

* **048:** refactor unit test to read tx-graph path via env var (nix-check sandbox compatibility) ([920a496](https://github.com/lambdasistemi/cardano-tx-tools/commit/920a496cce0462f40d0c20a3964b6dec53eea024))
* **validate:** seed reward accounts for withdrawals ([f1fd25e](https://github.com/lambdasistemi/cardano-tx-tools/commit/f1fd25e677e033958b8d92bc1bc1a1dfc72c54fe))
* **tx-validate:** query reward accounts from n2c ([704ecc9](https://github.com/lambdasistemi/cardano-tx-tools/commit/704ecc9bdcb46364490a8bee7591cbc382ca822e))

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

# Changelog

## Unreleased

## [0.1.4.0](https://github.com/lambdasistemi/cardano-tx-tools/compare/v0.1.3.0...v0.1.4.0) (2026-05-16)

### Features

* **022:** port tx-sign vault + witness from amaru-treasury-tx ([1203f29](https://github.com/lambdasistemi/cardano-tx-tools/commit/1203f298e24335630a6e3029dfbf73b3b5ee847c))
* **015:** cabal wiring + Cardano.Tx.Validate.Cli scaffold + Session ([015cd55](https://github.com/lambdasistemi/cardano-tx-tools/commit/015cd554518270a0c97daba6f2cc6edc27912626))
* **015:** parser + verdict + human renderer + Main + US1 happy path ([7f10cb9](https://github.com/lambdasistemi/cardano-tx-tools/commit/7f10cb9549a9aef3a82241b49bbbaa4cb5a10764))
* **015:** pre-fix body surfaces structural failure (SC-003) ([f99f711](https://github.com/lambdasistemi/cardano-tx-tools/commit/f99f711b7c2b949f5baff71278e63852ee300bc6))
* **015:** JSON envelope renderer + --output json wiring ([4af0c22](https://github.com/lambdasistemi/cardano-tx-tools/commit/4af0c225a0da8c7faa33ba75331e853f6468b2d4))
* **015:** release plumbing for tx-validate (AppImage / DEB / RPM / Darwin / Docker) ([741b8ab](https://github.com/lambdasistemi/cardano-tx-tools/commit/741b8ab934feebbd5afce56a5e372874d3d68620))
* **015:** wire github-release-check into tx-validate ([9b5c1b4](https://github.com/lambdasistemi/cardano-tx-tools/commit/9b5c1b4a5488609ac202b7739d1d2ed09dfb4d88))
* **015:** add --version flag to tx-validate ([5633c68](https://github.com/lambdasistemi/cardano-tx-tools/commit/5633c683dd6fb6568f3184d47c3992bf85ff8f43))

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


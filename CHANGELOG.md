# Changelog

## Unreleased

### Features

* **014:** add `Cardano.Tx.Validate.validatePhase1` — Phase-1 pre-flight gate that runs the ledger's UTXOW + LEDGER rule against an unsigned Conway transaction without submitting it, returning the full `ApplyTxError` verbatim. Companion helper `isWitnessCompletenessFailure` recognises the noise constructors any unsigned tx trips so callers can filter them before deciding whether to sign. See [PR #16](https://github.com/lambdasistemi/cardano-tx-tools/pull/16) and [issue #14](https://github.com/lambdasistemi/cardano-tx-tools/issues/14).

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


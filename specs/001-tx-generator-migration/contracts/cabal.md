# Cabal Contracts

Locked cabal stanza shapes for the migration. The implementation must
match these contracts; reviewers should diff the final `.cabal`
against this file before approving.

## `library tx-generator-lib`

```cabal
library tx-generator-lib
  import:           warnings
  visibility:       public
  hs-source-dirs:   lib-tx-generator
  default-language: GHC2021
  exposed-modules:
    Cardano.Tx.Generator.Build
    Cardano.Tx.Generator.Daemon
    Cardano.Tx.Generator.Fanout
    Cardano.Tx.Generator.Persist
    Cardano.Tx.Generator.Population
    Cardano.Tx.Generator.Selection
    Cardano.Tx.Generator.Server
    Cardano.Tx.Generator.Snapshot
    Cardano.Tx.Generator.Types

  build-depends:
    -- Adjusted as the migration discovers unused deps;
    -- final list lives in cardano-tx-tools.cabal.
    , aeson
    , async
    , base
    , base16-bytestring
    , bytestring
    , cardano-binary
    , cardano-crypto-class
    , cardano-ledger-allegra
    , cardano-ledger-api
    , cardano-ledger-byron
    , cardano-ledger-conway
    , cardano-ledger-core
    , cardano-ledger-mary
    , cardano-node-clients
    , cardano-node-clients:utxo-indexer-lib
    , cardano-slotting
    , cardano-strict-containers
    , cardano-tx-tools
    , chain-follower
    , containers
    , contra-tracer
    , directory
    , exceptions
    , filepath
    , microlens
    , network
    , operational
    , ouroboros-consensus
    , ouroboros-consensus:cardano
    , ouroboros-consensus:protocol
    , ouroboros-network
    , ouroboros-network:api
    , ouroboros-network:framework
    , random
    , retry
    , stm
    , text
    , time
    , unix
```

**Visibility**: `public`. Downstream consumers can build-depend on
`cardano-tx-tools:tx-generator-lib`.

**Inherits**: the `common warnings` stanza from the parent
`.cabal` (`-Wall -Werror -Wunused-imports -Wmissing-export-lists
-Wname-shadowing -Wredundant-constraints`).

**Forbids**: importing `Cardano.Node.Client.TxGenerator.*` (the
legacy namespace must not survive the migration).

## `executable cardano-tx-generator`

```cabal
executable cardano-tx-generator
  import:           warnings
  hs-source-dirs:   app/cardano-tx-generator
  main-is:          Main.hs
  default-language: GHC2021
  ghc-options:      -threaded -rtsopts -with-rtsopts=-N
  build-depends:
    , base
    , cardano-tx-tools:tx-generator-lib
```

**Binary name**: `cardano-tx-generator` (operator continuity).

**Main module**: `Main` at `app/cardano-tx-generator/Main.hs`.
Imports only the daemon entry point and forwards `getArgs`.

**Forbids**: pulling in anything beyond `base` and the new sublib
(`Main.hs` must stay thin; the daemon's logic lives in the sublib).

## `test-suite tx-generator-tests`

```cabal
test-suite tx-generator-tests
  import:           warnings
  type:             exitcode-stdio-1.0
  hs-source-dirs:   test
  main-is:          tx-generator-main.hs
  default-language: GHC2021
  other-modules:
    Cardano.Tx.Generator.FanoutSpec
    Cardano.Tx.Generator.PersistSpec
    Cardano.Tx.Generator.PopulationSpec
    Cardano.Tx.Generator.SelectionSpec
    Cardano.Tx.Generator.ServerSpec
    Cardano.Tx.Generator.SnapshotSpec

  build-depends:
    , aeson
    , async
    , base
    , base16-bytestring
    , bytestring
    , cardano-crypto-class
    , cardano-ledger-allegra
    , cardano-ledger-alonzo
    , cardano-ledger-api
    , cardano-ledger-binary
    , cardano-ledger-conway
    , cardano-ledger-core
    , cardano-ledger-mary
    , cardano-node-clients
    , cardano-slotting
    , cardano-strict-containers
    , cardano-tx-tools
    , cardano-tx-tools:tx-generator-lib
    , containers
    , directory
    , filepath
    , hspec
    , microlens
    , network
    , plutus-core
    , QuickCheck
    , random
    , sop-extras
    , temporary
    , text
    , time
```

**Separate from `unit-tests`**: the daemon's unit specs must NOT
appear under the existing `unit-tests` stanza's `other-modules`.
Symmetrically, no diff/blueprint/resolver spec appears here.

**Main entry**: `test/tx-generator-main.hs` registers the six
`*Spec` modules; nothing else.

## `test-suite e2e-tests`

```cabal
test-suite e2e-tests
  import:           warnings
  type:             exitcode-stdio-1.0
  hs-source-dirs:   test
  main-is:          e2e-main.hs
  default-language: GHC2021
  other-modules:
    Cardano.Tx.Generator.E2E.EnduranceSpec
    Cardano.Tx.Generator.E2E.IndexFreshSpec
    Cardano.Tx.Generator.E2E.ReadySpec
    Cardano.Tx.Generator.E2E.RefillSpec
    Cardano.Tx.Generator.E2E.RestartSpec
    Cardano.Tx.Generator.E2E.SnapshotSpec
    Cardano.Tx.Generator.E2E.StarvationSpec
    Cardano.Tx.Generator.E2E.SubmitIdempotenceSpec
    Cardano.Tx.Generator.E2E.TransactSpec

  build-depends:
    , async
    , base
    , bytestring
    , cardano-crypto-class
    , cardano-ledger-alonzo
    , cardano-ledger-api
    , cardano-ledger-byron
    , cardano-ledger-conway
    , cardano-ledger-core
    , cardano-node-clients
    , cardano-node-clients:devnet
    , cardano-tx-tools
    , cardano-tx-tools:tx-generator-lib
    , chain-follower
    , containers
    , directory
    , filepath
    , hspec
    , microlens
    , network
    , process
    , stm
    , temporary
    , time
    , unix
```

**Note**: the existing cardano-tx-tools repo currently has no
`e2e-tests` test-suite. This is a new stanza.

## Forbidden after migration

- The cardano-node-clients main library MUST NOT expose
  `Cardano.Node.Client.TxGenerator.*` modules.
- The cardano-node-clients main library MUST NOT contain
  `app/cardano-tx-generator/`.
- cardano-node-clients's `cabal.project` MUST NOT contain a
  `source-repository-package` entry for cardano-tx-tools.

These are verified by the companion deletion PR's diff and by
`cabal build all` succeeding on cardano-node-clients with the pin
absent.

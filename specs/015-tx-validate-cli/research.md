# Phase 0 Research: tx-validate CLI

**Feature**: 015-tx-validate-cli
**Date**: 2026-05-16

## R1. `Provider` accessors at the pinned `cardano-node-clients`

**Decision**: use `Cardano.Node.Client.Provider.queryProtocolParams`, `queryUTxOByTxIn`, and `queryLedgerSnapshot` exactly as `amaru-treasury-tx`'s [`liveContext`](https://github.com/lambdasistemi/amaru-treasury-tx/blob/main/lib/Amaru/Treasury/ChainContext.hs#L130-L162) does. Tip slot is `ledgerTipSlot snapshot`.

**Rationale**: this is the canonical N2C-driving pattern across our toolkit (also used by `cardano-tx-tools`' existing `Cardano.Tx.Diff.Resolver.N2C`). Inspector duplicates a JSON-shaped variant of the same recipe.

**Re-verification path**: open `Cardano.Node.Client.Provider` in the resolved build plan, confirm the three function signatures. The pin in `cabal.project` is the same one PR #16 used; we are not bumping it.

**Alternatives considered**:

- **Cardano-cli + JSON pipe** — call out to `cardano-cli query utxo`. Rejected; constitution VI says no shell-out, and we just replaced JSON parsing with proper CBOR in spec 014.
- **Direct LSQ via `Ouroboros.Network.Protocol.LocalStateQuery`** — bypass `Provider`. Rejected; the abstraction we want is `Provider`, and there's no reason to duplicate it.

## R2. Blockfrost `/epochs/latest/parameters` decoding into `PParams ConwayEra`

**Decision**: rely on `cardano-ledger-conway`'s `FromJSON (PParams ConwayEra)` instance.

**Rationale**: Blockfrost emits the Cardano-CLI-shaped protocol-parameters JSON, which is exactly what the `FromJSON` instance consumes. Inspector's [`parseProtocolParametersValue`](https://github.com/lambdasistemi/cardano-ledger-inspector/blob/main/libs/cardano-ledger-inspector/src/Conway/Inspector/Validation.hs#L557-L562) demonstrates the round-trip.

**Caveat**: Blockfrost's response wraps the pparams object in a flat top-level field set rather than nesting them; the Aeson decoder handles that shape natively in current `cardano-ledger-conway`. If a future Blockfrost schema bump diverges, we'll surface it as a configuration error per FR-006 / the assumptions block.

**Alternatives considered**:

- **Custom Aeson decoder** for the Blockfrost shape only. Rejected; redundant with the upstream instance.

## R3. Blockfrost `/blocks/latest` JSON

**Decision**: parse only the `slot :: Word64` field; ignore everything else.

**Rationale**: that's the only field `validatePhase1` consumes from the tip. Decoding the full block object brings in more fields that could drift; restricting to `slot` keeps the contract narrow.

**Implementation**: one-off `FromJSON` instance for `BlockfrostSlot` in `Cardano.Tx.Validate.Cli.Blockfrost`.

## R4. HTTP fetcher abstraction for the new endpoints

**Decision**: introduce a small record-of-functions `BlockfrostClient` in `Cardano.Tx.Validate.Cli.Blockfrost`:

```haskell
data BlockfrostClient m = BlockfrostClient
    { bfPParams :: m (Either BlockfrostError (PParams ConwayEra))
    , bfSlot    :: m (Either BlockfrostError SlotNo)
    }
```

Production wires it over `http-client` + the Blockfrost base URL + API key. Tests inject a pure stub.

**Rationale**: keeps the validate-side tests independent of `Cardano.Tx.Diff.Resolver.Web2`'s HTTP stub harness. The Diff path tests stubbed `Web2FetchTx`; we mirror that pattern for the two new endpoints.

**Alternatives considered**:

- **Extend `Cardano.Tx.Diff.Resolver.Web2`** with `httpFetchPParams` + `httpFetchTipSlot`. Pros: one HTTP-stack helper. Cons: leaks Validate's concerns into the Diff namespace and makes the Diff resolver harder to refactor later. Rejected on namespace-hygiene grounds.

## R5. Primary-session lifecycle

**Decision**: a `withSession` bracket that owns the primary source's connection lifetime:

```haskell
data Session = Session
    { sessionNetwork :: Network
    , sessionPParams :: PParams ConwayEra
    , sessionSlot    :: SlotNo
    , sessionPrimary :: PrimarySession         -- which one supplied the above
    , sessionUtxoResolvers :: [Resolver]       -- N2C first iff N2C is in the chain
    }

withSession ::
    TxValidateCliOptions ->
    (Session -> IO a) ->
    IO a
```

For N2C primary: `withLocalNodeBackend (n2c.magic) (n2c.socket) $ \backend -> do { pp <- queryProtocolParamsH (backendQuery backend); slot <- queryLedgerSnapshotH (backendQuery backend) >>= ledgerTipSlot; let r1 = n2cResolver (backendProvider backend); … }`.

For Blockfrost primary: build the `Manager`, call `bfPParams` + `bfSlot`, then build the Web2 resolver.

**Rationale**: the bracket ties HTTP / N2C lifecycle to the action; the `Session` is immutable after acquisition. Mirrors `amaru-treasury-tx`'s `withLiveContext`.

## R6. Resolver chain ordering

**Decision**: chain is `[n2cResolver, web2Resolver]` filtered by which flags are set. If both are set, N2C is first. If only one is set, the chain has one entry.

**Rationale**: matches `tx-diff`'s ordering (cheap-and-local first per the Resolver Architecture clause of the constitution). `resolveChain` already returns per-input resolver-trace diagnostics; we emit those to stderr per FR-008.

## R7. JSON output envelope

**Decision**: see [contracts/json-output.md](./contracts/json-output.md). Top-level keys: `status`, `exit_code`, `structural_failures`, `witness_completeness_count`, `pparams_source`, `slot_source`, `utxo_sources`.

**Rationale**: locked at the contract level so callers depending on the JSON shape can pin to it across minor versions. The exit-code field duplicates the process-level exit code; that's a usability concession for callers piping the JSON into other tools.

## R8. Release plumbing

**Decision**: extend `flake.nix` with:

- `txValidate` symlink-join wrapper (mirrors `txDiff`) that injects `SSL_CERT_FILE` from `pkgs.cacert` so HTTPS works against Blockfrost out of the box.
- `mkTxValidateDarwinHomebrewBundle` (mirrors `mkTxDiffDarwinHomebrewBundle`).
- `tx-validate-linux-release-artifacts` + `tx-validate-linux-dev-release-artifacts` (mirrors `linux-release-artifacts` / `linux-dev-release-artifacts`).
- A `tx-validate-image` docker image (mirrors `cardano-tx-generator-image`).
- `apps.tx-validate` for `nix run .#tx-validate`.
- `linux-artifact-smoke` already exists; extend it to smoke-test the tx-validate AppImage too.

**Rationale**: copy-paste of the existing `tx-diff` plumbing — minimal new abstraction; trivially reviewable.

---

## Open items for `/speckit.tasks`

None of the items above leave a `[NEEDS CLARIFICATION]` in the spec. Two genuine "happens during implementation" callouts:

- R1 re-verification: confirm `queryLedgerSnapshot` is exposed on the pinned `cardano-node-clients`; if the symbol moved, the failure is a compile error (bisect-safe).
- R3 / R4: confirm Blockfrost mainnet returns the schemas the decoders expect at fixture-creation time; if not, surface as `BlockfrostError` with a clear message.

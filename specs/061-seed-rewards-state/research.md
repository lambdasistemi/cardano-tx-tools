# Research: tx-validate reward state seeding

**Feature**: 061-seed-rewards-state
**Date**: 2026-05-20

## R1 - Pure Validator API

**Decision**: add a reward-aware pure validation entry point in `Cardano.Tx.Validate`, and keep the current `validatePhase1` as a compatibility wrapper with an empty reward-account map.

**Rationale**: the pure library currently owns `NewEpochState` construction. Passing queried reward accounts into this layer keeps CLI N2C concerns out of the library while making the seeding behavior testable without a node.

**Alternatives considered**:

- Change `validatePhase1` in place: rejected because it would break existing callers and tests.
- Filter `WithdrawalsNotInRewardsCERTS` in the CLI: rejected because it masks genuinely unregistered accounts.

## R2 - Conway Account State Seeding

**Decision**: seed withdrawal accounts via Conway `accountsL` / `addAccountState`, constructing an account with zero deposit and explicitly setting its reward balance to the queried `Coin`.

**Rationale**: Hoogle lookup showed:

- `certDStateL :: EraCertState era => Lens' (CertState era) (DState era)`
- `accountsL :: CanSetAccounts t => Lens' (t era) (Accounts era)`
- `addAccountState :: EraAccounts era => Credential 'Staking -> AccountState era -> Accounts era -> Accounts era`
- `mkConwayAccountState :: ConwayEraAccounts era => CompactForm Coin -> AccountState era`
- `balanceAccountStateL :: EraAccounts era => Lens' (AccountState era) (CompactForm Coin)`
- `compactCoinOrError :: Coin -> CompactForm Coin`

The important trap is that `mkConwayAccountState` takes a deposit and initializes the reward balance to `mempty`; it is not a reward-balance constructor. The implementation must therefore set `balanceAccountStateL` after constructing the account, or use the `ConwayAccountState` pattern carefully.

**Alternatives considered**:

- Directly set older `dsUnified`/UMap internals: rejected because the pinned ledger exposes the newer accounts API and lenses.
- Use the queried reward balance as the deposit argument to `mkConwayAccountState`: rejected because it registers the wrong field and leaves the reward balance zero.

## R3 - N2C Reward Account Query

**Decision**: use the existing `Provider.queryRewardAccounts :: Set AccountAddress -> m (Map AccountAddress Coin)` from `cardano-node-clients`.

**Rationale**: `mkN2CProvider` already implements `queryRewardAccounts` using `GetFilteredDelegationsAndRewardAccounts` under LocalStateQuery. It is the same provider abstraction already used by `tx-validate` for UTxO resolution and pparams/tip queries.

**Alternatives considered**:

- Add a custom LocalStateQuery in `app/tx-validate/Main.hs`: rejected because it bypasses the provider abstraction and duplicates `cardano-node-clients`.
- Query stake credentials instead of accounts: rejected for the CLI path because transaction withdrawals are keyed by `AccountAddress`, and the provider already exposes the account-shaped query.

## R4 - JSON Provenance

**Decision**: add a stable top-level JSON field:

```json
"reward_accounts_source": "n2c" | "not_required"
```

**Rationale**: the existing envelope already reports `pparams_source`, `slot_source`, and `utxo_sources`. A single source field is enough because v1 has exactly one reward-account source: N2C. Per-account provenance can be added later if multi-resolver reward lookup ships.

**Alternatives considered**:

- Per-account source map: rejected as unnecessary for N2C-only v1.
- No JSON change: rejected because issue #61 explicitly asks for source/provenance symmetry and users need to distinguish "queried from N2C" from "not applicable".

## R5 - Live Boundary Proof

**Decision**: keep CI offline and document a named operator follow-up for the exact live mainnet socket / issue transaction check.

**Rationale**: the bug is at a live-node query boundary, but CI cannot depend on `/code/cardano-mainnet/ipc/node.socket` or a sensitive treasury transaction artifact. Unit tests can lock the contract at the provider boundary; the live smoke proves the production socket returns the expected reward account.

**Alternatives considered**:

- Put a live mainnet smoke in `./gate.sh`: rejected because it requires local node access and potentially private transaction files.
- Skip live proof entirely: rejected because the failure mode is specifically a live-state gathering omission.

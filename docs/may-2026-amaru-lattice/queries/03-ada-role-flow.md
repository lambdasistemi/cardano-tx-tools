# Query 03 - ADA Role Flow

Runnable SPARQL: [`03-ada-role-flow.rq`](03-ada-role-flow.rq)

Back to the [May 2026 lattice demo](../../may-2026-amaru-lattice.md).

## What

This query computes ADA flow by ledger role. For each role, it reports
lovelace entering that role through seed outputs, lovelace leaving that
role through closure-resolved seed inputs, and the net delta.

Roles are derived from graph facts emitted from `rules.yaml`, not from a
hard-coded address map inside the query. Named treasury addresses,
bridge addresses, script credentials, and assets can all be recognized
by joining to the emitted entity overlay.

## Why

This is the ADA flow view that turns a pile of transactions into an
accounting statement. It distinguishes contingency, network compliance,
swap.v2, CAG payee, operator wallet, and unlabelled wallets so we can
ask whether value moved through the expected scopes.

The query also prevents the old "other bucket" problem. If all unknown
and script-controlled addresses are collapsed too early, the graph can
appear to say that one treasury "lost" value. Keeping roles separate
shows whether value went to a swap script, a pool, a bridge output, a
wallet, or back to treasury change.

## Diagram

```mermaid
flowchart LR
  outputs[Seed outputs]
  inputRefs[Seed inputs]
  parents[Parent outputs]
  rules[Rules roles]
  inflow[ADA inflow by role]
  outflow[ADA outflow by role]
  net[Net ADA by role]

  outputs --> inflow
  inputRefs --> parents
  parents --> outflow
  rules --> inflow
  rules --> outflow
  inflow --> net
  outflow --> net
```

## How

The query has two symmetric branches.

The output branch reads every seed output's `cardano:lovelace`, address,
and optional payment credential hash. That amount is counted as
`lovelace_in` for the destination role.

The input branch follows each seed input through `cardano:fromTxOutRef`
to the parent transaction and output index. It reads the parent output's
lovelace and address. That amount is counted as `lovelace_out` for the
source role.

After both branches produce `(bech32, payment hash, in, out)` rows, two
optional role lookups run:

```sparql
?entity cardano:bech32 ?bech ;
        rdfs:label ?label .
```

for address-level labels, and:

```sparql
?entity cardano:hasIdentifier ?id .
?id cardano:bytesHex ?payHash .
```

for script or credential-level labels. The final role is
`COALESCE(addressRole, credentialRole, "wallet.other")`.

The net is `SUM(lovelace_in) - SUM(lovelace_out)`. A positive net means
the role ended the seed set with more ADA than it started with. A
negative net means the seed set spent more ADA from that role than it
returned to it.

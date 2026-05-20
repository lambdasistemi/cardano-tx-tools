# 09-mpfs-facts-request — design narrative

Migrated from the artisan `expected.ttl` comment block in
PR #60 (Q-003 → A-003). The narrative lived as `#`-prefixed
comments in the joint `expected.ttl` before #58 regenerated
the file machine-uniform. This is documentation-only — no
test asserts against this file. The structured fixture data
is in `expected.txt`; the byte-diff anchor is `expected.ttl`.

---

## Story (044 Story 9)

MPFS facts-request — 1 operator input, 10 oracle outputs (each
carrying an identical inline `Fact` datum with a `requester`
field), 1 operator change output.

The future #47 emitter decodes the datum via the
`mpfs-fact.cip57.json` blueprint into a typed AST whose
`requester` leaf resolves to the operator entity. The harness's
`expected.ttl` is the un-inferred base graph: blueprint-decoded
datum triples are NOT modelled here (datum decode is #50's
territory); cross-leaf identity at the `requester` field is
exercised semantically by #47 once the emitter mints the
typed-leaf triples under the OWL key.

## Operator-declared entities

`operator` shares its bech32 (and hence its payment/stake key
hashes) with the `alice` entity used elsewhere in the harness;
the `bytesHex` values match `02-alice-bob-ada/expected.ttl`
exactly.

## Transaction body

1 input, 11 outputs (10 oracle facts + 1 operator change), 0
certs/withdrawals/proposals/collateral/refs/mint.

## Oracle-fact outputs

Ten oracle-fact outputs at `mpfs.oracle`. Each carries an
identical inline `Fact` datum referencing the operator's stake
key; the harness models the OUTPUT count structurally and leaves
datum decode to #50.

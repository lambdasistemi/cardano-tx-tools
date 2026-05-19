# Contract — kmaps#53 Phase A release-signal protocol

**Phase**: 1 (Design & Contracts).
**Owner**: epic `#46` orchestrator (cross-child synchronization).
**Consumers**: this harness's `expected.ttl` slices (S15..S24).

## Why the signal exists

The harness's `expected.ttl` files are pinned to the `cardano:` ontology URIs published by [`cardano-knowledge-maps#53`](https://github.com/lambdasistemi/cardano-knowledge-maps/issues/53). Authoring `expected.ttl` before kmaps#53 publishes Phase A would either:

- couple `expected.ttl` to the harness author's guess at the URIs (drift risk; ten-fixture rewrite if kmaps#53 picks different terms), or
- couple `expected.ttl` to a moving target (kmaps#53 may iterate on terms before Phase A stabilizes).

The epic orchestrator owns the synchronization. The harness blocks every `expected.ttl` slice on the signal arriving; A-side work proceeds in parallel and is signal-independent.

## What kmaps#53 Phase A publishes

Phase A is the **minimal vocab foundation**:

- prefix bindings under the `cardano:` namespace (`https://lambdasistemi.github.io/cardano-knowledge-maps/vocab/cardano#`),
- class URI declarations (`cardano:Transaction`, `cardano:Input`, `cardano:Output`, `cardano:Address`, `cardano:Credential`, `cardano:PaymentCredential`, `cardano:StakeCredential`, `cardano:Identifier`, `cardano:Entity`, `cardano:Asset`, `cardano:Datum`, `cardano:Redeemer`, `cardano:Script`, plus the `cardano:LeafType` concept scheme members: `cardano:PaymentKey`, `cardano:PaymentScript`, `cardano:StakeKey`, `cardano:StakeScript`, `cardano:DRepKey`, `cardano:DRepScript`, `cardano:PoolId`, `cardano:Policy`, `cardano:AssetClass`),
- property URI declarations (`cardano:hasInput`, `cardano:hasOutput`, `cardano:hasFee`, `cardano:hasValidityInterval`, `cardano:hasCertificate`, `cardano:hasWithdrawal`, `cardano:hasProposal`, `cardano:hasMint`, `cardano:hasCollateralInput`, `cardano:hasReferenceInput`, `cardano:hasWitnessSet`, `cardano:atOutRef`, `cardano:resolvedTo`, `cardano:atAddress`, `cardano:hasValue`, `cardano:hasDatum`, `cardano:hasReferenceScript`, `cardano:hasPaymentCredential`, `cardano:hasStakeCredential`, `cardano:bech32`, `cardano:hasIdentifier`, `cardano:bytesHex`, `cardano:leafType`, `cardano:hasPolicy`, `cardano:hasAssetName`, `cardano:hasRawBytes`, `cardano:decodedAs`, `cardano:hasHash`, `cardano:hasVersion`),
- no axioms (no `owl:hasKey`, no `owl:propertyChainAxiom`, no `owl:inverseOf`).

Phase A may include term subsets, additional prefixes (`prov:`, `skos:`, etc.), or `rdfs:label` / `rdfs:comment` annotations on the URIs. The harness only depends on the URIs being **stable and importable**; the harness does not consume axioms in Phase A.

## Signal shape

The kmaps#53 worker publishes the signal by:

1. landing the Phase A commit on the `cardano-knowledge-maps#53` PR,
2. logging a `NOTE  RELEASE: phase-a-vocab-foundation at <commit-url>` line to its `/tmp/epic-046/kmaps-53/STATUS.md`,
3. (optionally) writing a release marker file the orchestrator can sense.

The epic orchestrator monitors the kmaps-53 STATUS.md tail. When the `RELEASE:` line appears, the orchestrator writes an answer file under this harness's `answers/` directory unblocking the next `expected.ttl` task:

```text
/tmp/epic-046/tx-45/answers/A-NNN-kmaps-phase-a.md
```

The answer file carries at minimum:

- the kmaps#53 Phase A commit URL,
- the exact `cardano:` prefix string (in case it differs from the placeholder above),
- the per-term URI map (class names and property names) the harness's `expected.ttl` files MUST use verbatim.

## Worker (this harness) protocol

Before any S15..S24 (`expected.ttl`) slice is dispatched:

1. Verify the answer file for the kmaps Phase A signal exists under `/tmp/epic-046/tx-45/answers/`.
2. If absent, write a question file (`questions/Q-NNN-kmaps-phase-a-pending.md`), log `BLOCKED Q-NNN-kmaps-phase-a-pending` to STATUS.md, and poll until the answer arrives. Continue A-side work meanwhile.
3. Once the answer arrives, dispatch the next S15..S24 slice. The subagent brief references the answer file as the authoritative URI source.

## What the harness does NOT depend on

- Phase A axioms (none in Phase A by definition).
- Phase A `rdfs:label` / `rdfs:comment` text (the harness's `expected.ttl` does not assert against labels; engine views may).
- Phase B / C / later phases of kmaps#53. If kmaps#53 adds axioms (`owl:hasKey` and friends), those flow into `#49` (reasoner), not the harness's `expected.ttl`.
- Any URI change after Phase A. If kmaps#53 evolves Phase A's URIs after publishing, the orchestrator decides whether to update the harness's `expected.ttl` (mechanical rewrite) or carry the divergence (harness sticks to the originally-pinned set). Either way, this contract pins to the signal that fires the harness's B-side, not to live kmaps state.

## Failure modes

- **Signal does not arrive during the PR's lifetime**: the orchestrator defers S15..S24 to a follow-up issue, updates `tasks.md` to mark the deferral, and marks the PR ready with the B-side called out as a documented next step. A-side delivers a usable harness on its own.
- **Signal arrives but the URI set is materially different from this contract's placeholder list**: the orchestrator re-cuts S15..S24's owned-files map to use the actual URIs. The fixture-directory contract is unchanged (`expected.ttl` still ships in each directory); only the file contents shift.
- **Signal arrives but kmaps#53 publishes a non-Turtle vocab format** (e.g., schema.json or OWL/XML only): the harness keeps Turtle as its `expected.ttl` format and writes a Turtle equivalent of the published terms. The contract is on URIs, not on file format.

## Cross-references

- Protocol: `/tmp/epic-046/PROTOCOL.md`.
- Epic map: <https://github.com/lambdasistemi/cardano-tx-tools/issues/46#issuecomment-4486372253>.
- kmaps#53 worker dir: `/tmp/epic-046/kmaps-53/`.
- tx-45 worker dir (this harness): `/tmp/epic-046/tx-45/`.

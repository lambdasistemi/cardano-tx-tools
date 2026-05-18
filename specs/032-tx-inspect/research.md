# Research: tx-inspect — shared-substrate transaction renderer with two-stage rewriting

**Branch**: `032-tx-inspect` | **Date**: 2026-05-18

Phase 0 of `/speckit.plan`. Resolves the technical decisions the plan
depends on; alternatives considered are documented so future readers
understand the trade-off space.

## R1. Renderer extraction: a new top-level entry sharing the projection + render primitives

**Decision (corrected 2026-05-18 during S1 dispatch)**: Add two new exported functions in `src/Cardano/Tx/Diff.hs`:

1. `renderConwayTxHuman :: HumanRenderOptions -> TxDiffOptions -> ConwayTx -> Text` — the top-level entry `tx-inspect`'s `Main.hs` calls. Walks `conwayDiffProjection` (the same projection the diff walker uses) into a `RenderTrie` reusing the existing `RenderTrie` / `renderForest` / `renderJsonValue` primitives. No comparison step.
2. `renderOpenValueHuman[With] :: HumanRenderOptions -> OpenValue -> Text` — a primitive that renders an `OpenValue` subtree directly. Reuses the same render primitives. The rename layer in S3 needs it to render datum subtrees (the `OpenValue`-shaped sub-structure carried inside `ConwayOpenValue`).

The diff renderer `renderDiffNodeHumanWith` is **NOT touched**. tx-diff output is trivially byte-identical before and after.

**Rationale (post-code-inspection)**:

The plan's original framing assumed the diff renderer had a "per-side `OpenValue` render path" to extract. Reading `Cardano.Tx.Diff.hs` showed this is incorrect:

- The diff walker uses `ConwayDiffValue`, NOT `OpenValue`. `OpenValue` is one of `ConwayDiffValue`'s constructors (`ConwayOpenValue OpenValue`), representing user-data subtrees (datums / redeemers / blueprint-decoded plutus data). The full Conway tx is never projected to `OpenValue`.
- `renderDiffNodeHumanWith`'s `DiffSame` branch emits a single summary line via `renderSameLine`. A self-diff `diffConwayTxWith opts tx tx` collapses to one `= <root>` line — wrong granularity for tx-inspect.
- No `ConwayTx → OpenValue` converter exists today.

Two options were considered:

- **Option A — add `conwayTxOpenValue :: TxDiffOptions -> ConwayTx -> OpenValue`** and have tx-inspect render through `renderOpenValueHuman`. **Rejected** because the conversion is lossy: `OpenValue` has five constructors (`OpenObject`, `OpenArray`, `OpenInteger`, `OpenText`, `OpenBytes`) but the existing `Aeson.Value` leaves carry `Aeson.Null`, `Aeson.Bool`, and non-integer `Aeson.Number`. Encoding `Null` / `Bool` / fractional numbers into `OpenValue` is a load-bearing render decision the spec does not pin and that would diverge from tx-diff's existing per-leaf render semantics.
- **Option B — add `renderConwayTxHuman`** walking `conwayDiffProjection` directly and reusing `renderJsonValue` on `Aeson.Value` leaves. **Chosen.** Lossless (no Aeson → OpenValue round-trip), smaller diff to `Diff.hs`, matches the per-leaf render semantics tx-diff goldens already exercise. FR-008's "no forked walker, no copy-pasted render functions" is satisfied: both the new function and the diff renderer call the same internal `RenderTrie` / `renderForest` / `renderJsonValue` primitives.

`renderOpenValueHuman` is still introduced — the rename layer in S3 needs an `OpenValue`-shaped entry when it walks datums (the `ConwayOpenValue OpenValue` subtrees).

**Rejected alternatives** (recorded for future reference):

- *Self-diff trick* (`renderDiffNodeHumanWith opts (diffConwayTxWith opts tx tx)`): rejected — `DiffSame` collapses to a one-line summary, not a full structural render.
- *Add a "render-structural-on-DiffSame" mode to `HumanRenderOptions`*: rejected — non-additive shape change to the diff renderer; cascades into the diff core's handling of equal trees.
- *Brand-new copy of the renderer in `Cardano.Tx.Rewrite`*: rejected — forked walker FR-008 forbids.
- *Move the entire renderer to `Cardano.Tx.Rewrite`* and have tx-diff import it: rejected — wider blast radius than the minimal additive shim. Defer until a third consumer needs it.

**Byte-stability acceptance**: every existing tx-diff golden test must produce byte-identical output before and after S1. Since the diff renderer is not touched, this is satisfied trivially.

**Site-list note for the rename layer (S3)**: per FR-009, rename targets payment addresses + script hashes. Those live in body/witness/reference-script leaves, which are `ConwayDiffValue` leaves — NOT `OpenValue` leaves. So the rename application path walks `ConwayDiffValue`, not `OpenValue`. The `renderOpenValueHuman` primitive is still useful for rendering the datum subtrees, which is where a follow-up ticket could extend rename into plutus-data leaves (out of scope for this PR).

---

## R2. `RewriteRules` lives in a new module, NOT inside `Cardano.Tx.Diff`

**Decision**: `RewriteRules`, `RenameRule(s)`, and `parseRewriteRulesYaml` live in a new module `Cardano.Tx.Rewrite` (sibling of `Cardano.Tx.Diff`).

**Rationale**: Q1 clarification. `Cardano.Tx.Rewrite` is the substrate the predicate DSL (#15) will sit on; it should be addressable independently of `Cardano.Tx.Diff` so #15 can import the rewriting types without dragging in the diff machinery. Putting it inside `Cardano.Tx.Diff` would couple #15's import surface to the diff core.

**Alternatives**: per Q1 clarification answer — `Cardano.Tx.Diff.Rewrite`, `Cardano.Tx.Rename`, `Cardano.Tx.AddressBook`. All rejected for the reasons noted there.

---

## R3. YAML schema: additive `rename:` key on the existing top-level object

**Decision**: The unified rewriting-rules YAML document is the existing top-level object `parseCollapseRulesYaml` already accepts — `{ version?, views?, collapse?: [CollapseRule] }` — extended with an additional optional `rename:` key carrying a list of `RenameRule` entries. The new parser (`parseRewriteRulesYaml`) reuses the existing `parseCollapseRulesYaml` semantics for `version`, `views`, `collapse`, and adds rename-key handling. Backwards compatibility is automatic: existing files do not have a `rename:` key and the loader treats its absence as an empty `RenameRules`.

**Rationale**: Q2 clarification (corrected after code inspection of `parseCollapseRulesYaml`). The "legacy bare-list" form that an earlier draft of Q2 referenced does not exist — every existing collapse-rules YAML is already objectified. The corrected design has zero compatibility shim and one less concept to document.

**Alternatives** (revisited post-correction):
- *Flat tagged list* `[{ kind: collapse, … }, { kind: rename, … }]`: rejected — would break existing collapse-only YAML which has no `kind:` field. Adding a default would work but is a larger schema change than the additive `rename:` key.
- *Two separate flags / files*: rejected — loses the shared-language acceptance criterion in FR-007 + FR-014.

---

## R4. `RenameRule` shape: kind-tagged record with optional `match:` discriminator on address rules

**Decision**: Per Q3 and Q4 clarifications:
- Record shape: `{ kind: "address" | "script", key: <bech32-or-hex>, name: <string>, match?: "full" | "payment" }`.
- `match:` is meaningful only for `kind: "address"`; defaults to `"payment"`.
- For `kind: "script"` the match is always exact on the hex script hash; `match:` is ignored if present.
- The loader pre-extracts the payment credential at parse time when `match: payment`, so the apply path is a single `Map (Either AddressKey ScriptHash) Text` lookup per leaf.

**Rationale**: minimises per-rendered-leaf work; keeps the file format human-readable; leaves a forward-compatible enum (`kind:`) for follow-up tickets that add stake-addresses, pool IDs, DRep IDs, asset policies, asset names.

**Alternatives**: per Q3 and Q4 clarification answers. Per-kind buckets and unified by-key map were rejected (Q3); single global match mode was rejected (Q4).

---

## R5. Test-only static-fixture resolver

**Decision**: Introduce a test-only helper `test/StaticResolver.hs` that loads a `cardano-cli`-shaped `utxo.json` from disk and returns a `Resolver` matching the production interface. NOT exposed as a library.

**Rationale**: Constitution principle VI requires default-offline semantics for every tool. Golden tests for `tx-inspect` need resolved UTxOs deterministically; running the production N2C / Web2 resolvers in tests would defeat the offline guarantee. The existing fixtures under `test/fixtures/mainnet-txbuild/swap-cancel-issue-8/utxo.json` already use the cardano-cli `utxo.json` shape — we extend that pattern.

**Alternatives**:
- *Run the Web2 resolver against a recorded HTTP fixture (existing `Web2Spec.hs` pattern)*: rejected for the inspect tests — too much ceremony for the simple "lookup table" we need. Web2Spec's pattern stays valid for testing the *Web2 resolver itself*; for inspect golden tests, the static lookup is enough.
- *Hand-build TxOuts in code*: rejected — would force the test author to mirror every field of the resolved TxOut by hand, brittle, hard to maintain across many fixtures.
- *Add the resolver to the production library*: rejected — production library should not carry test scaffolding (constitution principle IV).

---

## R6. Amaru treasury swap fixture acquisition

**Decision**: Fetch real on-chain Amaru treasury swap CBOR via the `amaru-treasury` ops journal (recipes under `pragma-org/amaru-treasury/journal/2026/`). Each fixture is committed alongside a `<name>.source.md` provenance file (tx hash, block, fetch command, date). Resolved UTxOs come from `cardano-cli conway query utxo --tx-in <input> --output-json` aggregated into `<name>.utxo.json`.

**Rationale**: Real on-chain CBOR is the authoritative target — that is what the operator command runs against. Synthetic fixtures would not catch encoding quirks specific to the live Amaru treasury contracts. The provenance file makes the fixture replayable.

**Alternatives**:
- *Synthetic fixture via TxBuild DSL*: rejected — would catch our own assumptions, not the live contract's. The shared-substrate cross-check (FR-014) is most valuable when both sides operate on real CBOR.
- *Fetch via Blockfrost `/txs/{hash}/cbor`*: acceptable fallback if the journal recipe lookup fails. The fixture acquisition recipe in `source.md` records whichever path was used.

**Operational note**: fixture acquisition runs once per fixture, when S4 lands. The committed bytes are immutable thereafter. If the upstream Amaru treasury contract is rotated, a new fixture set is fetched in a follow-up ticket — this PR does not subscribe to upstream rotations.

---

## R7. Live-boundary smoke for the operator command

**Decision**: Every implementation slice (S1–S4, S6) extends `gate.sh` with a `cabal run -v0 -O0 tx-inspect …` invocation against the slice's golden, gated by `diff -q` on the captured output. S1's smoke uses the existing `swap-cancel-issue-8` body; S4's smoke uses the Amaru treasury swap fixtures landed in the same slice.

**Rationale**: per the resolve-ticket command-recovery rule and the workflow's live-boundary diagnostic — unit tests over `Cardano.Tx.Rewrite` and `InspectSpec` exercise the loader and the render function in isolation, but the executable's argv handling, `withCli`-wrapped path, resolver-chain wiring, and end-to-end exit-code semantics are only proved by running the binary. The gate failure mode is the operator's failure mode.

**Alternatives**:
- *Defer the smoke to post-merge operator verification*: rejected — fails the resolve-ticket rule that "the shipped command is the P1 user story; smoke proves the command path; smoke does not replace the command".

---

## R8. Release pipeline wiring strategy

**Decision**: S6's subagent enumerates every site in `.github/workflows/*.yaml` and `release-please*` config that names any of the four pre-existing CLIs, then adds `tx-inspect` everywhere it is named. Auto-discovering channels (e.g., flake `apps` iteration in nix-deploy) need no edit. The in-repo local-time gate is `! grep -L 'tx-inspect' .github/workflows/release*.yaml` (every release workflow that names tx-diff must also name tx-inspect). The conclusive verification is the first post-merge release, named in the PR body as an operator follow-up.

**Rationale**: the release pipeline is a live boundary that local tests cannot fully cover. The in-repo grep is a partial gate; the post-merge release is what proves the binary actually ships.

**Alternatives**:
- *Land tx-inspect without release-pipeline edits and let the next release-please bump catch it*: rejected — FR-017 requires the new exe to ship with the next normal release, and we cannot rely on tooling to discover a new exe that is referenced nowhere in the release workflows.

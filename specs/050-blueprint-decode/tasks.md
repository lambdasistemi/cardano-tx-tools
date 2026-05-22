# Tasks: Blueprint decode → typed triples (CIP-57)

**Feature**: `Cardano.Tx.Graph.Emit.Blueprint` (typed datum / redeemer emission)
**Branch**: `050-blueprint-decode-typed-triples`
**Plan**: [plan.md](./plan.md)
**Spec**: [spec.md](./spec.md)
**Parent answer**: `/tmp/epic-046/tx-50/answers/A-001-design-decisions.md`

Task numbering aligns with plan.md slices (S0..S11 → T100..T111). Every
behavior-changing task ships one bisect-safe commit; gate.sh GREEN on every
slice; commits carry a `Tasks: T###` trailer per the gate-script skill.

## Pre-implementation (already done in this PR)

| Status | Task | Commit | Subject |
|---|---|---|---|
| [X] | T000 | `00515a3` | `chore(050): add gate.sh for issue #50 PR` |
| [X] | T001 | `24bb617` + `799b7f0` | `docs(050): spec.md` + A-001 micro-edits |
| [X] | T002 | `45ef85e` | `docs(050): plan.md — D-001a..D-001g pins + S0..S11` |

The analyzer report (`analysis.md`) lands separately as part of the
speckit-analyze pass before T100.

## Implementation slices (auto-continue, no phase stop)

### T100 — S0: rules-loader threads the blueprint index (chore)

- **Status**: [X] complete — landed at this commit; 583/0/23 examples + cabal-fmt + fourmolu + hlint + cabal check + cabal haddock green; A-001 fixture-path fix folded in (Q-001-fixture-blueprint-paths-broken); spec.md FR-011 dup-script-variant relocation to `RulesLoadWarning` folded in as correction-in-passing.
- **Subject**: `chore(050): rules-loader reads + parses blueprints into the index`
- **Tasks trailer**: `Tasks: T100`
- **Files**:
  - `src/Cardano/Tx/Graph/Rules/Load/Types.hs` — add `RulesLoadError`
    variants: `BlueprintFileMissing`, `BlueprintParseError`,
    `AbsoluteBlueprintPath`, `HttpsBlueprintPath`,
    `DuplicateBlueprintForScript`, `DuplicateBlueprintPredicate`.
  - `src/Cardano/Tx/Graph/Rules/Load.hs` — extend `RulesLoadResult` with
    `rulesBlueprints :: ![(ScriptHash, Blueprint, Text)]`; new render
    cases in `renderRulesLoadError`.
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs` — extend the existing
    shape-validating walker to **actually read + parse** each `datum:`
    path via `parseBlueprintJSON`; gather the blueprint index; raise the
    new error variants.
  - `src/Cardano/Tx/Graph/Rules/Load/Resolve/Imports.hs` (if needed) —
    extend the imports resolver to surface blueprint indices from each
    imported file's loader result.
  - `cardano-tx-tools.cabal` — no new modules, but verify deps cover
    `Cardano.Tx.Blueprint` re-export.
  - `test/Cardano/Tx/Graph/Rules/Load/BlueprintLoadSpec.hs` (NEW) — synthetic
    in-memory YAML + on-disk JSON; assert `rulesBlueprints` is populated
    and the script-hash keys match the referenced entity's `PaymentScript`
    identifier bytes. Round-trip the six new error variants.
- **RED**: `BlueprintLoadSpec` fails on the pre-T100 loader (the field
  doesn't exist; the new error variants don't exist).
- **GREEN**: field + variants land; spec passes; **every existing fixture's
  loader result stays unchanged at the byte level** (no semantic change
  on the existing 11 fixtures because none of their `rules.yaml` paths
  resolve to a missing blueprint file — fixture 01's blueprint JSON exists
  on disk).
- **Live-boundary**: rules-loader ↔ filesystem read + JSON parse. The
  `owl:imports`-style path resolution is the boundary the new tests
  exercise.
- **Owner**: paired subagents (driver / navigator) via tmux quadrant.
  Brief at `/tmp/epic-046/tx-50/subagents/T100-rules-loader/brief.md`.

### T101 — S1: `Cardano.Tx.Graph.Emit.Blueprint` module (feat)

- **Status**: [X] complete — landed at this commit; 589/0/23 examples green (6 new BlueprintSpec invariants); gate clean first try. Navigator pinned the IRI minter as **pure concatenation** (`PIri (':' <> ctor <> '_' <> field)`), with FR-008 title-missing fallbacks (`_<idx>` / `field<n>`) computed by the T102 caller before invoking the minter — captured as NOTE NAV-PIN-IRI-MINTER in the subagent log; T102's driver brief inherits this contract.
- **Subject**: `feat(050): Emit.Blueprint — pure decoder + IRI minter (no emit wiring yet)`
- **Tasks trailer**: `Tasks: T101`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit/Blueprint.hs` (NEW) — exports
    `BlueprintDecodeResult (NoBlueprintRegistered | Decoded OpenValue
    Blueprint | DecodeFailed BlueprintDataError)`, `decodeDatumForOutput
    :: [(ScriptHash, Blueprint)] -> TxOut ConwayEra -> Data ConwayEra ->
    BlueprintDecodeResult`, `decodeRedeemerForPurpose ::
    [(ScriptHash, Blueprint)] -> RdmrPurpose -> ScriptHash -> Data
    ConwayEra -> BlueprintDecodeResult`, and the constructor-to-IRI
    minter (`blueprintFieldPredicate :: Text -> Text -> Predicate`).
  - `cardano-tx-tools.cabal` — wire the new module.
  - `test/Cardano/Tx/Graph/Emit/BlueprintSpec.hs` (NEW) — pure-function
    unit spec: covers each `BlueprintSchemaKind` constructor with
    synthetic `Data ConwayEra` values; asserts all three
    `BlueprintDecodeResult` variants emit on the expected paths; round-trips
    the IRI minter on `(title=Nothing, index=0)` → `"_0"` /
    `(title=Just "Foo", field="bar")` → `"Foo_bar"`.
- **RED**: `BlueprintSpec` fails because `Emit.Blueprint` doesn't exist.
- **GREEN**: module lands; spec passes; **no fixture changes**.
- **Live-boundary**: blueprint-decoder ↔ `OpenValue` AST — structural
  only, no I/O.
- **Owner**: paired subagents.

### T102 — S2: extend `emit` signature; thread index through walker (feat)

- **Status**: [X] complete — landed at this commit; ~25 files changed; 602/0/23 unit examples GREEN after one fourmolu retry; all 11 existing fixtures' `expected.ttl` byte-stable (the load-bearing invariant). Acceptable scope reductions accepted by navigator review: (a) Cert/Reward/Propose/Vote redeemer purposes deferred with `Nothing` + Haddock (byte-stable on existing fixtures; existing 11 don't exercise these kinds; will be picked up by a follow-up ticket OR T103 if a fixture needs them); (b) `Blueprint.hs` cycle-breaking import refactor (`Triple` instead of `Emit`) — public surface intact; (c) `Emit.hs` re-exports `BlueprintDecodeResult` + `RdmrPurpose` for in-package tests — pragmatic, documented.
- **Subject**: `feat(050): emit accepts blueprint index; projectBody + projectWitness consult it`
- **Tasks trailer**: `Tasks: T102`
- **Files**:
  - `src/Cardano/Tx/Graph/Emit.hs` — extend `emit` to
    `emit :: ConwayTx -> ResolvedUTxO -> [EntityDecl] ->
    [(ScriptHash, Blueprint, Text)] -> Either EmitError EmittedGraph`.
    Re-export `BlueprintDecodeResult` for tests.
  - `src/Cardano/Tx/Graph/Emit/Project.hs` — thread the blueprint index
    into `projectBody`; `emitOutputDatum` (≈ line 1573) consults the
    index for each output's payment-credential script hash. On
    `NoBlueprintRegistered` → existing opaque shape. On `Decoded` →
    emit typed triples per FR-008 / FR-004. On `DecodeFailed` →
    `cardano:hasRawBytes` + `cardano:decodeError` literal (first error
    only, D-001d).
  - `src/Cardano/Tx/Graph/Emit/Witness.hs` — mirror the same logic on
    the datum-witness path; redeemers consult the index keyed by purpose
    + resolved script hash per FR-007.
  - All callers of `emit` (executable, harness, tests) updated to pass
    `[]` for the blueprint index — preserves existing 11 fixtures'
    `expected.ttl` byte-for-byte.
- **RED**: a new `EmitGoldenSpec` invariant — every existing fixture's
  `expected.ttl` is **byte-equal** to the pre-T102 expectation when the
  emit caller passes `[]`. Initially red against a buggy signature
  thread; GREEN after wiring.
- **GREEN**: all 11 existing fixtures byte-stable; new emit signature
  compiles + threads.
- **Live-boundary**: emitter signature ↔ all callers (compile-time);
  emitter walker ↔ blueprint index lookup (still no behavioural change
  with `[]`).
- **Owner**: paired subagents.

### T103 — S3: fixture 12-blueprint-typed + EmitGoldenSpec extension (feat)

- **Status**: [X] complete — landed at this commit; 16 files changed; `./gate.sh` GREEN (609 examples, 0F, 25 pending); all 11 existing fixtures' `expected.ttl` / `expected.entities.ttl` byte-stable (load-bearing invariant); fixture 12's `expected.ttl` regenerated and byte-stable. A-001 walker grants folded in (`resolveBlueprintSchema` exported from `Cardano.Tx.Blueprint`; `tryDecode` resolves `$ref` blueprint schemas; `openValueAsObject` recurses on nested `OpenObject` via `emitDecodedConstructor` with `"_0"` ctor-title fallback — array recursion stays opaque-bnode for now). Two correction-in-passing T102-MVP fixes folded in (Q-002 / A-002 §"Authorized scope additions"): (a) `BlueprintSchema` JSON parser now honors the CIP-57 `{ "title": "...", "schema": {...} }` field-wrapper form so wrapped fields decode to typed predicates rather than the no-`dataType` `SchemaData` fallback; (b) `resolveBlueprintSchema` preserves the outer schema's title when following a `$ref`, so wrapped fields mint `:SwapOrder_recipient` instead of `:SwapOrder_Credential_pubKeyHash`. Spec User Story 1 example patched in-passing to the actual 2-level nested PubKeyCredential shape with `leafType "Bytes"` (operator-paste CBOR carries PubKey, not Script). `leafTypeFromFieldName` lookup table (pubKeyHash → "PaymentKey", etc.) deferred to a follow-up slice with broader fixture coverage. SC-002 cross-bnode `bytesHex` join validated via shape-agnostic substring count in `BlueprintTypedFixtureSpec.hs` (Q-002 / A-002 amendment by navigator on driver's GREEN diff). Per-fixture loader in `EmitGoldenSpec` + `RewriteRedesignGoldenSpec` now reads `rulesBlueprints` and threads the loaded index through `emit`; existing fixtures stay byte-stable because their outputs sit at pubkey-credential stubs (`paymentScriptHash` → `Nothing` → `NoBlueprintRegistered`).
- **Subject**: `feat(050): fixture 12-blueprint-typed — typed SwapOrder datum emission`
- **Tasks trailer**: `Tasks: T103`
- **Files**:
  - `test/fixtures/rewrite-redesign/12-blueprint-typed/rules.yaml` (NEW)
    — declares the swap.v2 entity (re-using the fixture 01 script hash)
    and a `blueprints:` entry pointing to
    `./blueprints/swap-v2-datum.cip57.json` (re-used from
    `test/fixtures/rewrite-redesign/blueprints/swap-v2-datum.cip57.json`
    via a relative `../blueprints/` path).
  - `test/fixtures/rewrite-redesign/12-blueprint-typed/NOTES.md` (NEW)
    — provenance citing the operator-paste CBOR at
    `test/fixtures/blockfrost-cache/operator-paste-2026-05-21.cbor.hex`
    + an ADR-style note pinning the typed-emission byte shape.
  - `test/fixtures/rewrite-redesign/12-blueprint-typed/expected.ttl`
    (NEW) — byte-diff golden showing
    `_:outputDatum1 a cardano:Datum ; cardano:hasHash <hash> ;
    :SwapOrder_recipient _:datum1_recipient .` plus the
    `_:datum1_recipient a cardano:Identifier` sub-block with the
    correct `leafType` ("PaymentScript" for a script credential) and
    `bytesHex`.
  - `test/fixtures/rewrite-redesign/12-blueprint-typed/expected.entities.ttl`
    (NEW) — entity overlay following the existing pattern.
  - `test/fixtures/rewrite-redesign/12-blueprint-typed/expected.txt`
    (NEW) — `tx-graph` exe stdout / stderr golden.
  - `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S11BlueprintTyped.hs`
    (NEW) — fixture builder following the existing
    `S<NN><Slug>.hs` pattern (cf. `S11_AmaruTreasurySwapReal.hs` for
    the precedent on real on-chain bytes).
  - `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` — enumerate the new
    fixture in the fixture list; add the BlueprintTraceability
    invariant once the corresponding spec lands in T104.
- **RED**:
  1. `EmitGoldenSpec` extended to fixture 11 fails on the pre-T103
     emitter (no typed triples produced).
  2. (Optional, if `arq` available in the dev shell) a SPARQL-shaped
     invariant: `SELECT ?r WHERE { ?d :SwapOrder_recipient ?r . ?r
     cardano:bytesHex ?b }` returns exactly one row.
- **GREEN**: emitter wiring produces the typed triples; fixture 11
  byte-diff passes; all 11 existing fixtures stay byte-stable.
- **Live-boundary**: emitter ↔ blueprint-decoder + fixture-scoped
  namespace minter; the operator-paste CBOR is real Conway bytes
  (strongest live-boundary smoke in the plan).
- **Owner**: paired subagents.

### T104 — S4: fixture 13-blueprint-passthrough + traceability spec (feat)

- **Status**: [X] complete — landed at this commit; 11 files changed; `./gate.sh` GREEN (626 examples, 0F, 27P); 11 existing fixtures + fixture 12's `expected.ttl` / `expected.entities.ttl` / `S12BlueprintTyped.hs` byte-stable (verified empty `git diff --name-only`); no `src/` touched (purely fixture + spec). Fixture 13 = no-blueprint passthrough: same SwapOrder datum body as fixture 12 but `rules.yaml` declares no `blueprints:` block → walker hits the `NoBlueprintRegistered` branch and emits the post-#77 opaque shape (`cardano:hasRawBytes "d8799f…"` literal on the Datum subject, no `:<ctor>_<field>` predicates, no recipient sub-bnode); byte-diff vs fixture 12 is exactly 3 hunks (slug prefix; Datum predicate → `hasRawBytes`; recipient sub-bnode block deleted). First fixture to exercise the `NoBlueprintRegistered` branch on a script-credential output — fixtures 01..11 sit at pubkey-credential addresses where `paymentScriptHash` returns `Nothing` upstream. New `BlueprintPredicateTraceabilitySpec.hs` enforces FR-010 / D-001c / SC-006: for every fixture, emitted `:<X>_<Y>` predicate IRIs ⊆ declared `(constructor, field)` titles in the fixture's loaded blueprint index. Navigator's domain refinement: chose **subset** rather than strict set-equality during authoring — the orphan-predicate-prevention direction is the FR-010 invariant; the reverse (every declared title gets emitted) would be a stronger datum-coverage invariant that the SwapOrder schema's many-fields shape would violate. Empty-blueprint fixtures (01..11 + 13): both sets ∅, subset vacuously holds. Fixture 12 (T103): emitted ⊆ declared holds against the full SwapOrder schema. The spec sweeps all 13 fixtures so any future stray `:_<>` predicate leaking into the no-blueprint path or any orphan typed predicate on the blueprint path will fire it.
- **Subject**: `feat(050): fixture 13-blueprint-passthrough — no-blueprint path stays opaque`
- **Tasks trailer**: `Tasks: T104`
- **Files**:
  - `test/fixtures/rewrite-redesign/13-blueprint-passthrough/{rules.yaml,
    expected.ttl, expected.entities.ttl, expected.txt, NOTES.md}` (NEW)
    — same datum body as fixture 11 but `rules.yaml` has NO
    `blueprints:` block. `expected.ttl` shows the post-#77 opaque
    `hasRawBytes` shape, byte-equal to what the pre-T103 emitter would
    have produced.
  - `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S13BlueprintPassthrough.hs`
    (NEW).
  - `test/Cardano/Tx/Graph/Emit/BlueprintPredicateTraceabilitySpec.hs`
    (NEW) — FR-010 / D-001c: for every fixture, parse `expected.ttl`,
    extract all `:_<>` predicate IRIs, and assert the set equals the
    set of `(constructor, field)` titles declared in that fixture's
    loaded blueprint index. Fixture 13's check is "both sets empty"
    (no `blueprints:` declared → no typed predicates); fixture 12's
    check is "{`SwapOrder_recipient`, `_0_pubKeyHash`}" (the typed
    SwapOrder shape T103 landed).
  - `test/Cardano/Tx/Graph/EmitGoldenSpec.hs` — enumerate fixture 13.
- **RED**: `BlueprintPredicateTraceabilitySpec` fails on a stray
  `:_<>` predicate (or a declared-but-not-emitted predicate). Initially
  passes vacuously on the existing 11 fixtures + fixture 13 (no
  `blueprints:`); the assertion really bites against fixture 12 (T103,
  declares + emits typed predicates) — the set-equality there is the
  load-bearing FR-010 / D-001c invariant.
- **GREEN**: fixture 13 byte-diff passes (byte-equal to the pre-T103
  opaque `hasRawBytes` shape on the same datum body); traceability
  spec covers all 13 fixtures (11 existing + 12 + 13).
- **Live-boundary**: emitter ↔ rules-loader (no-blueprint path); the
  set-equality check is the boundary smoke.
- **Owner**: paired subagents.

### T105 — S5: fixture 14-blueprint-decode-fail (feat)

- **Status**: [X] complete — landed at this commit; 14 files changed; `./gate.sh` GREEN (633 examples, 0F, 29P); 13 prior fixtures + T103's S12 / BlueprintTypedFixtureSpec + T104's S13 / BlueprintPredicateTraceabilitySpec UNTOUCHED (verified empty `git diff --name-only`). Wrong-shape blueprint case: `swap-v2-wrong-shape.cip57.json` declares the SwapOrder `recipient` field as a flat `bytes` leaf at the top level (no PubKeyCredential wrapper); the real `Constr` payload makes `decodeBlueprintData` return `Left (BlueprintDataTypeMismatch "bytes")` → walker hits the `DecodeFailed` branch → emits BOTH `cardano:hasRawBytes` AND exactly one `cardano:decodeError` literal on the Datum subject (FR-005 / D-001d FIRST-error-only). Traceability spec (T104) still holds vacuously for fixture 14 — empty emitted typed-predicate set ⊆ declared `{SwapOrder_recipient}` — so no `allFixtures` extension needed. Three correction-in-passing / scope additions, each documented in the commit body: (a) `src/Cardano/Tx/Graph/Emit/Serialize/Turtle.hs` `renderObject` on `OStringLit` now escapes `\\` and `\"` via the new `escapeTurtleString` helper — latent on pre-#50 fixtures (no embedded quotes), load-bearing on fixture 14's `cardano:decodeError "BlueprintDataTypeMismatch \"bytes\""` literal; (b) `app/tx-graph/Main.hs` adds `decodeErrorWarnings` + `renderSubject` to write one `warning: blueprint decode failed for <subject>: <error>` stderr line per `cardano:decodeError` triple, hooked into `bodyEmit` between `emit` and `serialize`; exit code unaffected (decode-fail is a data-quality signal, not fatal); (c) `cardano-tx-tools.cabal` promotes `Cardano.Tx.Graph.Emit.Project` from `other-modules` to `exposed-modules` so the navigator-owned `BlueprintSpec` extension can import `datumValidatorPick` + `emitDecodedOrOpaque` to exercise FIRST-error-only directly (the two symbols were already in the module's export block; this is a small public-surface expansion versus T101's alternative pattern of re-exporting from `Emit.hs` — chosen for directness and signed off by navigator review). Navigator-side fix shipped: `NAV-MONITOR-ARMED` line at 19:54:39Z (persistent STATUS.md tail filtering on `GATE-PASS / GREEN / COMMIT / BLOCKED / Q-files`) — the 47-min passive-wait pattern from T103/T104 did not recur.
- **Subject**: `feat(050): fixture 14-blueprint-decode-fail — decodeError literal + stderr warn`
- **Tasks trailer**: `Tasks: T105`
- **Files**:
  - `test/fixtures/rewrite-redesign/blueprints/swap-v2-wrong-shape.cip57.json`
    (NEW) — a deliberately wrong blueprint (e.g. expects a `bytes`
    leaf where the SwapOrder datum carries a constructor).
  - `test/fixtures/rewrite-redesign/14-blueprint-decode-fail/{rules.yaml,
    expected.ttl, expected.entities.ttl, expected.txt, NOTES.md}` (NEW)
    — same datum body as fixture 11; `rules.yaml` points at the
    wrong-shape blueprint. `expected.ttl` carries both
    `cardano:hasRawBytes "<cbor-hex>"` and a single
    `cardano:decodeError "<reason>"` literal. `expected.txt` carries
    the expected stderr warning line.
  - `test/fixtures/rewrite-redesign/Fixtures/RewriteRedesign/S14BlueprintDecodeFail.hs`
    (NEW).
  - `test/Cardano/Tx/Graph/Emit/BlueprintSpec.hs` (extended) — assert
    the FIRST-error-only invariant: a synthetic blueprint that fails at
    multiple sub-positions emits exactly one `cardano:decodeError`
    triple (D-001d).
  - `test/Cardano/Tx/Graph/TxGraphExeSpec.hs` — assert (a) exit code 0,
    (b) stderr substring match against `expected.txt`.
- **RED**: extended `BlueprintSpec` + `TxGraphExeSpec` fail on the
  pre-T105 emitter (no `decodeError` literal emitted).
- **GREEN**: decode-failure path lands; fixture 14 byte-diff passes;
  exit 0 + stderr warning asserted.
- **Live-boundary**: emitter ↔ blueprint-decoder (failure path) +
  stderr; the exe spec is the operator-visible boundary.
- **Owner**: paired subagents.

### T106 — S6: draft Phase A.4 patch for `cardano:decodeError` (chore)

- **Status**: [X] complete — closed as PARENT-ACTION satisfied by
  kmaps#59. The parent (epic owner) authored and merged the Phase
  A.4 declaration of `cardano:decodeError` directly into kmaps `main`
  @ `51088551a73f4b92f6611879908a2ea1f2bcd105`, superseding the local
  runtime-root draft mechanism this task originally specified. No
  separate commit ships under T106 — T107 (this commit) absorbs both
  trailers via `Tasks: T106, T107`.
- **Subject**: n/a (absorbed into T107 commit).
- **Tasks trailer**: `Tasks: T106` (carried by T107 commit).
- **Files**:
  - `/tmp/epic-046/tx-50/transactions-additions-phase-a4.ttl` — no
    longer load-bearing; parent opened kmaps#59 directly from the
    Vocab.hs-derived shape.
- **RED**: n/a (pure draft + STATUS log).
- **GREEN**: closed by kmaps#59 merge at
  `51088551a73f4b92f6611879908a2ea1f2bcd105`.
- **Live-boundary**: n/a — cross-repo dependency satisfied at the
  upstream `main` SHA consumed by T107.
- **Owner**: parent (kmaps PR authored externally to this branch).

### T107 — S7: refresh canonical-vocab pin to kmaps@51088551 + cover fixture 14 in vocab traceability (feat)

- **Status**: [X] complete — landed at this commit; carries the
  `Tasks: T106, T107` trailer because the parent-action chunk from
  T106 was satisfied by kmaps#59 merging Phase A.4 directly into
  kmaps `main`. Two correction-in-passing scope additions documented
  in the commit body: (A-004 / Q-001) `VocabTraceabilitySpec`
  enumerates fixture 14 alongside fixtures 01..11 — T105 left it
  outside the strict gate because the T104 typed-predicate spec
  held vacuously, but the strict `cardano:`-CURIE invariant was
  never extended, so `cardano:decodeError` would have been
  unconstrained; (A-005 / Q-002) the same spec now threads
  `rulesBlueprints` from the rules.yaml loader through to the
  `emit` call site (renaming the test helper `loadEntities` →
  `loadRulesData`), replacing the placeholder `emit … []`
  invocation. Without the second correction the spec passed even
  with fixture 14 enumerated, because no blueprint registry was
  attached and the `DecodeFailed` branch never fired.
- **Subject**: `feat(050): refresh canonical-vocab pin to kmaps@5108855 + thread blueprint registry through strict vocab gate`
- **Tasks trailer**: `Tasks: T106, T107`
- **Files**:
  - `test/fixtures/canonical-vocab/transactions.ttl` — verbatim copy of
    kmaps `main` at `51088551a73f4b92f6611879908a2ea1f2bcd105` (the
    canonical file after kmaps#59 squash-merged). Adds exactly one
    cardano: declaration: `cardano:decodeError` (datatype property,
    `rdfs:range xsd:string`, no domain).
  - `test/fixtures/canonical-vocab/PINNED.md` — Current-pin / history /
    lifecycle / Related sections cite kmaps PR #59 + merged SHA.
  - `test/Cardano/Tx/Graph/Emit/VocabTraceabilitySpec.hs` — (a) `S14`
    import + `("14-blueprint-decode-fail", S14.tx)` entry in
    `enabledFixtures`; (b) `loadEntities :: FilePath -> IO
    [EntityDecl]` renamed to `loadRulesData :: FilePath -> IO
    ([EntityDecl], [(ScriptHash, Blueprint, Text)])`; (c) both
    `emit tx emptyUtxo entities []` call sites become
    `emit tx emptyUtxo entities blueprints`. Strict gate goes
    44 examples → 48 examples (12 fixtures × 4 invariants).
- **RED**: focused `nix develop --quiet -c just unit "vocab
  traceability"` exits non-zero on the pre-refresh pin —
  fixture 14 emits `cardano:decodeError` through the threaded
  blueprint registry, the pre-refresh pin
  (kmaps@`f8ca27549f22b3bbfd42528439253a48182fca16`) declares only
  `cardano:decodedAs`, the strict gate reports
  `expected: [] but got: ["decodeError"]` on
  `14-blueprint-decode-fail / every emitted cardano: CURIE is
  declared in the canonical pin`. Fixtures 01..11 stay GREEN
  under the threaded blueprint path, proving no
  cardano:-namespace drift.
- **GREEN**: pin refreshed to
  kmaps@`51088551a73f4b92f6611879908a2ea1f2bcd105`; focused
  command exits 0; 48 examples, 0 failures.
- **Live-boundary**: canonical-vocab pin ↔ `VocabTraceabilitySpec`
  strict CI gate. The pin refresh is byte-stable; the spec edit
  is contained to one test file and does not perturb any
  fixture's `expected.ttl`.
- **Owner**: sub-orchestrator (driver+navigator pair).
- **Depended on**: T106 PARENT-ACTION (closed by kmaps#59 merge).

### T108 — S8: re-record asciinema cast on fixture 11; refresh docs (docs)

- **Subject**: `docs(050): re-record tx-graph.cast on fixture 11 + docs refresh`
- **Tasks trailer**: `Tasks: T108`
- **Files**:
  - `docs/assets/asciinema/scripts/tx-graph.sh` — extend (or replace
    the fixture choice) to record against fixture 11. The script may
    need to dispatch `--rules` and the chosen tx CBOR.
  - `docs/assets/asciinema/tx-graph.cast` — regenerated cast bytes.
  - `docs/tx-graph.md` — refresh the `--help` excerpt if it changed;
    add a one-paragraph + Turtle-example section on blueprint decoding.
  - `README.md` — one-paragraph blueprint-decode mention; one extra
    CLI example demonstrating a blueprint-typed datum output.
- **RED**: n/a (docs only).
- **GREEN**: `./gate.sh` passes (no test impact); manual reviewer
  check that the cast renders on the preview URL.
- **Live-boundary**: asciinema-cast viewer ↔ docs preview — manual
  check at `MKDOCS_SITE_URL`.
- **Owner**: sub-orchestrator (self-execute; docs only).

### T109 — S9: refresh canonical-vocab pin to merged kmaps#58 main SHA (chore — finalization-blocking)

- **Status**: [X] complete — no-op pin refresh verified on 2026-05-22:
  fetched kmaps `origin/main` = `51088551a73f4b92f6611879908a2ea1f2bcd105`,
  matching T107's vendored pin exactly; `data/rdf/transactions.ttl`
  byte-compares equal to `test/fixtures/canonical-vocab/transactions.ttl`.
- **Subject**: `chore(050): refresh canonical-vocab pin to kmaps@<merged-sha>`
- **Tasks trailer**: `Tasks: T109`
- **Files**:
  - `test/fixtures/canonical-vocab/transactions.ttl` — refreshed to the
    merged kmaps `main` SHA.
  - `test/fixtures/canonical-vocab/PINNED.md` — header refresh.
- **RED**: n/a; the byte-content should match T107's pin if kmaps#58
  merged cleanly. If kmaps received review changes the diff is real
  and the spec count may extend further.
- **GREEN**: pin matches merged SHA; all invariants stay GREEN.
- **Live-boundary**: n/a (data refresh).
- **Owner**: sub-orchestrator.
- **Depends on**: parent surfaces merged kmaps `main` SHA via STATUS or
  A-file. PR cannot flip to ready (T111) until this commits.

### T110 — S10: CHANGELOG entry (docs)

- **Subject**: `docs(050): CHANGELOG entry for blueprint-decoded datum emission`
- **Tasks trailer**: `Tasks: T110`
- **Files**:
  - `CHANGELOG.md` — one entry under the next-release cut summarising
    the typed-emission feature, the rules.yaml schema extension (no
    breaking change), the new `RulesLoadError` variants, and the new
    `cardano:decodeError` term.
- **RED**: n/a (docs only).
- **GREEN**: `./gate.sh` passes.
- **Live-boundary**: n/a.
- **Owner**: sub-orchestrator.

### T111 — S11: drop gate.sh (ready for review) (chore)

- **Subject**: `chore(050): drop gate.sh (ready for review)`
- **Tasks trailer**: `Tasks: T111`
- **Files**: removes `gate.sh`.
- **RED**: n/a.
- **GREEN**: `cabal check` + `cabal haddock` + unit suite GREEN one
  last time (manually invoked because `gate.sh` is being removed in
  the same commit); `gh pr ready` flips the PR out of draft.
- **Live-boundary**: n/a.
- **Owner**: sub-orchestrator.
- **Depends on**: T109 (merged-SHA pin), T108 (cast refreshed), every
  prior task GREEN.

## Cross-slice invariants

These specs run on every behavior-changing slice (S2..S5) — never
deleted, only extended:

- `EmitGoldenSpec` — byte-diff per fixture vs `expected.ttl`.
- `ReproducibilitySpec` (#58 SC-005) — run-twice → identical bytes.
- `JsonLdEquivalenceSpec` (#58 SC-002) — JSON-LD ≡ Turtle.
- `VocabTraceabilitySpec` (#58 SC-006, narrowed by D-001c) — every
  emitted `cardano:` CURIE traces to a term declared in the canonical
  vocab pin. Strict-gate fixture coverage: 11 (T105) → 12 (T107, +
  `14-blueprint-decode-fail`); spec also threads `rulesBlueprints`
  from T107 onward so the blueprint-driven `cardano:decodeError`
  predicate is actually observed.
- `BlueprintPredicateTraceabilitySpec` (T104+) — set-equality between
  emitted `:_<>` predicates and declared blueprint `(constructor, field)`
  pairs, per fixture.
- `NoStubViewSpec` (#70 T109) — SPARQL view returns zero rows on every
  fixture, including the 3 new ones.
- `SubjectDeDupSpec` (#70 T102) — no two distinct subject blocks share
  the same subject node.
- Constitution sweep — `cabal check`, `cabal haddock`, `fourmolu`,
  `hlint`, `cabal-fmt` — inherited from `gate.sh`.

## Parent-side parallel work (not a task this worker executes)

- **K1** — Parent opens kmaps#58 using
  `/tmp/epic-046/tx-50/transactions-additions-phase-a4.ttl` as the body
  (drafted in T106). Single term: `cardano:decodeError`.
- **K2** — On merge, parent surfaces the merged kmaps `main` SHA via
  STATUS / answer-file so worker's T109 commit message can cite it
  precisely.

## Follow-on tickets (filed at #50 finalization, NOT during this PR)

- **F1** — "OWL annotations for blueprint-derived predicates" against
  cardano-tx-tools (D-001e deferral closure — owned by #49 / #51).
- **F2** — "SHACL shapes for operator-extensible decode" — Phase C
  reference for #51.
- **F3** — "Cross-blueprint predicate-namespace handling" if real
  operator workflows surface a need beyond the fixture-scoped `:`
  prefix (Q-001b option 2 / option 3 from Q-001).
- **F4** — "`--no-blueprint-decode` debug flag" if an operator needs to
  emit opaque output despite a registered blueprint (Q-001g option 2).

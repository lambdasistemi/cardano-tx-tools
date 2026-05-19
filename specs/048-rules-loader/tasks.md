# Tasks — Rules loader (#48)

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Research**: [research.md](./research.md)

Each implementation task is one bisect-safe commit produced by a single
subagent run. RED and GREEN fold into that one commit. The orchestrator
amends each subagent's HEAD commit to add the `Tasks: T###` trailer and
tick the matching checkbox here; no separate task-stamping commit.

Non-code tasks (carve-out authoring, docs, chore) are marked
`type=docs`/`type=chore` so the analyzer can distinguish them from
behaviour-changing slices.

Legend: `[ ]` = pending, `[X] T###` = closed in the commit whose body
carries `Tasks: T###`.

## Phase 0 — orchestrator gate

- [ ] **T000** *(orchestrator-owned; not a subagent slice)* — Analyzer
  dispatch via `speckit-analyze` against spec.md, plan.md, tasks.md.
  Address findings (or fail-fast back through speckit-plan/tasks) before
  T001 starts. Open Q-files for the design questions in plan.md
  "Pre-implementation prereqs" (naming algo D2, executable name D7,
  `Cardano.Tx.Graph.*` subtree placement, cross-PR contract shape) so
  the orchestrator can confirm or correct before any code lands.

- [ ] **T000a** *(orchestrator-owned; not a subagent slice; post-analyzer)*
  — Verify the `cardano-foundation-drep` CIP-129 bech32 string in
  `test/fixtures/rewrite-redesign/07-vote-delegation/rules.yaml`
  (currently `drep1y2v5h0g4qjqj9p6h9rp3z5lyqz3xczvqj5x3z7c7gj7nf2c52u7m3`,
  60 chars — short by CIP-129 conventions). Run a one-line bech32
  decode probe (`nix develop --quiet -c ghci -e "import Codec.Binary.Bech32
  qualified as B32; …"`) **before T003 begins**; if the decode fails,
  raise a `Q-NNN` Q-file on the worker to edit the fixture's
  `rules.yaml` to a valid CIP-129 form as a tiny `chore(048):`
  pre-T003 slice. (Plan risk R-3 escalation per analyzer finding C5.)

---

## Phase 1 — loader scaffolding (chore-shaped, no behaviour change)

- [X] **T001b** *(type=chore, subagent slice; constitution-compliance
  sweep per Q-002 Option B)* — Add PvP-compliant upper bounds to every
  dependency in every stanza of `cardano-tx-tools.cabal`.

  **Owned files**:
  - `cardano-tx-tools.cabal` (every `build-depends:` block)

  **Forbidden scope**: anything else. No `flake.nix`, no source files,
  no test files, no `gate.sh` (that's T001a).

  **RED proof**: before this slice, `nix develop --quiet -c cabal
  check` reports `Warning: [missing-upper-bounds] On library …` and
  similar for every executable + test-suite stanza. (The orchestrator
  has confirmed this — see Q-002.)

  **GREEN proof**: after this slice, `nix develop --quiet -c cabal
  check` reports zero `missing-upper-bounds` warnings (the only
  remaining error is the `werror` one, which T001c removes). Build
  + unit + fourmolu + hlint + cabal-fmt remain green.

  **Strategy**: for each dep, use `^>=<current-major>` per PvP. Pick
  the current major from `cabal.project.freeze` if present, otherwise
  from the build plan computed by `nix develop -c cabal v2-build
  --dry-run all` (read `dist-newstyle/cache/plan.json`). Where the
  PvP-strict bound would be too restrictive (e.g., for fast-moving
  Cardano libs), widen the bound to the next major (`< x+2`), noting
  the choice in the commit body.

  **Commit subject**: `chore(048): add PvP upper bounds to cardano-tx-tools.cabal`

- [ ] **T001c** *(type=chore, subagent slice; constitution-compliance
  sweep per Q-002 Option B)* — Gate `-Werror` behind a `werror` cabal
  flag per the cardano-node-clients pattern and constitution
  Principle V.

  **Owned files**:
  - `cardano-tx-tools.cabal` (introduce `flag werror`; move `-Werror`
    out of the inline `common warnings` and into a conditional
    `if flag(werror)` clause that adds it)
  - `flake.nix` (wire the flag through the haskell.nix build so dev
    and CI builds still get `-Werror` enabled; usually a
    `flags.werror = true` in the per-component cabalProject options
    or a `--flag=werror` pass)
  - `cabal.project.local` (only if needed for dev convenience; CI
    must inherit from the flake)

  **Forbidden scope**: source files, tests, gate.sh, fixtures.

  **RED proof**: before this slice, `nix develop --quiet -c cabal
  check` reports the `[werror]` error and `Hackage would reject this
  package`. (Per Q-002.)

  **GREEN proof**: after this slice, `nix develop --quiet -c cabal
  check` no longer reports the `[werror]` error and reports
  `Hackage would accept …` (zero errors). The dev shell still
  builds with `-Werror` active — verified by inducing a warning
  (e.g., a temporary unused import in a throwaway .hs) and observing
  the build fail; restore the file before commit. Cabal-fmt +
  fourmolu + hlint + build + unit remain green.

  **Commit subject**: `chore(048): gate -Werror behind a cabal werror flag`

- [ ] **T001a** *(type=chore, subagent slice; analyzer C4 + Q-002
  Option B closer)* — Extend `./gate.sh` to run `nix develop --quiet
  -c cabal check` and `nix develop --quiet -c cabal -O0 haddock
  lib:cardano-tx-tools`. After T001b + T001c, `cabal check` is clean;
  T001a's purpose is to make the gate enforce SC-006 + SC-007 on
  every subsequent slice.

  **Owned files**:
  - `gate.sh` (add the two new lines)

  **Forbidden scope**: cabal file, source, tests.

  **RED proof**: before this slice, `./gate.sh` doesn't invoke
  `cabal check` or `cabal haddock`; FR-016 + SC-007 are
  unenforced. Manual verification suffices since this slice's RED is
  "the new commands aren't there".

  **GREEN proof**: `./gate.sh` includes both new commands and runs
  green on the current HEAD. Try inducing a missing-Haddock failure
  on a fresh export (add a `module Foo where; foo :: Int` with no
  docstring) and confirm the gate fails; restore.

  **Commit subject**: `chore(048): extend gate.sh with cabal check + haddock build`

- [ ] **T001** *(type=feat, US1 scaffolding)* — Module skeleton + types
  + cabal expose + smoke spec.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (new — public API)
  - `cardano-tx-tools.cabal` (add `Cardano.Tx.Graph.Rules.Load` to
    `library`'s `exposed-modules`)
  - `test/Cardano/Tx/Graph/Rules/LoadSmokeSpec.hs` (new — drives the
    smoke `it` block below; module is registered in `unit-tests`
    `other-modules`)

  **Forbidden scope**: anything else in `src/`, anything in
  `test/fixtures/`, gate.sh, README, PR/issue metadata, any
  other `specs/` file.

  **RED proof** (write before the implementation): a Hspec `it`
  block under `Cardano.Tx.Graph.Rules.LoadSmokeSpec` named *"rejects
  a `.foo` extension with UnsupportedExtension"* that imports
  `Cardano.Tx.Graph.Rules.Load.loadRulesFile` and expects
  `Left (UnsupportedExtension "/tmp/<temp>.foo")`. The implementation
  module does not exist yet → the test does not compile. Confirm the
  failure by running `nix develop --quiet -c just unit` (or just
  `cabal build`).

  **GREEN proof** (after the implementation):
  - `nix develop --quiet -c just build` is clean.
  - `nix develop --quiet -c just unit` passes the new smoke `it`.
  - `./gate.sh` is green.

  **Commit subject**: `feat(graph): scaffold Cardano.Tx.Graph.Rules.Load module`

  **Notes**: The module exposes the public types and an
  `loadRulesFile :: FilePath -> IO (Either RulesLoadError
  RulesLoadResult)` whose body is a single pattern match on the file
  extension that returns `Left (UnsupportedExtension path)` for
  anything other than `.ttl`/`.yaml`/`.yml` and returns
  `Left (NotImplemented "<format>")` (a new constructor) for the two
  supported extensions. The non-`.foo` constructors are stubs the
  later slices flesh out; the smoke spec only exercises the
  `.foo` rejection so the slice is honest about what it implements.

---

## Phase 2 — YAML loader (the load-bearing P1 surface)

- [ ] **T002** *(type=feat, US1)* — YAML parser for the basic
  `entities:` shapes (`from-address`, `script`, `asset`) + slugify +
  identifier extraction.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (extend with the YAML
    branch)
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs` (new — internal)
  - `src/Cardano/Tx/Graph/Rules/Load/Bech32.hs` (new — internal,
    `from-address` decomposition)
  - `cardano-tx-tools.cabal` (add the two new other-modules)
  - `test/Cardano/Tx/Graph/Rules/LoadYamlSpec.hs` (new — unit tests
    for the YAML parser; registered in `unit-tests`)

  **Forbidden scope**: serializer, Turtle parser, executable, imports,
  test/fixtures/.

  **RED proof**: unit tests that construct small `rules.yaml` text
  blobs in-line, run `parseRulesYaml`, and assert the resulting
  `[EntityDecl]` matches expected. The `from-address` test surface MUST
  enumerate **all six Conway address classes** (per plan R-2):

  | payment half  | stake half     | identifiers produced               |
  |---------------|----------------|------------------------------------|
  | PaymentKey    | StakeKey       | (PaymentKey,  …) + (StakeKey,  …)  |
  | PaymentKey    | StakeScript    | (PaymentKey,  …) + (StakeScript,…) |
  | PaymentScript | StakeKey       | (PaymentScript,…) + (StakeKey, …)  |
  | PaymentScript | StakeScript    | (PaymentScript,…) + (StakeScript,…)|
  | PaymentKey    | enterprise     | (PaymentKey,  …)                   |
  | PaymentScript | enterprise     | (PaymentScript,…)                  |

  Plus:
  - one `script: <hex>` entity → 1 entity, 1 identifier
    `(PaymentScript, bytes)`
  - one `asset: { policy, name }` entity → 1 entity, 1 identifier
    `(AssetClass, policy ++ ascii(name) hex-encoded)`

  None of the 11 fixtures actually exercises the stake-script half,
  but the unit-test surface MUST still cover it so the implementation
  is not silently incomplete (per analyzer finding C10).

  Failing assertion before implementation: the module's
  `parseRulesYaml` is `undefined` (or returns `Left
  (NotImplemented "yaml")`); the tests fail with a clear message.

  **GREEN proof**: same tests pass; `./gate.sh` green.

  **Commit subject**: `feat(graph): YAML parser for entities (from-address, script, asset)`

- [ ] **T003** *(type=feat, US1)* — Canonical Turtle serializer +
  deterministic naming + carve out & byte-diff fixtures **02, 03, 05,
  06, 07, 08, 10** (the 7 "basic-shape" fixtures).

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (wire serializer into
    `loadRulesFile`)
  - `src/Cardano/Tx/Graph/Rules/Load/Emit/Overlay.hs` (new — canonical
    Turtle emitter)
  - `src/Cardano/Tx/Graph/Rules/Load/Naming.hs` (new — D2 algorithm)
  - `cardano-tx-tools.cabal` (add the two new other-modules)
  - `test/Cardano/Tx/Graph/Rules/LoadGoldenSpec.hs` (new — registers
    the 11-fixture registry; this slice activates byte-diff items
    for 02/03/05/06/07/08/10 and marks the other 4 `pending`)
  - `test/fixtures/rewrite-redesign/02-alice-bob-ada/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/03-multi-asset-transfer/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/05-withdrawal-script-stake/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/06-stake-pool-delegation/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/07-vote-delegation/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/08-contingency-disburse/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/10-governance-treasury-withdrawal/expected.entities.ttl`
    (new)

  **Forbidden scope**: complex-shape entities (compound `keys`+`bytes`,
  shared-identity, blueprints, collapse) — those land in T004–T006.
  Turtle parser, imports, executable also out.

  **RED proof** (re-stated post-analyzer C12, three-step):
  1. Land the spec module + 7 `it` blocks pointing at
     `<fixture>/expected.entities.ttl` paths that **do not yet exist**
     on disk. Tests fail with "file not found" / "byte-mismatch
     against empty file".
  2. Run `loadRulesFile <fixture>/rules.yaml` ad-hoc (e.g., a small
     GHCi session or a throwaway main) **for each of the 7
     fixtures**, capture stdout, write it to
     `<fixture>/expected.entities.ttl` on disk.
  3. Re-run the suite — tests now pass byte-for-byte.

  **Carve-out authoring discipline** (per research.md R7): the
  capture from step 2 *is* the golden. The subagent does NOT
  hand-author the carve-outs.

  **GREEN proof**: all 7 `it` blocks pass; the other 4 fixtures stay
  `pending`. `./gate.sh` green. The subagent MUST paste the
  captured-vs-existing-entity-section diff into the report for
  **all 7 fixtures** (not just fixture 02 per analyzer finding C12) so
  the orchestrator can confirm the naming-scheme shift is visible and
  expected per the cross-PR contract.

  **Commit subject**: `feat(graph): canonical Turtle serializer + 7 basic-shape goldens`

- [ ] **T004** *(type=feat, US1)* — `keys:` + `bytes:` compound-key
  entity (fixture 04) + carve out 04 + activate byte-diff.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs`
  - `src/Cardano/Tx/Graph/Rules/Load/Naming.hs` (extend if needed)
  - `test/fixtures/rewrite-redesign/04-mint-spend-script-overlap/expected.entities.ttl`
    (new)
  - `test/Cardano/Tx/Graph/Rules/LoadGoldenSpec.hs` (activate fixture
    04's `it`)

  **RED proof**: byte-diff for 04 fails before this slice
  (compound-key parser missing).

  **GREEN proof**: byte-diff for 04 passes; the 7 from T003 still
  pass; the other 3 fixtures still `pending`. `./gate.sh` green.

  **Commit subject**: `feat(graph): compound-key entities (keys+bytes) and fixture 04 golden`

- [ ] **T005** *(type=feat, US1)* — Shared identity + `blueprints:`
  validation + `collapse:` round-trip + carve out fixtures **01, 09,
  11** + activate byte-diffs.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs`
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (extend `RulesLoadError` with
    `BlueprintRefsUnknownScript`)
  - `src/Cardano/Tx/Graph/Rules/Load/Naming.hs` (first-entity-wins
    rule applied to shared identity)
  - `test/fixtures/rewrite-redesign/01-amaru-treasury-swap/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/09-mpfs-facts-request/expected.entities.ttl`
    (new)
  - `test/fixtures/rewrite-redesign/11-amaru-treasury-swap-real/expected.entities.ttl`
    (new)
  - `test/Cardano/Tx/Graph/Rules/LoadGoldenSpec.hs` (activate the
    three remaining `it`s — all 11 byte-diffs active and passing)
  - `test/Cardano/Tx/Graph/Rules/LoadYamlSpec.hs` (extend with
    `BlueprintRefsUnknownScript` unit test)

  **RED proof**: the three byte-diffs fail before this slice.

  **GREEN proof**: all 11 byte-diffs pass. `BlueprintRefsUnknownScript`
  unit test passes for the negative case. `./gate.sh` green.

  **Commit subject**: `feat(graph): shared-identity + blueprints/collapse + 3 complex-shape goldens`

  **Notes**: this is the **P1 acceptance pivot**. After this slice,
  SC-001 and SC-002 from the spec are anchored on green tests; the
  remaining slices close US2–US7 (the secondary stories).

---

## Phase 3 — Turtle parser path (US2)

- [ ] **T006** *(type=feat, US2)* — Structural Turtle parser for the
  subset in research.md R1.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Turtle.hs` (new)
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (wire the `.ttl` extension
    branch)
  - `cardano-tx-tools.cabal` (add the new other-module)
  - `test/Cardano/Tx/Graph/Rules/LoadTurtleSpec.hs` (new — unit tests)

  **RED proof**: unit tests authoring a hand-written `.ttl` rules file
  (one entity, one identifier) and asserting
  `parseRulesTurtle` produces a matching `[EntityDecl]`. The `.ttl`
  branch is `Left (NotImplemented "turtle")` → tests fail.

  **GREEN proof**: tests pass. Also: a round-trip test that authors
  the same content as YAML and as Turtle, runs `loadRulesFile` on
  both, and confirms byte-equal `overlayTurtle` output. `./gate.sh`
  green.

  **Commit subject**: `feat(graph): structural Turtle parser for rules subset`

---

## Phase 4 — Imports composition (US3, US4)

- [ ] **T007** *(type=feat, US3)* — `owl:imports` (Turtle) +
  `imports:` (YAML) + DFS resolver + diamond.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load/Resolve/Imports.hs` (new)
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (call the resolver)
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs` (recognise
    `imports:` top-level key)
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Turtle.hs` (recognise
    `owl:imports` triples)
  - `cardano-tx-tools.cabal`
  - `test/Cardano/Tx/Graph/Rules/LoadImportsSpec.hs` (new — unit
    tests; uses `System.IO.Temp` to author small import graphs)

  **RED proof**: tests for parent-imports-child (both Turtle and
  YAML), mixed YAML-imports-Turtle, and diamond. Before the resolver,
  the loader produces only parent triples; tests fail. Includes
  one `MissingImport` test (parent references a non-existent file)
  asserting the structured `Left MissingImport <importer> <imported>`
  error (analyzer N2 surface). Includes one HTTPS-URI rejection
  test asserting that an `owl:imports <https://example.org/x.ttl>`
  triple fails with a parse/resolve error (analyzer N4
  default-offline negative test).

  **GREEN proof**: tests pass. `./gate.sh` green.

  **Commit subject**: `feat(graph): owl:imports composition + DFS resolver`

- [ ] **T008** *(type=feat, US4)* — Cycle detection + structured
  `RulesImportCycle` error.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load/Resolve/Imports.hs`
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (extend `RulesLoadError`
    with `RulesImportCycle`)
  - `test/Cardano/Tx/Graph/Rules/LoadImportsSpec.hs` (add cycle
    tests: 2-file cycle, self-import)

  **RED proof**: tests for the two cycle shapes — before this slice,
  they hang or fail with a different error.

  **GREEN proof**: tests pass; the error carries the cycle path in
  order. `./gate.sh` green.

  **Commit subject**: `feat(graph): cycle detection in rules import graph`

---

## Phase 5 — Loader-level validation (US5)

- [ ] **T009** *(type=feat, US5)* — `EntityZeroIdentifiers` + parser
  errors with file+line + invalid-bech32 / bad-policy-hex /
  duplicate-in-file + slug-collision errors (per Q-001 Option A:
  `EntityNameSlugEmpty`, `EntityNameSlugLeadingDigit`,
  `DuplicateEntitySlugInFile`).

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (extend `RulesLoadError`
    with the new constructors)
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Yaml.hs` (validate after
    parse)
  - `src/Cardano/Tx/Graph/Rules/Load/Parse/Turtle.hs` (validate after
    parse)
  - `src/Cardano/Tx/Graph/Rules/Load/Bech32.hs` (already exists;
    extend with structured errors)
  - `test/Cardano/Tx/Graph/Rules/LoadValidationSpec.hs` (new — unit
    tests covering every error variant)

  **RED proof**: each error scenario tests for the corresponding
  `Left <constructor> …`. Includes an `AbsoluteImport` test —
  an `imports: ["/abs/path.yaml"]` (or `<file:///abs.ttl>`) triple
  must fail with `Left AbsoluteImport <importer> <imported>`
  (analyzer N2 surface). Before this slice, the loader either
  succeeds (silently dropping bad input) or panics with an opaque
  string.

  **GREEN proof**: every test asserts the correct structured error
  with correct file path and line number. `./gate.sh` green.

  **Commit subject**: `feat(graph): structured validation errors with file+line`

---

## Phase 6 — Cross-file duplicate warning (US6)

- [ ] **T010** *(type=feat, US6)* — `DuplicateEntityAcrossFiles`
  warning naming both files.

  **Owned files**:
  - `src/Cardano/Tx/Graph/Rules/Load/Resolve/Imports.hs` (detect
    duplication during merge; emit warning; keep first declaration)
  - `src/Cardano/Tx/Graph/Rules/Load.hs` (`RulesLoadWarning` type
    already exists — extend if needed)
  - `test/Cardano/Tx/Graph/Rules/LoadImportsSpec.hs` (extend with
    duplicate-across-files test)

  **RED proof**: test asserts the warning is emitted with both file
  paths. Before this slice, the loader either errors or silently
  merges; test fails.

  **GREEN proof**: warning is emitted; the kept declaration is the
  first-seen. `./gate.sh` green.

  **Commit subject**: `feat(graph): warn on cross-file duplicate entities`

---

## Phase 7 — Executable wiring (US7)

- [ ] **T011** *(type=feat, US7)* — `tx-graph` executable + `--rules`
  flag + cabal stanza + executable smoke test.

  **Owned files**:
  - `app/tx-graph/Main.hs` (new)
  - `cardano-tx-tools.cabal` (new `executable tx-graph` stanza, mirror
    `executable tx-diff`)
  - `test/Cardano/Tx/Graph/Rules/LoadExeSpec.hs` (new — spawns
    `tx-graph --rules <fixture>/rules.yaml`, captures stdout, diffs
    against `expected.entities.ttl`)

  **Forbidden scope**: `--utxo`, `--out`, `--tx`, `--format` flags
  (deferred to #58 — the executable rejects them with usage text).

  **RED proof**: three `it` blocks failing before the binary lands:
  1. Success path: `tx-graph --rules <fixture>/rules.yaml` writes
     the overlay to stdout, exit 0, stdout byte-equals the
     `expected.entities.ttl` of that fixture.
  2. Structured-error path: `tx-graph --rules <fixture-with-cycle>`
     exits non-zero with the structured error on stderr.
  3. Missing-argument path (per US7 Acceptance Scenario 3, analyzer
     finding C7): `tx-graph` with no `--rules` arg shows usage on
     stderr and exits non-zero. The expected exit code and the
     `--rules` mention in the usage string are part of the assertion.

  **GREEN proof**: all three `it` blocks pass; `nix develop --quiet -c
  just build` includes the new executable; `./gate.sh` green.

  **Commit subject**: `feat(graph): tx-graph executable --rules wiring`

  **Notes**: confirm with the orchestrator (Q-file) whether
  `./gate.sh` needs to grow a `nix run --quiet .#tx-graph` smoke
  step or whether the cabal-level smoke test suffices.

---

## Phase 8 — Finalization

- [ ] **T012** *(type=docs, orchestrator-owned)* — Update README +
  CHANGELOG with the new executable and module surface.

  **Owned files** (orchestrator):
  - `README.md` (add `tx-graph` entry)
  - `CHANGELOG.md` (note the new module + executable)

  **Notes**: this is a mechanical docs edit; orchestrator may
  apply directly without dispatching a subagent.

- [ ] **T013** *(type=chore, orchestrator-owned)* — Drop `gate.sh`
  in the final commit; mark PR ready.

  **Owned files**: `gate.sh` (removed).

  **Commit subject**: `chore(048): drop gate.sh (ready for review)`

  **Notes**: per resolve-ticket finalization, this is the very last
  commit before the PR transitions out of draft. The orchestrator
  runs the finalization audit (per the `gate-script` skill) before
  removing.

---

## Slice ordering and dependencies

```
T000 (analyzer) ──▶ T001 (skeleton) ──▶ T002 (yaml) ──▶ T003 (serializer + 7 goldens) ◀── P1 anchor #1
                                            │
                                            ▼
                                      T004 (keys+bytes + 1 golden)
                                            │
                                            ▼
                                      T005 (shared-id + 3 complex goldens) ◀── P1 anchor #2 (SC-001/SC-002)
                                            │
              ┌─────────────────────────────┴───────────────────────┐
              ▼              ▼              ▼              ▼
            T006           T007           T009          (T011)
          (turtle)       (imports)    (validation)    (executable)
                            │
                            ▼
                          T008           T010
                         (cycles)    (dup-warning)
                            │              │
                            └──────┬───────┘
                                   ▼
                                 T012 (docs)
                                   │
                                   ▼
                                 T013 (drop gate)
```

T006, T007, T009, T011 are **independent** after T005 — they can be
dispatched in any order (or in parallel if the orchestrator allows).
T008 depends on T007; T010 depends on T007. T012 + T013 are
sequential at the end.

## Counts

- 11 implementation subagent slices (T001–T011) + 3 chore subagent
  slices (T001b, T001c, T001a — constitution sweep per Q-002 Option B).
  3 orchestrator-owned slices: T000 (analyzer), T000a (drep bech32
  verify), T012 (docs), T013 (drop gate.sh). 18 total tracked entries.
- 7 fixtures byte-diffed in T003; 1 in T004; 3 in T005 → 11 total.
- 5 user stories closed by T001 (scaffolding part of US1) → T011
  (US7).

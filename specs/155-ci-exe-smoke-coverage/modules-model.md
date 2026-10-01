# Modules model — 155

| ID | Component | Change | Responsibility |
|---|---|---|---|
| M1 | `nix/checks.nix` `gateSpecs.build` | changed | realize every shipped executable and every public sub-library |
| M2 | `nix/checks.nix` new smoke gate | new | run the three smoke scripts against Nix-built executables; data in D1 |
| M3 | `.github/workflows/ci.yml` | changed | `Build Gate` builds M2's check; a downstream job runs M2's app |
| M4 | `justfile` `ci` recipe | changed | invoke the Nix app CI runs for M2 (INV-4) |

Dependency direction: M3 and M4 consume M1/M2 through flake outputs only.
The flake already maps every `gateSpecs` entry to `checks.<sys>.<name>`
and an app; no flake wiring change is expected.

# Data model — 155

| ID | Datum | Fields / relationships | Validation |
|---|---|---|---|
| D1 | smoke gate spec | `name`; `runtimeInputs` = every binary the three scripts call plus the three executables; env `TX_SIGN_EXE`, `TX_INSPECT_EXE`, `TX_DIFF_EXE` bound to `components.exes.<tool>` store paths | INV-3: each variable names an existing executable; each script is executed |

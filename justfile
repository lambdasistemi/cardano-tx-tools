default:
    just --list

format:
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -i {} +
    cabal-fmt -i cardano-tx-tools.cabal

hlint:
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +

build:
    cabal build all -O0

unit match="":
    #!/usr/bin/env bash
    set -euo pipefail
    cabal build exe:tx-graph -O0 >/dev/null
    export TX_GRAPH_EXE="$(cabal list-bin exe:tx-graph -O0)"
    if [[ '{{ match }}' == "" ]]; then
        cabal test cardano-tx-tools:unit-tests -O0 --test-show-details=direct
    else
        cabal test cardano-tx-tools:unit-tests -O0 \
            --test-show-details=direct \
            --test-option=--match \
            --test-option="{{ match }}"
    fi

smoke-sign:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal build exe:tx-sign -O0 >/dev/null
    TX_SIGN_EXE="$(cabal list-bin exe:tx-sign -O0)" scripts/smoke/tx-sign

smoke-inspect:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal build exe:tx-inspect -O0 >/dev/null
    TX_INSPECT_EXE="$(cabal list-bin exe:tx-inspect -O0)" scripts/smoke/tx-inspect

smoke-diff:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal build cardano-tx-tools:exe:tx-diff -O0 >/dev/null
    TX_DIFF_EXE="$(cabal list-bin cardano-tx-tools:exe:tx-diff -O0)" scripts/smoke/tx-diff

ci:
    just build
    just unit
    just smoke-sign
    just smoke-inspect
    just smoke-diff
    cabal-fmt -c cardano-tx-tools.cabal
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +

serve-docs:
    mkdocs serve

build-docs:
    mkdocs build --strict

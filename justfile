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

ci:
    just build
    just unit
    just smoke-sign
    cabal-fmt -c cardano-tx-tools.cabal
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +

serve-docs:
    mkdocs serve

build-docs:
    mkdocs build --strict

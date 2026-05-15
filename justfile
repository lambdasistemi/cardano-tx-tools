default:
    just --list

format:
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -i {} +
    cabal-fmt -i cardano-tx-tools.cabal

hlint:
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +

build:
    cabal build cardano-tx-tools -O0

ci:
    just build
    cabal-fmt -c cardano-tx-tools.cabal
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +

serve-docs:
    mkdocs serve

build-docs:
    mkdocs build --strict

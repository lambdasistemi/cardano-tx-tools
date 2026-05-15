# cardano-tx-tools

Cardano transaction tooling: builder, structural diff, blueprint
decoding. Uses [`cardano-node-clients`][cnc] for Provider/N2C access but
is not a node client. Dependency direction is one-way:
`cardano-tx-tools → cardano-node-clients`.

Documentation: <https://lambdasistemi.github.io/cardano-tx-tools/>.

## Status

Bootstrap. Modules migrate from
[lambdasistemi/cardano-node-clients#152][issue] in subsequent PRs; see
[`docs/migration.md`](docs/migration.md) for the plan.

## Develop

```bash
nix develop --quiet -c just build
nix develop --quiet -c just ci
```

The local gate (`nix flake check --no-eval-cache`) mirrors the CI:

```bash
nix flake check --no-eval-cache
```

## License

[Apache 2.0](LICENSE).

[cnc]: https://github.com/lambdasistemi/cardano-node-clients
[issue]: https://github.com/lambdasistemi/cardano-node-clients/issues/152

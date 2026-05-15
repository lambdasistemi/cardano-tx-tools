# Operator Impact — Quickstart

This page tells operators of `cardano-tx-generator` what changes
when the binary moves from
[`lambdasistemi/cardano-node-clients`](https://github.com/lambdasistemi/cardano-node-clients)
to
[`lambdasistemi/cardano-tx-tools`](https://github.com/lambdasistemi/cardano-tx-tools).

## TL;DR

- **Binary name**: unchanged. `cardano-tx-generator`.
- **CLI flags**: unchanged.
- **Control-socket protocol**: unchanged.
- **On-disk state files**: unchanged. Existing seed + counter files
  keep working.
- **Install URL**: changes. GitHub releases move to
  `lambdasistemi/cardano-tx-tools`.
- **Docker image registry path**: changes. New path noted below.

## Install changes

### Linux AppImage / DEB / RPM

Before:

```
https://github.com/lambdasistemi/cardano-node-clients/releases/download/v0.1.3.0/cardano-tx-generator-...
```

After:

```
https://github.com/lambdasistemi/cardano-tx-tools/releases/download/v<X>/cardano-tx-generator-...
```

The `cardano-tx-tools` release for this binary will be the first
tagged version that includes the migrated daemon. Until then, the
binary remains shipped from cardano-node-clients's last release
(`v0.1.3.0`).

### Docker image

Before:

```
ghcr.io/lambdasistemi/cardano-node-clients/cardano-tx-generator:<tag>
```

After:

```
ghcr.io/lambdasistemi/cardano-tx-tools/cardano-tx-generator:<tag>
```

Update your `docker-compose.yml` `image:` line accordingly. The
container's entrypoint, volumes, ports, and config-file expectations
are all unchanged.

## Verification

Once you've switched to the new install source, run:

```
cardano-tx-generator --help
```

Output should be byte-identical to the old `--help`. If it isn't,
the migration broke its own success criterion — file an issue on
[`lambdasistemi/cardano-tx-tools`](https://github.com/lambdasistemi/cardano-tx-tools/issues).

## What did NOT change

These are all the same on either side of the migration:

- Configuration file schema (whatever JSON / TOML / env vars the
  daemon already reads, it still reads).
- The daemon's HD-wallet seed file (path defaults match the previous
  build; explicit `--seed-path` overrides still work).
- The HD-index counter file format.
- The Unix-socket request / response JSON for `refill`,
  `transact`, `snapshot`, `ready` endpoints.
- The exit codes the daemon produces on failures (`FailureReason`
  remains identical to the pre-migration version).
- The on-the-wire N2C protocol versions and behaviour. The daemon
  still uses cardano-node-clients's `runNodeClient` under the hood;
  the import path changed but the runtime behavior is preserved.

## If you build the daemon from source

Before:

```bash
git clone https://github.com/lambdasistemi/cardano-node-clients
cd cardano-node-clients
nix run .#cardano-tx-generator -- --help
```

After:

```bash
git clone https://github.com/lambdasistemi/cardano-tx-tools
cd cardano-tx-tools
nix run .#cardano-tx-generator -- --help
```

Other `nix run` and `cabal run` recipes follow the same pattern: the
target name (`cardano-tx-generator`) is unchanged; only the repo
hosting it has moved.

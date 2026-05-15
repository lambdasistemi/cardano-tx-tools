# Changelog

## Unreleased

- Migrate `lib-tx-build`, `lib-plutus-blueprint`, the `TxDiff` stack,
  `Evaluate`, and the `tx-diff` executable from
  [lambdasistemi/cardano-node-clients](https://github.com/lambdasistemi/cardano-node-clients)
  under the new `Cardano.Tx.*` namespace
  (tracking issue
  [#152](https://github.com/lambdasistemi/cardano-node-clients/issues/152)).
- Bootstrap scaffold: flake.nix, justfile, CI, mkdocs, GitHub Pages.
- Port the upstream release pipeline (Linux AppImage / DEB / RPM
  bundlers, Darwin Homebrew tap bundles, dev-channel artifacts,
  release planner script, `Linux Release` / `Darwin Release` /
  `Darwin Dev Homebrew` / `Release Planner` workflows).
- `tx-diff` ships wrapped via `pkgs.makeWrapper` so `SSL_CERT_FILE`
  defaults to the bundled cacert; AppImage / DEB / RPM bundlers
  carry the wrapper's full nix closure (including `nss-cacert`), so
  HTTPS verification works in released artifacts.

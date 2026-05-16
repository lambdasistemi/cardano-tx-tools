{ pkgs, components, imageTag, ... }:
let
  # /usr/bin/env so any pipeline driver shebang like
  # `#!/usr/bin/env bash` resolves inside the container.
  usrBinEnv = pkgs.runCommand "usr-bin-env" { } ''
    mkdir -p $out/usr/bin
    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
  '';
in
pkgs.dockerTools.buildImage {
  name = "ghcr.io/lambdasistemi/cardano-tx-tools/tx-validate";
  tag = imageTag;

  # Single-purpose image: tx-validate is the entrypoint. The
  # consumer (signing pipeline / CI gate) supplies the CLI
  # flags and mounts the cardano-node socket via volume.
  config = {
    EntryPoint = [ "/bin/tx-validate" ];
  };

  # Full nix closure including pkgs.cacert so the future
  # Blockfrost-side path can do HTTPS without external
  # configuration. Harmless for the N2C-only v1.
  copyToRoot = pkgs.buildEnv {
    name = "tx-validate-image-root";
    paths = [
      pkgs.coreutils
      pkgs.bash
      pkgs.jq
      pkgs.cacert
      usrBinEnv
      components.exes.tx-validate
    ];
  };
}

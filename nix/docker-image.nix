{ pkgs, components, imageTag, ... }:
let
  # /usr/bin/env so any composer / driver shebang like
  # `#!/usr/bin/env bash` resolves inside the container.
  usrBinEnv = pkgs.runCommand "usr-bin-env" { } ''
    mkdir -p $out/usr/bin
    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
  '';
in
pkgs.dockerTools.buildImage {
  name = "ghcr.io/lambdasistemi/cardano-tx-tools/cardano-tx-generator";
  tag = imageTag;

  # Single-purpose image: the daemon is the entrypoint;
  # the consumer (e.g. the Antithesis testnet's
  # docker-compose.yaml) supplies the CLI flags and may
  # mount composer scripts at
  # /opt/antithesis/test/v1/tx-generator/.
  config = {
    EntryPoint = [ "/bin/cardano-tx-generator" ];
  };

  # buildEnv collects the binary's full nix closure into
  # /nix/store inside the image. netcat-openbsd is included
  # so composer scripts can shell into the container and
  # talk to the control socket via `nc -U`. pkgs.cacert
  # gives the daemon a CA store for any HTTPS that future
  # consumers may want; harmless when unused.
  copyToRoot = pkgs.buildEnv {
    name = "cardano-tx-generator-image-root";
    paths = [
      pkgs.coreutils
      pkgs.bash
      pkgs.jq
      pkgs.gnugrep
      pkgs.netcat-openbsd
      pkgs.cacert
      usrBinEnv
      components.exes.cardano-tx-generator
    ];
  };
}

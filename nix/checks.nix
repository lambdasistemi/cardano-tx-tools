{ pkgs, src, components, lintPkgs ? pkgs }:
let
  lib = pkgs.lib;

  mkCheck = name: script:
    pkgs.runCommand "${name}-check" {
      nativeBuildInputs =
        lib.optionals pkgs.stdenv.hostPlatform.isLinux
          [ pkgs.glibcLocales ];
      LANG = "C.UTF-8";
      LC_ALL = "C.UTF-8";
    } ''
      set -euo pipefail
      cd ${src}
      ${lib.getExe script}
      touch "$out"
    '';

  mkScript = { name, runtimeInputs ? [ ], text }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs text;
    };

  mkGate = spec:
    let
      script = mkScript spec;
    in {
      check = mkCheck spec.name script;
      inherit script;
    };

  lintInputs = [
    lintPkgs.haskellPackages.cabal-fmt
    lintPkgs.haskellPackages.fourmolu
    lintPkgs.haskellPackages.hlint
    pkgs.bash
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
  ];

  gateSpecs = {
    build = {
      name = "build";
      text = ''
        test -e ${components.library}
        test -e ${components.sublibs."n2c-resolver"}
        test -e ${components.sublibs."tx-generator-lib"}
        test -e ${components.exes.tx-diff}
        test -e ${components.exes."cardano-tx-generator"}
        echo "build outputs realized"
      '';
    };

    unit = {
      name = "unit";
      runtimeInputs = [ components.tests.unit-tests ];
      text = ''
        unit-tests
      '';
    };

    tx-generator-unit = {
      name = "tx-generator-unit";
      runtimeInputs =
        [ components.tests."tx-generator-tests" ];
      text = ''
        tx-generator-tests
      '';
    };

    lint = {
      name = "lint";
      runtimeInputs = lintInputs;
      text = ''
        cd ${src}
        cabal-fmt -c cardano-tx-tools.cabal
        find . -type f -name '*.hs' \
          -not -path '*/dist-newstyle/*' \
          -exec fourmolu -m check {} +
        find . -type f -name '*.hs' \
          -not -path '*/dist-newstyle/*' \
          -exec hlint {} +
      '';
    };
  };

  gates = lib.mapAttrs (_: mkGate) gateSpecs;
in {
  checks = lib.mapAttrs (_: gate: gate.check) gates;
  scripts = lib.mapAttrs (_: gate: gate.script) gates;
}

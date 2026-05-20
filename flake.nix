{
  description =
    "Cardano transaction tooling (builder, structural diff, blueprint)";
  nixConfig = {
    extra-substituters = [
      "https://cache.iog.io"
      "https://paolino.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "paolino.cachix.org-1:ecmgO3CXdgSWA2cHlm4srknd/cLFMLmK3i3NrzeDFaE="
    ];
  };
  inputs = {
    haskellNix = {
      url =
        "github:input-output-hk/haskell.nix/8b447d7f57d62fab9249f79bb916bc891e29b9d0";
      inputs.hackage.follows = "hackageNix";
    };
    hackageNix = {
      url = "github:input-output-hk/hackage.nix/b6b4aa4bd699f743238da45c7f43da5a26a822f7";
      flake = false;
    };
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    lintNixpkgs.url =
      "github:NixOS/nixpkgs/647e5c14cbd5067f44ac86b74f014962df460840";
    flake-parts.url = "github:hercules-ci/flake-parts";
    bundlers = {
      url = "github:NixOS/bundlers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dev-assets.url = "github:paolino/dev-assets";
    iohkNix = {
      url =
        "github:input-output-hk/iohk-nix/f444d972c301ddd9f23eac4325ffcc8b5766eee9";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    CHaP = {
      url =
        "github:intersectmbo/cardano-haskell-packages/887d73ce434831e3a67df48e070f4f979b3ac5a6";
      flake = false;
    };
    mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
    cardano-node = {
      url = "github:IntersectMBO/cardano-node/10.7.0";
    };
    cardano-node-clients = {
      url =
        "github:lambdasistemi/cardano-node-clients/ca86f11d27b34e37d3814e4d3c3d66e256400403";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, lintNixpkgs, flake-parts, haskellNix
    , hackageNix, iohkNix, CHaP, mkdocs, cardano-node, cardano-node-clients
    , ... }:
    let
      imageTag =
        self.shortRev or (self.dirtyShortRev or "dirty");
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      flake = {
        inherit imageTag;
      };
      perSystem = { system, ... }:
        let
          pkgs = import nixpkgs {
            overlays = [
              iohkNix.overlays.crypto
              haskellNix.overlay
              iohkNix.overlays.haskell-nix-crypto
              iohkNix.overlays.cardano-lib
            ];
            inherit system;
          };
          lib = pkgs.lib;
          lintPkgs = import lintNixpkgs { inherit system; };
          indexState = "2026-02-17T10:15:41Z";
          indexTool = { index-state = indexState; };
          fix-libs = { lib, pkgs, ... }: {
            packages.cardano-crypto-praos.components.library.pkgconfig =
              lib.mkForce [ [ pkgs.libsodium-vrf ] ];
            packages.cardano-crypto-class.components.library.pkgconfig =
              lib.mkForce
                [ [ pkgs.libsodium-vrf pkgs.secp256k1 pkgs.libblst ] ];
            packages.cardano-lmdb.components.library.pkgconfig =
              lib.mkForce [ [ pkgs.lmdb ] ];
            packages.cardano-ledger-binary.components.library.doHaddock =
              lib.mkForce false;
            packages.plutus-core.components.library.doHaddock =
              lib.mkForce false;
            packages.plutus-ledger-api.components.library.doHaddock =
              lib.mkForce false;
            packages.plutus-tx.components.library.doHaddock =
              lib.mkForce false;
          } // lib.optionalAttrs (system == "x86_64-linux") {
            packages.blockio-uring.components.library.pkgconfig =
              lib.mkForce [ [ pkgs.liburing ] ];
          };
          project = pkgs.haskell-nix.cabalProject' {
            name = "cardano-tx-tools";
            src = ./.;
            compiler-nix-name = "ghc9123";
            shell = {
              withHoogle = true;
              tools = {
                cabal = indexTool;
              };
              buildInputs = [
                lintPkgs.haskellPackages.cabal-fmt
                lintPkgs.haskellPackages.fourmolu
                lintPkgs.haskellPackages.hlint
                pkgs.just
                pkgs.curl
                pkgs.cacert
                pkgs.lmdb
                pkgs.liburing
                mkdocs.packages.${system}.from-nixpkgs
                mkdocs.packages.${system}.asciinema-plugin
              ];
              shellHook = ''
                export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              '';
            };
            modules = [
              fix-libs
              { packages.cardano-tx-tools.flags.werror = true; }
            ];
            inputMap = {
              "https://chap.intersectmbo.org/" = CHaP;
            };
          };
          components = project.hsPkgs.cardano-tx-tools.components;
          # tx-diff's web2 resolver uses http-client-tls and needs a CA
          # bundle at runtime. Wrap the raw executable so SSL_CERT_FILE
          # defaults to the bundled cacert; users can still override.
          # AppImage / DEB / RPM bundlers carry the wrapper's full nix
          # closure (including nss-cacert), so HTTPS works post-install.
          txDiff = pkgs.symlinkJoin {
            name = "tx-diff";
            paths = [ components.exes.tx-diff ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/tx-diff \
                --set-default SSL_CERT_FILE \
                  ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            '';
          };
          # tx-validate is N2C-only in v1 but the CA-bundle wrapper is
          # kept for forward-compat with the future Blockfrost path
          # (lambdasistemi/cardano-tx-tools#21). HTTPS works
          # out-of-the-box if a future invocation needs it.
          txValidate = pkgs.symlinkJoin {
            name = "tx-validate";
            paths = [ components.exes.tx-validate ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/tx-validate \
                --set-default SSL_CERT_FILE \
                  ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            '';
          };
          # tx-inspect performs HTTPS via github-release-check's
          # withCli banner on every run (unless TX_INSPECT_NO_UPDATE_CHECK
          # is set). Per the constitution Operational Constraint, the
          # AppImage / DEB / RPM closures must carry a CA bundle so the
          # banner doesn't crash on a fresh user host. Future
          # --resolve-web2 work for tx-inspect (parallel to tx-diff)
          # would benefit from the same wrapper.
          txInspect = pkgs.symlinkJoin {
            name = "tx-inspect";
            paths = [ components.exes.tx-inspect ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/tx-inspect \
                --set-default SSL_CERT_FILE \
                  ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            '';
          };
          packageVersion =
            let
              versionLines =
                builtins.filter (lib.hasPrefix "version:")
                  (lib.splitString "\n"
                    (builtins.readFile ./cardano-tx-tools.cabal));
            in
            builtins.elemAt
              (builtins.match
                "version:[[:space:]]*([^[:space:]]+)"
                (builtins.head versionLines))
              0;
          sourceRevision =
            self.shortRev or (self.dirtyShortRev or "dirty");
          devArtifactVersion = "${packageVersion}-${sourceRevision}";
          mkDarwinHomebrewBundle =
            inputs.dev-assets.lib.mkDarwinHomebrewBundle { inherit pkgs; };
          # Single source of truth for every release-shipped exe.
          # Adding a new exe is one row here; the Linux + Darwin
          # outputs and both workflow matrices read from this list.
          exeSpecs = [
            {
              name = "tx-diff";
              package = txDiff;
              desc =
                "Compare Conway transactions with blueprint-aware data diffs";
              formulaClass = "TxDiff";
              formulaTest = ''
                output = shell_output("#{bin}/tx-diff 2>&1", 1)
                assert_match "Usage:", output
              '';
              usageGreps = [ "Usage:" "[--blueprint FILE ...]" ];
            }
            {
              name = "tx-validate";
              package = txValidate;
              desc =
                "Conway Phase-1 pre-flight against a local cardano-node";
              formulaClass = "TxValidate";
              formulaTest = ''
                output = shell_output("#{bin}/tx-validate 2>&1", 1)
                assert_match "tx-validate", output
              '';
              usageGreps = [ "tx-validate" "--n2c-socket-path PATH" ];
            }
            {
              name = "tx-inspect";
              package = txInspect;
              desc =
                "Render Conway transactions as structured, human-readable reports";
              formulaClass = "TxInspect";
              formulaTest = ''
                output = shell_output("#{bin}/tx-inspect 2>&1", 1)
                assert_match "Usage:", output
              '';
              usageGreps = [ "Usage:" "[--rules FILE]" ];
            }
            {
              name = "tx-sign";
              package = components.exes.tx-sign;
              desc =
                "Encrypted signing-key vault and detached witness emitter for Cardano";
              formulaClass = "TxSign";
              formulaTest = ''
                output = shell_output("#{bin}/tx-sign 2>&1", 1)
                assert_match "Usage:", output
              '';
              usageGreps = [ "Usage:" "Create or use an encrypted Cardano" ];
            }
            {
              # tx-graph does no HTTPS today (no github-release-check
              # banner, no --resolve-web2-style remote calls), so it
              # ships without the CA-bundle wrapper that txInspect /
              # txDiff need. Uses components.exes.tx-graph directly.
              # If tx-graph ever grows an HTTPS call, wrap it like
              # txInspect / txValidate.
              name = "tx-graph";
              package = components.exes.tx-graph;
              desc =
                "Emit Conway transactions and operator-entity overlays as RDF";
              formulaClass = "TxGraph";
              formulaTest = ''
                output = shell_output("#{bin}/tx-graph 2>&1", 1)
                assert_match "operator-entity overlay + body emitter", output
              '';
              usageGreps = [
                "Usage:"
                "operator-entity overlay + body emitter"
              ];
            }
            {
              name = "cardano-tx-generator";
              package = components.exes.cardano-tx-generator;
              desc =
                "Synthetic Cardano transaction load generator";
              formulaClass = "CardanoTxGenerator";
              formulaTest = ''
                output = shell_output("#{bin}/cardano-tx-generator 2>&1", 1)
                assert_match "--relay-socket PATH", output
              '';
              usageGreps = [ "Usage:" "--relay-socket PATH" ];
            }
          ];
          mkExeSmokeCommand = spec:
            ''
              set +e
              ${spec.name} >/tmp/${spec.name}.out 2>&1
              status="$?"
              set -e
              test "$status" -ne 0
            ''
            + lib.concatMapStringsSep "\n"
              (g: "  grep -F ${lib.escapeShellArg g} /tmp/${spec.name}.out >/dev/null")
              spec.usageGreps;
          # Parametric Darwin Homebrew bundle. Drop-in replacement for
          # the per-exe helpers; takes an exeSpec and override args.
          mkExeDarwinHomebrewBundle = spec: args:
            mkDarwinHomebrewBundle ({
              pname = spec.name;
              version = packageVersion;
              owner = "lambdasistemi";
              repo = "cardano-tx-tools";
              desc = spec.desc;
              formulaClass = spec.formulaClass;
              executables = { ${spec.name} = spec.package; };
              executableNames = [ spec.name ];
              formulaTest = spec.formulaTest;
              smokeCommands = [ (mkExeSmokeCommand spec) ];
            } // args);
          mkExeLinuxRelease = spec: extraArgs:
            import ./nix/linux-release.nix ({
              inherit pkgs system packageVersion;
              executableName = spec.name;
              package = spec.package;
              bundlers = inputs.bundlers;
            } // extraArgs);
          txDiffSpec =
            lib.findFirst (s: s.name == "tx-diff")
              (throw "exeSpecs is missing tx-diff")
              exeSpecs;
          darwinReleasePackages = lib.optionalAttrs
            pkgs.stdenv.isDarwin
            (lib.listToAttrs
              (lib.concatMap (spec: [
                {
                  name = "${spec.name}-darwin-release-artifacts";
                  value = mkExeDarwinHomebrewBundle spec { };
                }
                {
                  name = "${spec.name}-darwin-dev-homebrew-artifacts";
                  value = mkExeDarwinHomebrewBundle spec {
                    artifactVersion = devArtifactVersion;
                    releaseTag = "dev-homebrew-${spec.name}";
                    formulaName = "${spec.name}-dev";
                    formulaClass = "${spec.formulaClass}Dev";
                    formulaVersion = devArtifactVersion;
                  };
                }
              ]) exeSpecs)
            // {
              # Backward-compat aliases. The unprefixed names were
              # the tx-diff outputs before the Phase-6 refactor; keep
              # them so any external CI referencing them continues to
              # build until callers migrate to the prefixed form.
              # Use the same releaseTag (`dev-homebrew`) the original
              # dev-Homebrew workflow uses.
              darwin-release-artifacts =
                mkExeDarwinHomebrewBundle txDiffSpec { };
              darwin-dev-homebrew-artifacts =
                mkExeDarwinHomebrewBundle txDiffSpec {
                  artifactVersion = devArtifactVersion;
                  releaseTag = "dev-homebrew";
                  formulaName = "tx-diff-dev";
                  formulaClass = "TxDiffDev";
                  formulaVersion = devArtifactVersion;
                };
            });
          linuxReleasePackages = lib.optionalAttrs
            pkgs.stdenv.isLinux
            (lib.listToAttrs
              (lib.concatMap (spec: [
                {
                  name = "${spec.name}-linux-release-artifacts";
                  value = mkExeLinuxRelease spec { };
                }
                {
                  name = "${spec.name}-linux-dev-release-artifacts";
                  value = mkExeLinuxRelease spec {
                    artifactVersion = devArtifactVersion;
                  };
                }
              ]) exeSpecs)
            // {
              # Backward-compat aliases (tx-diff was unprefixed
              # pre-Phase-6); preserve so external callers don't
              # break on rename.
              linux-release-artifacts =
                mkExeLinuxRelease txDiffSpec { };
              linux-dev-release-artifacts =
                mkExeLinuxRelease txDiffSpec {
                  artifactVersion = devArtifactVersion;
                };
              linux-artifact-smoke =
                import ./nix/linux-artifact-smoke.nix {
                  inherit pkgs system;
                };
            });
          cardanoTxGeneratorImage =
            import ./nix/docker-image.nix {
              inherit pkgs components imageTag;
            };
          txValidateImage =
            import ./nix/tx-validate-docker-image.nix {
              inherit pkgs components imageTag;
            };
          checkSuite = import ./nix/checks.nix {
            inherit pkgs components lintPkgs;
            src = ./.;
            cardanoNode =
              cardano-node.packages.${system}.cardano-node;
            cardanoNodeClientsSrc = cardano-node-clients;
          };
          checkApps = import ./nix/apps.nix {
            inherit pkgs;
            inherit (checkSuite) scripts;
          };
        in {
          packages = {
            default = txDiff;
            tx-diff = txDiff;
            tx-inspect = txInspect;
            tx-sign = components.exes.tx-sign;
            tx-validate = txValidate;
            tx-graph = components.exes.tx-graph;
            cardano-tx-generator =
              components.exes.cardano-tx-generator;
          } // darwinReleasePackages // linuxReleasePackages
            // lib.optionalAttrs pkgs.stdenv.isLinux {
              cardano-tx-generator-image = cardanoTxGeneratorImage;
              tx-validate-image = txValidateImage;
            };
          checks = checkSuite.checks;
          apps = checkApps // {
            tx-diff = {
              type = "app";
              program = "${txDiff}/bin/tx-diff";
            };
            tx-sign = {
              type = "app";
              program = "${components.exes.tx-sign}/bin/tx-sign";
            };
            tx-validate = {
              type = "app";
              program = "${txValidate}/bin/tx-validate";
            };
            tx-inspect = {
              type = "app";
              program = "${txInspect}/bin/tx-inspect";
            };
            tx-graph = {
              type = "app";
              program = "${components.exes.tx-graph}/bin/tx-graph";
            };
            cardano-tx-generator = {
              type = "app";
              program = "${
                  components.exes.cardano-tx-generator
                }/bin/cardano-tx-generator";
            };
          } // lib.optionalAttrs pkgs.stdenv.isLinux {
            linux-artifact-smoke = {
              type = "app";
              program =
                "${linuxReleasePackages.linux-artifact-smoke}/bin/linux-artifact-smoke";
            };
          };
          devShells.default = project.shell;
        };
    };
}

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
    dev-assets.url = "github:paolino/dev-assets/v0.1.0";
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
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
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
          } // lib.optionalAttrs (lib.elem system [ "x86_64-linux" "aarch64-linux" ]) {
            # liburing is Linux-only (both x86_64 and aarch64); gated at the
            # modules-list construction level via the outer `system` string so
            # it never references blockio-uring on Darwin where it is not in
            # the build plan.
            packages.blockio-uring.components.library.pkgconfig =
              lib.mkForce [ [ pkgs.liburing ] ];
          };
          # librocksdb.a (static musl) calls into lz4/zstd/bz2/snappy, but
          # rocksdb-haskell-jprupp only declares `extra-libraries: rocksdb`, so
          # the static musl link of cardano-tx-generator (the only rocksdb
          # consumer) leaves those undefined. Add the static archives
          # (pkgsStatic so the .a actually exists — the plain musl lz4/snappy
          # ship no static lib) and group them so the linker resolves the cycle.
          # This module is unconditional but only goes into muslProject below, so
          # glibc links rocksdb dynamically and darwin's ld64 never sees
          # --start-group. (Gating the module on pkgs.* recurses; routing it via
          # a dedicated project is the reliable way to scope it to the cross.)
          fix-rocksdb-static = { pkgs, ... }: {
            packages.cardano-tx-tools.components.exes.cardano-tx-generator = {
              # librocksdb.a (musl) links compression (lz4/zstd/bz2/snappy) plus
              # liburing (async IO) and numactl on Linux.
              libs = with pkgs.pkgsStatic; [ lz4 zstd bzip2 snappy liburing numactl ];
              ghcOptions = [
                "-optl-Wl,--start-group"
                "-optl-llz4"
                "-optl-lzstd"
                "-optl-lbz2"
                "-optl-lsnappy"
                "-optl-luring"
                "-optl-lnuma"
                "-optl-Wl,--end-group"
              ];
            };
          };
          mkProject = extraModules: pkgs.haskell-nix.cabalProject' {
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
                pkgs.apache-jena
                pkgs.lmdb
                pkgs.liburing
                mkdocs.packages.${system}.from-nixpkgs
                mkdocs.packages.${system}.asciinema-plugin
              ];
              shellHook = ''
                export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              '';
            };
            modules = [ fix-libs ] ++ extraModules
              ++ [ { packages.cardano-tx-tools.flags.werror = true; } ];
            inputMap = {
              "https://chap.intersectmbo.org/" = CHaP;
            };
          };
          # Native project (x86_64/aarch64 glibc + darwin) — no rocksdb fix.
          project = mkProject [ ];
          # Musl-cross project carries the rocksdb static-link fix; consumed
          # only via projectCross below, so glibc/darwin stay untouched.
          muslProject = mkProject [ fix-rocksdb-static ];
          components = project.hsPkgs.cardano-tx-tools.components;
          # Static musl cross for the per-arch musl tarball. Cross-compiled
          # from the native build platform (x86_64-linux -> x86_64 musl;
          # aarch64-linux -> aarch64 musl), so the cross plan evaluates without
          # an aarch64 builder. Raw exes (no SSL wrapper) — static binaries.
          muslComponents =
            if system == "x86_64-linux"
            then muslProject.projectCross.musl64.hsPkgs.cardano-tx-tools.components
            else if system == "aarch64-linux"
            then muslProject.projectCross.aarch64-multiplatform-musl.hsPkgs.cardano-tx-tools.components
            else null;
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
          # tx-fetch hits Blockfrost over HTTPS for every CBOR fetch,
          # so the AppImage / DEB / RPM closures must carry a CA bundle.
          # Same wrapper shape as txDiff.
          txFetch = pkgs.symlinkJoin {
            name = "tx-fetch";
            paths = [ components.exes.tx-fetch ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/tx-fetch \
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
              darwinPackage = components.exes.tx-diff;
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
              darwinPackage = components.exes.tx-validate;
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
              darwinPackage = components.exes.tx-inspect;
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
              name = "tx-fetch";
              package = txFetch;
              darwinPackage = components.exes.tx-fetch;
              desc =
                "Walk a closure of Conway transactions over Blockfrost and write one CBOR per tx";
              formulaClass = "TxFetch";
              formulaTest = ''
                output = shell_output("#{bin}/tx-fetch 2>&1", 1)
                assert_match "Usage:", output
              '';
              usageGreps = [
                "Usage:"
                "closure-walking Conway CBOR fetcher"
              ];
            }
            {
              # tx-view is the offline packaged-view runner. Like
              # tx-graph it does no HTTPS today, so no CA-bundle
              # wrapper is needed; if a future view ever calls out
              # over the network, wrap it like txInspect.
              name = "tx-view";
              package = components.exes.tx-view;
              desc =
                "Project canonical Turtle graphs through packaged SPARQL views";
              formulaClass = "TxView";
              formulaTest = ''
                output = shell_output("#{bin}/tx-view 2>&1", 1)
                assert_match "packaged-view dispatcher", output
              '';
              usageGreps = [
                "Usage:"
                "packaged-view dispatcher"
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
            # `grep -F --` is required on macOS: BSD grep parses any
            # argument starting with `--` as a long option, so without
            # the `--` terminator patterns like `--n2c-socket-path PATH`
            # or `--relay-socket PATH` trip the option parser.
            ''
              set +e
              ${spec.name} >/tmp/${spec.name}.out 2>&1
              status="$?"
              set -e
              test "$status" -ne 0
            ''
            + lib.concatMapStringsSep "\n"
              (g: "  grep -F -- ${lib.escapeShellArg g} /tmp/${spec.name}.out >/dev/null")
              spec.usageGreps;
          # Resolve the Darwin-side package: prefer `darwinPackage` if the
          # spec declares one, else fall back to `package`. The wrapped
          # Linux variants (txDiff, txValidate, txInspect) bundle a
          # cacert via `wrapProgram`, which leaves the wrapper script
          # referencing a nix-store path not present in the Darwin
          # tarball's closure on a consumer machine. macOS has system
          # certs, so Darwin uses the raw `components.exes.<name>`
          # output and skips the wrapper entirely.
          darwinPackageOf = spec: spec.darwinPackage or spec.package;
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
              executables = { ${spec.name} = darwinPackageOf spec; };
              executableNames = [ spec.name ];
              formulaTest = spec.formulaTest;
              smokeCommands = [ (mkExeSmokeCommand spec) ];
            } // args);
          # Linux artifacts now come from the shared dev-assets lib (pinned via
          # the flake input) instead of the per-repo nix/linux-release.nix.
          # bundlers is the same NixOS/bundlers rev dev-assets pins, so the
          # AppImage runtime tooling is identical fleet-wide. muslPackage is
          # added in the musl-cross slice.
          mkExeLinuxRelease = spec: extraArgs:
            inputs.dev-assets.lib.mkLinuxArtifacts ({
              inherit pkgs system;
              executableName = spec.name;
              version = packageVersion;
              glibcPackage = spec.package;
              muslPackage = muslComponents.exes.${spec.name};
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
                # Full symmetric matrix on both arches (the lib default).
                inputs.dev-assets.lib.mkLinuxArtifactSmoke {
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
            tx-fetch = txFetch;
            tx-view = components.exes.tx-view;
            cardano-tx-generator =
              components.exes.cardano-tx-generator;
          } // darwinReleasePackages // linuxReleasePackages
            // lib.optionalAttrs pkgs.stdenv.isLinux {
              cardano-tx-generator-image = cardanoTxGeneratorImage;
              tx-validate-image = txValidateImage;
            };
          # The cli-tree slice of #51 needs the tx-view binary on the
          # unit check's PATH so Cardano.Tx.View.CliTreeGoldenSpec can
          # spawn it. The nix-check sandbox has no cabal on PATH, so
          # the check is replaced with a tx-view-aware wrapper. The
          # base unit script (built by nix/checks.nix) still runs
          # underneath; this wrapper just adds TX_VIEW_EXE to the
          # environment first.
          checks = checkSuite.checks // {
            unit = pkgs.runCommand "unit-check"
              {
                nativeBuildInputs =
                  pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux
                    [ pkgs.glibcLocales ];
                LANG = "C.UTF-8";
                LC_ALL = "C.UTF-8";
              } ''
                set -euo pipefail
                cd ${./.}
                export TX_VIEW_EXE=${components.exes.tx-view}/bin/tx-view
                ${pkgs.lib.getExe checkSuite.scripts.unit}
                touch "$out"
              '';
          };
          apps = checkApps // {
            # Override apps.unit so `nix run .#unit` (what CI calls)
            # exports TX_VIEW_EXE before invoking the script — same
            # treatment the checks.unit derivation above gets. Without
            # this the unit-tests fail in CI on the four Cardano.Tx.View
            # spec families that spawn tx-view as a subprocess.
            unit = {
              type = "app";
              program = "${pkgs.writeShellApplication {
                name = "unit-with-tx-view";
                runtimeInputs = [ checkSuite.scripts.unit ];
                text = ''
                  export TX_VIEW_EXE=${components.exes.tx-view}/bin/tx-view
                  exec ${pkgs.lib.getExe checkSuite.scripts.unit} "$@"
                '';
              }}/bin/unit-with-tx-view";
            };
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
            tx-fetch = {
              type = "app";
              program = "${txFetch}/bin/tx-fetch";
            };
            tx-view = {
              type = "app";
              program = "${components.exes.tx-view}/bin/tx-view";
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

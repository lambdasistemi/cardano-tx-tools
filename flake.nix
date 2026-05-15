{
  description =
    "Cardano transaction tooling (builder, structural diff, blueprint)";
  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
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
    CHaP = {
      url =
        "github:intersectmbo/cardano-haskell-packages/887d73ce434831e3a67df48e070f4f979b3ac5a6";
      flake = false;
    };
    mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
  };

  outputs = inputs@{ self, nixpkgs, lintNixpkgs, flake-parts, haskellNix
    , hackageNix, CHaP, mkdocs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { system, ... }:
        let
          pkgs = import nixpkgs {
            overlays = [ haskellNix.overlay ];
            inherit system;
          };
          lintPkgs = import lintNixpkgs { inherit system; };
          indexState = "2026-02-17T10:15:41Z";
          indexTool = { index-state = indexState; };
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
                mkdocs.packages.${system}.from-nixpkgs
              ];
              shellHook = ''
                export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              '';
            };
            inputMap = {
              "https://chap.intersectmbo.org/" = CHaP;
            };
          };
          components = project.hsPkgs.cardano-tx-tools.components;
          checkSuite = import ./nix/checks.nix {
            inherit pkgs components lintPkgs;
            src = ./.;
          };
          checkApps = import ./nix/apps.nix {
            inherit pkgs;
            inherit (checkSuite) scripts;
          };
        in {
          packages = {
            default = components.library;
          };
          checks = checkSuite.checks;
          apps = checkApps;
          devShells.default = project.shell;
        };
    };
}

{
  description = "resorter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
  };

  outputs = { self, nixpkgs, devshell, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        p2n = pkgs.poetry2nix;
        python = "python39";
        r-packages = with pkgs.rPackages; [
          rlang
          styler
          httr
          feather
          BradleyTerry2
          argparser
          tidyverse
          jsonlite
          jqr
          dplyr
          purrr
          crayon
        ];

        R-with-packages = pkgs.rWrapper.override { packages = r-packages; };
        customOverrides = self: super: { };
        packageName = "Resorter";

        app = p2n.mkPoetryApplication {
          projectDir = ./.;
          python = pkgs.python39;
          overrides =
            [ p2n.defaultPoetryOverrides customOverrides ];
        };
        pythonEnv = p2n.mkPoetryEnv {
          projectDir = ./.;
          python = pkgs.python39;
          overrides =
            [ p2n.defaultPoetryOverrides customOverrides ];
        };
      in {
        packages.containerImage = pkgs.dockerTools.buildLayeredImage {
          name = "resorter";
          contents = [ pkgs.python39 ];
          config = {
            Cmd = [ "${pkgs.python3}/bin/python" "-c" "print('hello world')" ];
          };
        };

        packages.${packageName} = app;
        defaultPackage = self.packages.${system}.${packageName};
        devShell = let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ devshell.overlay ];
          };
        in pkgs.devshell.mkShell {
          imports = [ (pkgs.devshell.importTOML ./devshell.toml) ];
          # buildInputs = with pkgs; [ poetry ];
          devshell.packages = with pkgs; [
            pythonEnv
            poetry
            # python39.pkgs.black
            # (pkgs.${python}.withPackages (p: with p; [ pip black ]))
            R-with-packages
          ];
        };
      });
}

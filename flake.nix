{
  description = "resorter";

  inputs = {
    nixpkgs.url = "git://github.com/NixOS/nixpkgs.git";
    flake-utils.url = "git://github.com/numtide/flake-utils.git";
    devshell.url = "git://github.com/numtide/devshell.git";
  };

  outputs = { self, nixpkgs, devshell, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ ];
        pkgs = import nixpkgs {
          inherit system overlays;
          config.allowBroken = true;
        };
        p2n = pkgs.poetry2nix;
        python = "python39";
        r-packages = with pkgs.rPackages; [
          rlang
          # styler
          httr
          rio
          arrow
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
          overrides = [ p2n.defaultPoetryOverrides customOverrides ];
        };
        pythonEnv = p2n.mkPoetryEnv {
          projectDir = ./.;
          python = pkgs.python39;
          overrides = [ p2n.defaultPoetryOverrides customOverrides ];
        };
      in
      {
        packages.containerImage = pkgs.dockerTools.buildLayeredImage {
          name = "resorter";
          contents = [ pkgs.python39 app ];
          config = {
            Cmd = [ "${pkgs.python3}/bin/python" "-c" "print('hello world')" ];
          };
        };

        packages.${packageName} = app;
        defaultPackage = self.packages.${system}.${packageName};
        devShell =
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ devshell.overlay ];
            };
          in
          pkgs.devshell.mkShell {
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

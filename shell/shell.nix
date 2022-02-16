{ pkgs, extraModulesPath, ... }:
let
  # hooks = import ./hooks;
  pkgWithCategory = category: package: { inherit package category; };
  linter = pkgWithCategory "linter";
  docs = pkgWithCategory "docs";
  devos = pkgWithCategory "devos";

in {
  devshell.startup.load_profiles = pkgs.lib.mkForce (pkgs.lib.noDepEntry ''
    # PATH is devshell's exorbitant privilige:
    # fence against its pollution
    _PATH=''${PATH}
    # Load installed profiles
    for file in "$DEVSHELL_DIR/etc/profile.d/"*.sh; do
      # If that folder doesn't exist, bash loves to return the whole glob
      [[ -f "$file" ]] && source "$file"
    done
    # Exert exorbitant privilige and leave no trace
    export PATH=''${_PATH}
    unset _PATH
  '');

  packages = with pkgs; [
    git-crypt
  ];

    # flake-utils.lib.eachDefaultSystem (system:
    #   let
    #     pkgs = nixpkgs.legacyPackages.${system};
    #     python = "python39";
    #     my-r-packages = with pkgs.rPackages; [
    #       rlang
    #       styler
    #       # R
    #       httr
    #       BradleyTerry2
    #       argparser
    #       tidyverse
    #       jsonlite
    #       jqr
    #       dplyr
    #       purrr
    #       crayon
    #     ];

    #     R-with-my-packages =
    #       pkgs.rWrapper.override { packages = my-r-packages; };

    #     customOverrides = self: super:
    #       {
    #         # Overrides go here
    #       };

    #     app = pkgs.poetry2nix.mkPoetryApplication {
    #       projectDir = ./.;
    #       overrides =
    #         [ pkgs.poetry2nix.defaultPoetryOverrides customOverrides ];
    #     };

    #     packageName = "Resorter";
    #   in {
    #     packages.${packageName} = app;
    #     defaultPackage = self.packages.${system}.${packageName};
    #     devShell = pkgs.mkShell {
    #       buildInputs = with pkgs; [
    #         poetry
    #         # (pkgs.${python}.withPackages
    #         #   (ps: with ps; [ pip black jello pandas httpx ]))
    #         # python
    #         R
    #         my-r-packages
    #       ];
    #       inputsFrom = builtins.attrValues self.packages.${system};
    #     };

    #     # devShell = pkgs.mkShell {
    #     #   buildInputs = [
    #     #     # dev packages
    #     #     (pkgs.${python}.withPackages
    #     #       (ps: with ps; [ pip black pyflakes isort ])) # <--- change here
    #     #     pkgs.nodePackages.pyright
    #     #     pkgs.glpk

    #     #     # app packages
    #     #     # pythonBuild
    #     #   ];
    #     # };

    #   });

}

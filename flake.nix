{
  description = "resorter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?rev=c82b46413401efa740a0b994f52e9903a4f6dcd5";
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
      projectDir = ./src/presorter;
      python = pkgs.python39;
    };
    pythonEnv = p2n.mkPoetryEnv {
      projectDir = ./src/presorter;
      python = pkgs.python39;
      overrides = [ p2n.defaultPoetryOverrides customOverrides ];
    };
    resort-entrypoint = "resort-script";
    resort-entrypoint-buildInputs = with pkgs; [ ];
    resort-script = (pkgs.writeScriptBin resort-entrypoint (builtins.readFile ./src/resort)).overrideAttrs(old: {
      buildInputs = with pkgs; [ zsh ];
      buildCommand = ''
        ${old.buildCommand}
        patchShebangs $out
      '';
    });
  in rec
  {
    packages.resort-script = pkgs.symlinkJoin {
      name = resort-entrypoint;
      paths = [ resort-script ] ++ resort-entrypoint-buildInputs;
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/${resort-entrypoint} --prefix PATH : $out/bin
      '';
    };
    packages.containerImage = pkgs.dockerTools.buildLayeredImage {
      name = "resorter";
      contents = [ pkgs.python39 app resort-script pkgs.bash pkgs.coreutils pkgs.findutils pkgs.gnugrep ];
      config = {
        # Cmd = [ "${app}/bin/presort" ];
        Cmd = [ "${resort-entrypoint}" ];
      };
    };

    # packages.${packageName} = app;
    packages.presorter = app;
    defaultPackage = app;
    devShell =
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ devshell.overlay ];
        };
      in
      pkgs.devshell.mkShell {
        imports = [ (pkgs.devshell.importTOML ./devshell.toml) ];
        devshell.packages = with pkgs; [
          pythonEnv
          poetry
          R-with-packages
        ];
      };
  });
}

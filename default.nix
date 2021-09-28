with import <nixpkgs> { }; {
  resorter = stdenv.mkDerivation {
    name = "resorter";
    version = "1";
    src = if lib.inNixShell then null else nix;

    buildInputs = with rPackages; [
      R
      httr
      BradleyTerry2
      argparser
      tidyverse
      jsonlite
      jqr
      dplyr
      purrr
    ];
  };
  # rEnv = pkgs.rWrapper.override {
  #   packages = with pkgs.rPackages; [
  #     R
  #     ggplot2
  #     knitr
  #     BradleyTerry2
  #     argparser
  #     RCurl
  #   ];
  # };
}

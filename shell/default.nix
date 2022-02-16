{ self, inputs, ... }:
{
  # externalModules = with inputs; [
  #   bud.devshellModules.bud
  # ];
  exportedModules = [ ./python.toml ];
  modules = [
    ./shell.nix
  ];
}

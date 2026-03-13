{ self, inputs, ... }:
{
  flake.homeModules.base-home =
    { ... }:
    {
      imports = [
        self.homeModules.configuration
        self.homeModules.shell
        self.homeModules.git-configuration
        inputs.nix-index-database.hmModules.nix-index
      ];
    };

}

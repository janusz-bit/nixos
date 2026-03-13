{ self, inputs, ... }:
{
  flake.homeModules.base-home =
    { ... }:
    {
      imports = [
        self.nixosModules.configuration
        self.nixosModules.shell
        self.nixosModules.git-configuration
        inputs.nix-index-database.nixosModules.default
      ];
    };

}

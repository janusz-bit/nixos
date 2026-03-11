{ self, inputs, ... }:
{
  flake.nixosModules.base =
    { ... }:
    {
      imports = [
        self.nixosModules.configuration
        self.nixosModules.shell
        self.nixosModules.git-configuration
        self.nixosModules.shell
        inputs.nix-index-database.nixosModules.default
      ];
    };

}

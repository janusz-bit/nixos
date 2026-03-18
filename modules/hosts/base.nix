{ self, inputs, ... }:
{
  flake.nixosModules.base =
    { ... }:
    {
      imports = [
        self.nixosModules.configuration
        self.nixosModules.shell
        self.nixosModules.git-configuration
        self.nixosModules.nix-settings
        self.nixosModules.ssh
        self.nixosModules.cachix-janusz-bit
        inputs.nix-index-database.nixosModules.default
      ];
    };

}

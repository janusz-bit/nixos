{ self, ... }:
{
  flake.nixosModules.nixos =
    { ... }:
    {
      imports = [
        self.nixosModules.nixos-specific
        self.nixosModules.nixos-configuration
        self.nixosModules.nixos-hardware-configuration
        self.nixosModules.nixos-packages
        self.nixosModules.nixos-db
        self.nixosModules.disko
      ];
    };
}

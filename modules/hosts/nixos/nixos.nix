{ self, ... }:
{
  flake.nixosModules.nixos =
    { ... }:
    {
      imports = [
        self.nixosModules.nixos-stateVersion
        self.nixosModules.nixos-configuration
        self.nixosModules.nixos-hardware-configuration
        self.nixosModules.nixos-packages
        self.nixosModules.nixos-specific
      ];
    };
}

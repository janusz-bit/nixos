{ self, ... }:
{
  flake.nixosModules.raspberry-pi-4 =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.raspberry-pi-4-hardware-configuration
        self.nixosModules.raspberry-pi-4-specific
        self.nixosModules.raspberry-pi-4-specific-configuration
        self.nixosModules.raspberry-pi-4-configuration
      ];
    };
}

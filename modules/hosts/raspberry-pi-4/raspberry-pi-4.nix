{ self, inputs, ... }:
{
  flake.nixosModules.raspberry-pi-4 =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.raspberry-pi-4-hardware-configuration
        self.nixosModules.raspberry-pi-4-specific
        self.nixosModules.raspberry-pi-4-configuration
        # inputs.nixos-hardware.nixosModules.raspberry-pi-4
        (_: {
          custom.flakeTarget = "raspberry-pi-4";
          custom.defaultUser = "nixos";
        })
      ];
    };
}

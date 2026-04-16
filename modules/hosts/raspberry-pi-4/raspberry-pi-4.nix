{ self, inputs, ... }:
{
  flake.nixosModules.raspberry-pi-4 =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.raspberry-pi-4-hardware-configuration
        self.nixosModules.raspberry-pi-4-disko
        self.nixosModules.raspberry-pi-4-nextcloud
        self.nixosModules.agenix
        self.nixosModules.raspberry-pi-4-specific
        self.nixosModules.raspberry-pi-4-configuration
        inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4
        # self.nixosModules.base
        self.nixosModules.options
        (_: {
          custom.flakeTarget = "raspberry-pi-4";
          custom.defaultUser = "nixos";
        })
      ];
    };
}

{ self, inputs, ... }:
{
  flake.nixosModules.raspberry-pi-4 =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.raspberry-pi-4-nextcloud
        self.nixosModules.agenix
        self.nixosModules.raspberry-pi-4-specific
        self.nixosModules.raspberry-pi-4-configuration
        inputs.nixos-hardware.nixosModules.raspberry-pi-4
        inputs.nixos-raspberrypi.nixosModules.nixos-raspberrypi.lib.inject-overlays
        inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches
        inputs.nixos-raspberrypi.nixosModules.nixpkgs-rpi
        self.nixosModules.git-configuration
        self.nixosModules.configuration
        self.nixosModules.options
        (_: {
          custom.flakeTarget = "raspberry-pi-4";
          custom.defaultUser = "nixos";
        })
      ];
    };
}

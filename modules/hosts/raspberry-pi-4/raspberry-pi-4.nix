{ self, inputs, ... }:
{
  flake.nixosModules."raspberry-pi-4" =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules."raspberry-pi-4/nextcloud"
        # self.nixosModules."raspberry-pi-4/cloudflared"
        self.nixosModules."agenix"
        self.nixosModules."raspberry-pi-4/specific"
        self.nixosModules."raspberry-pi-4/configuration"
        inputs.nixos-hardware.nixosModules.raspberry-pi-4
        self.nixosModules."base/git"
        self.nixosModules."base/configuration"
        self.nixosModules."options"
        (_: {
          custom.flakeTarget = "raspberry-pi-4";
          custom.defaultUser = "nixos";
        })
      ];
    };
}

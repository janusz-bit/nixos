# IMPORTANT: changes have to be written to config.txt directly
# sudo mount /dev/disk/by-label/FIRMWARE /mnt
# sudo micro /mnt/config.txt # <-- make changes here
# dtparam=audio=on
{
  inputs,
  self,
  lib,
  ...
}:
{
  flake.nixosModules."raspberry-pi-4" =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules."raspberry-pi-4/nextcloud"
        self.nixosModules."raspberry-pi-4/trilium"
        self.nixosModules."raspberry-pi-4/cloudflared"
        self.nixosModules."raspberry-pi-4/pwm-fan"
        self.nixosModules."raspberry-pi-4/hermes"
        # self.nixosModules."raspberry-pi-4/hermes-webui"
        self.nixosModules."raspberry-pi-4/open-webui"
        self.nixosModules."base/agenix"
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

  flake.nixosConfigurations.raspberry-pi-4 = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = "aarch64-linux"; }
      self.nixosModules."raspberry-pi-4"
      self.nixosModules."raspberry-pi-4/hardware-configuration"
    ];
  };
}

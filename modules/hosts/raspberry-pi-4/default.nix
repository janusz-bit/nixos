# IMPORTANT: changes have to be written to config.txt directly
# sudo mount /dev/disk/by-label/FIRMWARE /mnt
# sudo micro /mnt/config.txt # <-- make changes here
# dtparam=audio=on
{
  inputs,
  self,
  lib,
  config,
  ...
}:
{
  flake.modules.nixos.raspberry-pi-4 =
    { pkgs, ... }:
    {
      imports = [
        self.modules.nixos.nextcloud
        self.modules.nixos.trilium
        self.modules.nixos.cloudflared
        self.modules.nixos.pwm-fan
        self.modules.nixos.leds-off
        self.modules.nixos.hermes
        self.modules.nixos.open-webui
        self.modules.nixos.base-agenix
        self.modules.nixos.rpi-specific
        self.modules.nixos.rpi-configuration
        inputs.nixos-hardware.nixosModules.raspberry-pi-4
        self.modules.nixos.base-git
        self.modules.nixos.base-configuration
        self.modules.nixos.options
        (_: {
          customBot.flakeTarget = "raspberry-pi-4";
          customBot.defaultUser = "nixos";
        })
      ];
    };

  flake.nixosConfigurations.raspberry-pi-4 = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = "aarch64-linux"; }
      self.modules.nixos.raspberry-pi-4
      self.modules.nixos.rpi-hardware-configuration
    ];
  };
}

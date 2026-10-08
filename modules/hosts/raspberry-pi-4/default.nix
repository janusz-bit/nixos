# IMPORTANT: changes have to be written to config.txt directly
# sudo mount /dev/disk/by-label/FIRMWARE /mnt
# sudo micro /mnt/config.txt # <-- make changes here
# dtparam=audio=on
{
  inputs,
  self,
  ...
}:
{
  flake.modules.nixos.raspberry-pi-4 = _: {
    imports = [
      self.modules.nixos.base
      self.modules.nixos.fail2ban
      self.modules.nixos.nextcloud
      self.modules.nixos.trilium
      self.modules.nixos.gitea
      self.modules.nixos.cloudflared
      self.modules.nixos.pwm-fan
      self.modules.nixos.leds-off
      self.modules.nixos.hermes
      self.modules.nixos.open-webui
      self.modules.nixos.ttyd
      self.modules.nixos.rpi-wifi
      self.modules.nixos.rpi-laptop-remote
      self.modules.nixos.ai-skills
      self.modules.nixos.rpi-specific
      self.modules.nixos.rpi-configuration
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
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

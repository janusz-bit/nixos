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
      self.modules.nixos.base-fail2ban
      self.modules.nixos.rpi-nextcloud
      self.modules.nixos.rpi-trilium
      self.modules.nixos.rpi-gitea
      self.modules.nixos.rpi-cloudflared
      self.modules.nixos.hardware-raspberry-pi-4-fan
      self.modules.nixos.hardware-raspberry-pi-4
      self.modules.nixos.rpi-hermes
      self.modules.nixos.rpi-matrix
      self.modules.nixos.rpi-claude-notify
      self.modules.nixos.rpi-open-webui
      self.modules.nixos.rpi-ttyd
      self.modules.nixos.rpi-network
      self.modules.nixos.rpi-remote-agent
      self.modules.nixos.ai-skills
      self.modules.nixos.rpi-specific
      self.modules.nixos.rpi-configuration
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
      # Ustawia to też rejestr hostów; tutaj dla obrazu SD
      # (raspberry-pi-4-sd-image), który składa ten moduł poza rejestrem.
      { customBot.flakeTarget = "raspberry-pi-4"; }
    ];
  };

  hosts.raspberry-pi-4 = {
    system = "aarch64-linux";
    modules = [
      self.modules.nixos.raspberry-pi-4
      ./_hardware-configuration.nix
    ];
  };
}

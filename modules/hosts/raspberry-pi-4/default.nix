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
      # Bez fail2ban: SSH przychodzi tu tylko z LAN-u (zapora,
      # rpi-configuration) albo przez tunel z pętli zwrotnej — oba źródła
      # były na liście ignorowanych, więc jail nie mógł nikogo zbanować.
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
      self.modules.nixos.ai-skills
      self.modules.nixos.rpi-specific
      self.modules.nixos.rpi-configuration
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
      (_: {
        customBot = {
          flakeTarget = "raspberry-pi-4";
          defaultUser = "nixos";
          # Serwer z internetu: tylko to, czego używa (prime-agent, hermes,
          # nix access-tokens). Bez tokenu zapisu do cachix (zaufanego przez
          # wszystkie hosty), kluczy opencode/gemini i notatek. RPi zostaje
          # odbiorcą wszystkich plików .age (rekeying), ale ich nie odszyfrowuje.
          userSecrets = [
            "github-token"
            "ollama-api-key"
            "openrouter-api-key"
            "trilium-etapi"
          ];
        };
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

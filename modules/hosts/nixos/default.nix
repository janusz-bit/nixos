{
  inputs,
  self,
  ...
}:
{
  flake.modules.nixos.nixos = _: {
    imports = [
      self.modules.nixos.nixos-specific
      self.modules.nixos.nixos-configuration
      self.modules.nixos.nixos-packages
      self.modules.nixos.desktop-devenv
      self.modules.nixos.desktop-podman
      self.modules.nixos.nixos-disko
      self.modules.nixos.base-fail2ban
      self.modules.nixos.desktop-ai
      self.modules.nixos.ai-skills
      self.modules.nixos.nixos-appimage-run
      self.modules.nixos.desktop-autostart
      self.modules.nixos.desktop-browsers
      self.modules.nixos.gaming-dbd
      self.modules.nixos.gaming-deadlock
      self.modules.nixos.gaming-steam
      self.modules.nixos.nixos-snapper
      self.modules.nixos.nixos-remote-agent
      self.modules.nixos.nixos-claude-notify
      self.modules.nixos.desktop-tuning
    ];
  };

  hosts.nixos = {
    system = "x86_64-linux";
    # Ciężki build (~400 pakietów, 3-5 h) — CI tylko przy PR i ręcznie.
    buildOnTags = false;
    modules = [
      self.modules.nixos.base
      self.modules.nixos.nixos
      self.modules.nixos.hardware-LOQ-15IRX10
      # Chaotic-Nyx: overlay z bleeding-edge pakietami (proton-cachyos_x86_64_v3,
      # proton-ge-custom, mangohud_git...) bez binary cache nyx.
      inputs.chaotic.nixosModules.default
      {
        customBot = {
          defaultUser = "dinosaur";
          # Desktopowy Trilium (trilium-desktop, ETAPI/MCP na 37840),
          # a nie trilium-server:8081 z raspberry-pi-4.
          triliumMcpUrl = "http://127.0.0.1:37840/mcp";
        };
        # Nadal używamy overlaya (pakiety), ale bez binary cache nyx.
        chaotic.nyx.cache.enable = false;
      }
    ];
  };

  flake.nixosConfigurations.default = self.nixosConfigurations.nixos;
}

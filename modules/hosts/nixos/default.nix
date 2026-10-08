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
      self.modules.nixos.nixos-hardware-configuration
      self.modules.nixos.nixos-packages
      self.modules.nixos.nixos-podman
      self.modules.nixos.disko
      self.modules.nixos.fail2ban
      self.modules.nixos.nixos-ai
      self.modules.nixos.ai-skills
      self.modules.nixos.nixos-appimage-run
      self.modules.nixos.nixos-helium
      self.modules.nixos.nixos-dbd
      self.modules.nixos.nixos-gaming
      self.modules.nixos.nixos-snapper
      self.modules.nixos.nixos-remote-agent
      # VFIO + libvirt/virt-manager tymczasowo wyłączone.
      # Procedura ponownego włączenia: modules/hosts/nixos/vfio.nix.
      # self.modules.nixos.nixos-vfio
    ];
  };

  flake.nixosConfigurations = {
    nixos = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.modules.nixos.base
        self.modules.nixos.nixos
        self.modules.nixos.hardware-LOQ-15IRX10
        # Chaotic-Nyx: overlay z bleeding-edge pakietami (proton-cachyos_x86_64_v3,
        # proton-ge-custom, mangohud_git...) bez binary cache nyx.
        inputs.chaotic.nixosModules.default
        (_: {
          customBot = {
            flakeTarget = "nixos";
            defaultUser = "dinosaur";
            # Desktopowy Trilium (trilium-desktop, ETAPI/MCP na 37840),
            # a nie trilium-server:8081 z raspberry-pi-4.
            triliumMcpUrl = "http://127.0.0.1:37840/mcp";
          };
          # Nadal używamy overlaya (pakiety), ale bez binary cache nyx.
          chaotic.nyx.cache.enable = false;
        })
      ];
    };

    default = self.nixosConfigurations.nixos;
  };
}

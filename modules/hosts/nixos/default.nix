{
  inputs,
  self,
  config,
  ...
}:
{
  flake.modules.nixos.nixos =
    { ... }:
    {
      imports = [
        self.modules.nixos.nixos-specific
        self.modules.nixos.nixos-configuration
        self.modules.nixos.nixos-hardware-configuration
        self.modules.nixos.nixos-packages
        self.modules.nixos.nixos-podman
        self.modules.nixos.disko
        # self.modules.nixos.nixos-niri
        self.modules.nixos.nixos-ai
        self.modules.nixos.ai-skills
        self.modules.nixos.nixos-appimage-run
        self.modules.nixos.nixos-gaming
        self.modules.nixos.nixos-snapper
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
        # proton-ge-custom, mangohud_git, linux_cachyos...) + własny binary cache.
        inputs.chaotic.nixosModules.default
        (_: {
          customBot.flakeTarget = "nixos";
          customBot.defaultUser = "dinosaur";
        })
      ];
    };

    default = self.nixosConfigurations.nixos;
  };
}

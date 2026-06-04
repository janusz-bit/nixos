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
        self.modules.nixos.nixos-niri
        self.modules.nixos.nixos-ai
        self.modules.nixos.nixos-appimage-run
      ];
    };

  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.modules.nixos.base
      self.modules.nixos.nixos
      self.modules.nixos.hardware-LOQ-15IRX10
      (_: {
        customBot.flakeTarget = "nixos";
        customBot.defaultUser = "dinosaur";
      })
    ];
  };

  flake.nixosConfigurations.default = self.nixosConfigurations.nixos;
}

{ inputs, self, ... }:
rec {
  flake.nixosModules.nixos =
    { ... }:
    {
      imports = [
        self.nixosModules."nixos/specific"
        self.nixosModules."nixos/configuration"
        self.nixosModules."nixos/hardware-configuration"
        self.nixosModules."nixos/packages"
        # self.nixosModules."nixos/openclaw"
        self.nixosModules."nixos/podman"
        self.nixosModules."disko"
        self.nixosModules."nixos/niri"
        self.nixosModules."nixos/ai"
        self.nixosModules."nixos/appimage-run"
      ];
    };

  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules."base"
      self.nixosModules.nixos
      self.nixosModules."hardware/LOQ-15IRX10"
      (_: {
        customBot.flakeTarget = "nixos";
        customBot.defaultUser = "dinosaur";
      })
    ];
  };

  flake.nixosConfigurations.default = flake.nixosConfigurations.nixos;
}

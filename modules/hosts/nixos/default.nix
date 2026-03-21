{ inputs, self, ... }:
rec {
  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.base
      self.nixosModules.nixos
      self.nixosModules.nixos-hardware-LOQ-15IRX10
      (_: { custom.flakeTarget = "nixos"; })
    ];
  };

  flake.nixosConfigurations.default = flake.nixosConfigurations.nixos;
}

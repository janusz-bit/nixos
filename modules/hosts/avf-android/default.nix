{ inputs, self, ... }:
{
  flake.nixosConfigurations.avf = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.base
      inputs.avf.nixosModules.avf
      self.nixosModules.wsl-stateVersion
    ];
  };
}

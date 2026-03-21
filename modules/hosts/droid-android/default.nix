{ inputs, self, ... }:
{
  flake.nixosConfigurations.droid = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      self.nixosModules.base
      inputs.avf.nixosModules.avf
      self.nixosModules.droid-stateVersion
    ];
  };
}

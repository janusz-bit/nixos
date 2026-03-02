{ inputs, self, ... }:
{
  flake.nixosConfigurations.wsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.wsl-stateVersion-home
      self.nixosModules.wsl-stateVersion

      self.nixosModules.configuration

      inputs.nixos-wsl.nixosModules.default
      self.nixosModules.wsl-settings

      inputs.home-manager.nixosModules.default
      self.nixosModules.wsl-home

    ];
  };
}

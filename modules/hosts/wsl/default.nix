{ inputs, self, ... }:
{
  flake.nixosConfigurations.wsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.configuration

      inputs.nixos-wsl.nixosModules.default
      self.nixosModules.wsl-stateVersion
      self.nixosModules.wsl-settings

      inputs.home-manager.nixosModules.default
      self.nixosModules.wsl-home
    ];
  };

  flake.nixosModules.inputs.nixos-wsl.nixosModules.default = inputs.nixos-wsl.nixosModules.default;

}

{ inputs, self, ... }:
{
  flake.nixosModules.wsl =
    { ... }:
    {
      imports = [
        self.nixosModules.wsl-stateVersion
        self.nixosModules.wsl-obsidian

        inputs.nixos-wsl.nixosModules.default
        self.nixosModules.wsl-settings
      ];
    };
}

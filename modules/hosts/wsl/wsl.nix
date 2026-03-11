{ inputs, self, ... }:
{
  flake.nixosModules.wsl =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.wsl-stateVersion
        # self.nixosModules.wsl-obsidian

        inputs.nixos-wsl.nixosModules.default
        self.nixosModules.wsl-settings
      ];
      environment.systemPackages = with pkgs; [ zed-editor-fhs ];

    };
}

{ inputs, self, ... }:
{
  flake.nixosModules."wsl" =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules."wsl/stateVersion"
        # self.nixosModules."wsl/obsidian"

        inputs.nixos-wsl.nixosModules.default
        self.nixosModules."wsl/settings"
      ];
      environment.systemPackages = with pkgs; [ zed-editor-fhs ];
    };

  flake.nixosConfigurations.wsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules."base"
      self.nixosModules."wsl"
      (_: {
        custom.enableFastfetch = false;
        custom.flakeTarget = "wsl";
      })
    ];
  };
}

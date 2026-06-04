{
  inputs,
  self,
  config,
  ...
}:
{
  flake.modules.nixos.wsl =
    { pkgs, ... }:
    {
      imports = [
        self.modules.nixos.wsl-stateVersion
        # self.modules.nixos.wsl-obsidian

        inputs.nixos-wsl.nixosModules.default
        self.modules.nixos.wsl-settings
      ];
      environment.systemPackages = with pkgs; [ zed-editor-fhs ];
    };

  flake.nixosConfigurations.wsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.modules.nixos.base
      self.modules.nixos.wsl
      (_: {
        customBot.enableFastfetch = false;
        customBot.flakeTarget = "wsl";
      })
    ];
  };
}

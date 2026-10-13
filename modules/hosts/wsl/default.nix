{
  inputs,
  self,
  ...
}:
{
  flake.modules.nixos.wsl =
    { pkgs, ... }:
    {
      imports = [
        self.modules.nixos.wsl-stateVersion
        inputs.nixos-wsl.nixosModules.default
        self.modules.nixos.wsl-settings
      ];
      environment.systemPackages = with pkgs; [
        zed-editor-fhs
        opencode
      ];
    };

  hosts.wsl = {
    system = "x86_64-linux";
    modules = [
      self.modules.nixos.base
      self.modules.nixos.wsl
      { customBot.enableFastfetch = false; }
    ];
  };
}

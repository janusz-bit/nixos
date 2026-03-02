{ ... }:
{
  flake.nixosModules.wsl-obsidian =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        (obsidian.override {
          commandLineArgs = "--ozone-platform=x11";
        })
      ];
    };
}

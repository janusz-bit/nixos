{ ... }:
{
  flake.nixosModules.wsl-settings =
    { ... }:
    {
      wsl.enable = true;
      wsl.defaultUser = "nixos";
      wsl.docker-desktop.enable = true;
      wsl.useWindowsDriver = true;
      wsl.startMenuLaunchers = true;
      wsl.wslConf.gpu.enabled = true;
    };
}

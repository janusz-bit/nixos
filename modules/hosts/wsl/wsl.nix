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

      environment.sessionVariables.ZED_ALLOW_EMULATED_GPU = "1";
    };
}

{ ... }:
{
  flake.nixosModules.wsl-settings =
    { ... }:
    {
      wsl.enable = true;
      wsl.defaultUser = "nixos";
      wsl.useWindowsDriver = true;
      wsl.startMenuLaunchers = true;

      environment.sessionVariables.ZED_ALLOW_EMULATED_GPU = "1";
    };
}

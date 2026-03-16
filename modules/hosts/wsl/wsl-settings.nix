_:
{
  flake.nixosModules.wsl-settings =
    _:
    {
      wsl.enable = true;
      wsl.defaultUser = "nixos";
      wsl.useWindowsDriver = true;
      wsl.startMenuLaunchers = true;

      environment.sessionVariables.ZED_ALLOW_EMULATED_GPU = "1";
    };
}

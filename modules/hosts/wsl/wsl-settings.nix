_: {
  flake.modules.nixos.wsl-settings = _: {
    wsl = {
      enable = true;
      defaultUser = "nixos";
      useWindowsDriver = true;
      startMenuLaunchers = true;
    };

    environment.sessionVariables.ZED_ALLOW_EMULATED_GPU = "1";
  };
}

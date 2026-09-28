_: {
  flake.modules.nixos.wsl-settings =
    { config, ... }:
    {
      wsl = {
        enable = true;
        inherit (config.customBot) defaultUser;
        useWindowsDriver = true;
        startMenuLaunchers = true;
      };

      # resolv.conf generuje WSL (wsl.wslConf.network.generateResolvConf) —
      # serwery DNS z base i tak byłyby ignorowane (ostrzeżenie ewaluacji).
      networking.nameservers = [ ];

      environment.sessionVariables.ZED_ALLOW_EMULATED_GPU = "1";
    };
}

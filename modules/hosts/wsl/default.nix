# Host wsl: NixOS-WSL na Windowsie (sterownik GPU z Windowsa, skróty
# aplikacji w menu Start). resolv.conf generuje WSL, więc serwery DNS z base
# są tu czyszczone. WSL nie jest odbiorcą agenix: sekrety użytkownika z
# base-secrets są zadeklarowane, ale się tu nie odszyfrowują.
{ inputs, self, ... }:
{
  hosts.wsl = {
    system = "x86_64-linux";
    modules = [
      self.modules.nixos.base
      self.modules.nixos.wsl
      { customBot.enableFastfetch = false; }
    ];
  };

  flake.modules.nixos.wsl =
    { config, pkgs, ... }:
    {
      imports = [ inputs.nixos-wsl.nixosModules.default ];

      system.stateVersion = "25.05";

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
      environment.systemPackages = with pkgs; [
        zed-editor-fhs
        opencode
      ];
    };
}

# Host wsl: NixOS-WSL na Windowsie (sterownik GPU z Windowsa, skróty
# aplikacji w menu Start). WSL nie jest odbiorcą agenix, więc nie importuje
# base-agenix (sekrety użytkownika, wrappery fish, alias push).
{ inputs, self, ... }:
{
  hosts.wsl = {
    system = "x86_64-linux";
    modules = [
      self.modules.nixos.base
      self.modules.nixos.wsl
    ];
  };

  flake.modules.nixos.wsl =
    { config, pkgs, ... }:
    {
      imports = [ inputs.nixos-wsl.nixosModules.default ];

      system.stateVersion = "25.05";
      customBot.enableFastfetch = false;

      wsl = {
        enable = true;
        inherit (config.customBot) defaultUser;
        useWindowsDriver = true;
        startMenuLaunchers = true;
      };

      # resolv.conf generuje WSL (wsl.wslConf.network.generateResolvConf), więc
      # serwery DNS z base byłyby ignorowane (z ostrzeżeniem ewaluacji).
      networking.nameservers = [ ];

      environment.sessionVariables.ZED_ALLOW_EMULATED_GPU = "1";
      environment.systemPackages = with pkgs; [
        zed-editor-fhs
        opencode
      ];
    };
}

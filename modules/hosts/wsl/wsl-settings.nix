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

      # NixOS-WSL wyłącza firewall.service, a żadne konto nie ma tu kluczy
      # SSH — sshd byłby tylko powierzchnią ataku (z Windows albo, w trybie
      # mirrored, z LAN-u).
      services.openssh.enable = false;

      # NixOS-WSL domyślnie daje wheel sudo bez hasła, a jako ten użytkownik
      # działają agenci AI (opencode, prime-agent, dsh) — inwariant AGENTS.md
      # „brak NOPASSWD sudo dla agentów”. Przed pierwszym switchem ustaw hasło:
      # z Windows `wsl -d NixOS -u root passwd nixos` (to też ścieżka ratunkowa).
      security.sudo.wheelNeedsPassword = true;

      environment.sessionVariables.ZED_ALLOW_EMULATED_GPU = "1";
    };
}

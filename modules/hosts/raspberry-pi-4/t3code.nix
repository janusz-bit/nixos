# T3 Code (pingdotgg/t3code, pakiet z nixpkgs): webowy interfejs do agentów
# kodujących (Claude Code, Codex, OpenCode), dostępny wyłącznie z tailnetu:
# https://t3.<domena> -> nginx na adresie tailnetu RPi (tailnet.nix) -> t3
# na 127.0.0.1:3773.
#
# Serwer to agent z powłoką, więc działa jako osobny użytkownik t3code: bez
# sudo, bez grup, bez sekretów i bez dostępu do /var/lib innych usług, z
# zapisem tylko do własnego StateDirectory. Uwierzytelnia parowanie: każde
# urządzenie dostaje jednorazowy link (`t3 pair`), domyślny zakres to pełny
# dostęp do terminala agenta, więc link traktuj jak hasło.
#
# Jednorazowo: logowanie Claude Code na koncie usługi
#   sudo -u t3code -H claude auth login
# Parowanie urządzenia (link ważny 5 minut):
#   sudo -u t3code -H env T3CODE_HOME=/var/lib/t3code t3 pair
#   (t3 jest w systemPackages)
#
# Pamięć: serwer Node plus agent to kilkaset MB przy 4 GB RAM RPi, razem
# z Nextcloudem i Hermesem; w razie presji pamięci zatrzymaj `t3code`.
#
# Sprawdzenie: `systemctl status t3code`, `journalctl -u t3code -b`,
# `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3773/` (200).
_: {
  flake.modules.nixos.rpi-t3code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      port = 3773;
      home = "/var/lib/t3code";
    in
    {
      customBot.lockdownServices = [ "t3code" ];

      environment.systemPackages = [ pkgs.t3code ];

      users = {
        users.t3code = {
          isSystemUser = true;
          group = "t3code";
          inherit home;
          shell = pkgs.bashInteractive;
        };
        groups.t3code = { };
      };

      systemd.services.t3code = {
        description = "T3 Code";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        # Dostawcy agentów t3 szuka w PATH.
        path = with pkgs; [
          claude-code
          git
          bashInteractive
        ];
        environment = {
          HOME = home;
          T3CODE_HOME = home;
        };
        serviceConfig = {
          ExecStart = "${lib.getExe' pkgs.t3code "t3"} serve --mode web --host 127.0.0.1 --port ${toString port} --no-browser";
          User = "t3code";
          Group = "t3code";
          StateDirectory = "t3code";
          StateDirectoryMode = "0700";
          WorkingDirectory = home;
          Restart = "on-failure";
          RestartSec = "5s";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
        };
      };

      services.nginx.virtualHosts."t3.${config.customTop.domain}" = {
        listenAddresses = [ config.customBot.tailnetAddress ];
        forceSSL = true;
        enableACME = true;
        # Certyfikat przez DNS-01 (tailnet.nix), nie przez webroot.
        acmeRoot = null;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
          # Domyślne 60 s zrywałoby bezczynny WebSocket sesji agenta.
          extraConfig = "proxy_read_timeout 1h;";
        };
      };
    };
}

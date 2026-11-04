# T3 Code (pingdotgg/t3code, pakiet z flake llm-agents): webowy interfejs do agentów
# kodujących (Claude Code, Codex, OpenCode), dostępny wyłącznie z tailnetu
# Tailscale (tailnet.nix): https://raspberry-pi-4.<tailnet>.ts.net ->
# `tailscale serve` -> t3 na 127.0.0.1:3773. Nie ma go w Cloudflare Tunnel.
#
# `tailscale serve` kończy TLS w tailscaled certyfikatem *.ts.net od
# Tailscale i przekazuje ruch, także WebSockety, bez nginx i ACME. Jego
# konfiguracja żyje w stanie tailscaled; unit t3code-tailscale-serve nakłada
# ją przy starcie i czyści przy zatrzymaniu, więc nie zostaje po usunięciu
# modułu.
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
# Sprawdzenie: `systemctl status t3code t3code-tailscale-serve`,
# `tailscale serve status`,
# `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3773/` (200),
# z laptopa w tailnecie `curl -I https://raspberry-pi-4.<tailnet>.ts.net`.
{ inputs, ... }:
{
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
      t3code = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
    in
    {
      customBot.lockdownServices = [ "t3code" ];

      environment.systemPackages = [ t3code ];

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
          ExecStart = "${lib.getExe' t3code "t3"} serve --mode web --host 127.0.0.1 --port ${toString port} --no-browser";
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

      systemd.services.t3code-tailscale-serve =
        let
          tailscale = lib.getExe config.services.tailscale.package;
        in
        {
          description = "T3 Code w tailnecie (tailscale serve)";
          wantedBy = [ "multi-user.target" ];
          after = [ "tailscaled.service" ];
          wants = [ "tailscaled.service" ];
          # `serve` zawodzi, dopóki węzeł nie jest zalogowany (jednorazowe
          # `tailscale up`, tailnet.nix) i po starcie, zanim tailscaled
          # połączy się z tailnetem: ponawia bez limitu startów.
          startLimitIntervalSec = 0;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${tailscale} serve --bg --yes --https=443 http://127.0.0.1:${toString port}";
            # "-": przy wyłączaniu po `lockdown on` tailscaled już nie działa.
            ExecStop = "-${tailscale} serve reset";
            Restart = "on-failure";
            RestartSec = "30s";
            # Gdy w tailnecie brakuje HTTPS Certificates, `serve` wypisuje adres
            # do ich włączenia i może na nie czekać; oneshot bez limitu
            # zablokowałby przełączenie systemu.
            TimeoutStartSec = "1min";
          };
        };
    };
}

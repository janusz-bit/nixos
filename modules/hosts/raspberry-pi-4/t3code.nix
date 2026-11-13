# T3 Code (interfejs WWW agentów Claude Code i Codex) na RPi, dostępny
# z przeglądarki wyłącznie w tailnecie: Tailscale Serve wystawia
# https://<RPi>.<tailnet>.ts.net (certyfikat Tailscale) i przekazuje ruch do
# `t3 serve` na 127.0.0.1:3773, które działa na koncie systemowym t3code bez
# grup, sudo i sekretów. Sam Tailscale (logowanie, ustawienia, firewall,
# jednostka tailscale-serve) jest w hosts/tailscale.nix (rpi-tailscale).
#
# Granica zaufania: sesja T3 to powłoka, pliki i agenci na koncie t3code.
# - Z tailnetu dociera tylko HTTPS Serve (netfilter nodivert, rpi-tailscale).
# - Konta lokalne (pozostałe usługi, konto główne) nie docierają do T3: do
#   127.0.0.1:3773 łączy się tylko root (proxy tailscaled) i t3code (reguła
#   iptables owner z customBot.tailscaleServe.users), a połączenia na własne
#   adresy tailnetu (lokalny listener Serve) są odrzucane (hosts/tailscale.nix). Bez operatora tailscaled dla t3code: operator mógłby
#   włączyć Funnel, czyli wystawić T3 do internetu.
# - Uwierzytelnia sam T3 (parowanie, sesje). `t3 serve` wypisuje przy starcie
#   token parowania właściciela (5 min); LogFilterPatterns nie wpuszcza go do
#   journala, który czytają też inne konta (grupy wheel i systemd-journal).
#   Telemetria wyłączona.
#
# Jednorazowo: zalogować RPi do Tailscale i włączyć Serve (nagłówek
# hosts/tailscale.nix), logowanie agenta:
# `sudo -u t3code -H claude auth login`. Parowanie urządzenia: `t3code pair`
# (link https w tailnecie + QR, ważny 5 min); pozostałe polecenia `t3`
# na koncie usługi: `t3code <polecenie>`, np. `t3code auth session list`.
#
# Sprawdzenie: `systemctl status t3code tailscale-serve`,
# `tailscale serve status`, `curl -sI http://127.0.0.1:3773` jako nixos (odrzucone), z urządzenia
# w tailnecie https://<RPi>.<tailnet>.ts.net.
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
      user = "t3code";
      home = "/var/lib/${user}";
      port = 3773;

      t3code = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code.override {
        # Te same CLI agentów co tools.nix zamiast kopii z llm-agents.
        providerPackages = with pkgs; [
          claude-code
          codex
        ];
      };

      t3codeCli = pkgs.writeShellApplication {
        name = "t3code";
        runtimeInputs = with pkgs; [
          config.services.tailscale.package
          jq
          qrencode
        ];
        text = ''
          # Katalog bieżący (np. /home/nixos) jest dla t3code niedostępny.
          cd /
          as_t3code() {
            /run/wrappers/bin/sudo -u ${user} -H -- ${lib.getExe t3code} "$@"
          }

          if [ "''${1:-}" != pair ]; then
            as_t3code "$@"
            exit
          fi
          shift

          # `t3 pair` podaje adres 127.0.0.1; z tailnetu T3 jest pod nazwą
          # MagicDNS RPi (Tailscale Serve, port 443).
          host=$(tailscale status --json | jq -r '.Self.DNSName // "" | rtrimstr(".")')
          if [ -z "$host" ]; then
            echo "t3code: Tailscale niezalogowany (nagłówek modułu t3code.nix)" >&2
            exit 1
          fi
          out=$(as_t3code pair "$@")
          token=$(sed -n 's/^Token: //p' <<<"$out")
          if [ -z "$token" ]; then
            echo "t3code: brak tokenu w wyjściu \`t3 pair\`" >&2
            exit 1
          fi
          url="https://$host/pair#token=$token"
          sed -n 's/^Expires: /Ważny do: /p' <<<"$out"
          printf '%s\n' "$url"
          qrencode -t ansiutf8 "$url"
        '';
      };
    in
    {
      users = {
        users.${user} = {
          isSystemUser = true;
          group = user;
          inherit home;
          # Powłoka terminala T3 (node-pty bierze ją z passwd); bez hasła
          # i kluczy SSH, więc nie daje logowania.
          shell = pkgs.bashInteractive;
        };
        groups.${user} = { };
      };

      environment.systemPackages = [ t3codeCli ];

      systemd.services = {
        t3code = {
          description = "T3 Code (127.0.0.1:${toString port})";
          wantedBy = [ "multi-user.target" ];
          path = [
            pkgs.git
            config.nix.package
          ];
          environment.T3CODE_TELEMETRY_ENABLED = "false";
          serviceConfig = {
            User = user;
            Group = user;
            ExecStart = lib.escapeShellArgs [
              (lib.getExe t3code)
              "serve"
              "--mode"
              "web"
              "--host"
              "127.0.0.1"
              "--port"
              (toString port)
              "--no-browser"
            ];
            WorkingDirectory = home;
            StateDirectory = user;
            StateDirectoryMode = "0700";
            Restart = "on-failure";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            # Blok startowy `t3 serve` (token, URL i link z tokenem, kod QR)
            # idzie na stdout razem z logami; journald odrzuca te linie.
            LogFilterPatterns = [
              "~^(Token|Pairing URL|App link):"
              "~^ *[▀▄█][ ▀▄█]*$"
            ];
          };
        };
      };

      customBot = {
        # https://<RPi>.<tailnet> (domyślny port HTTPS): pod tym adresem
        # są już sparowane urządzenia.
        tailscaleServe."443" = {
          inherit port;
          users = [ user ];
        };
        # Agenci łączą się z internetem sami (API modeli).
        lockdownServices = [ user ];
      };
    };
}

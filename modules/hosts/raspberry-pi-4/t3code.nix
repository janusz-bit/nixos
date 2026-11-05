# T3 Code (interfejs WWW agentów Claude Code i Codex) na RPi, dostępny
# z przeglądarki wyłącznie w tailnecie: Tailscale Serve wystawia
# https://<RPi>.<tailnet>.ts.net (certyfikat Tailscale) i przekazuje ruch do
# `t3 serve` na 127.0.0.1:3773, które działa na koncie systemowym t3code bez
# grup, sudo i sekretów. Tailscale (hostowany serwer koordynacji) łączy się
# wychodząco, więc działa za CGNAT, gdzie headscale za tunelem Cloudflare nie
# może (AGENTS.md).
#
# Granica zaufania: sesja T3 to powłoka, pliki i agenci na koncie t3code.
# - Tailnet dociera tylko do HTTPS Serve: --netfilter-mode=nodivert, bo
#   domyślne `on` wstawia na początek INPUT `-i tailscale0 -j ACCEPT`, z którym
#   tailnet omijałby nixos-fw (także SSH tylko z LAN-u). Porty Serve obsługuje
#   netstack w procesie tailscaled, więc nixos-fw ich nie blokuje.
#   --accept-dns=false: MagicDNS przejąłby DNS całego hosta, a lockdown, który
#   zatrzymuje tailscaled, odciąłby wtedy DNS cloudflared.
# - Konta lokalne (hermes i usługi z internetu) nie docierają do T3: do
#   127.0.0.1:3773 łączy się tylko root (proxy tailscaled) i t3code (reguła
#   iptables owner), a połączenia na własne adresy tailnetu (lokalny listener
#   Serve) są odrzucane. Bez operatora tailscaled dla t3code: operator mógłby
#   włączyć Funnel, czyli wystawić T3 do internetu.
# - Uwierzytelnia sam T3 (parowanie, sesje). `t3 serve` wypisuje przy starcie
#   token parowania właściciela (5 min); LogFilterPatterns nie wpuszcza go do
#   journala, który czyta też hermes (systemd-journal). Telemetria wyłączona.
#
# Jednorazowo na RPi: `sudo tailscale up --accept-dns=false --netfilter-mode=nodivert`
# (pierwsze logowanie nadpisuje ustawienia domyślnymi, jednostka t3code-tailnet
# i tak przywraca je zaraz po nim), w panelu Tailscale wyłączyć wygasanie klucza
# RPi i włączyć MagicDNS + HTTPS Certificates; logowanie agenta:
# `sudo -u t3code -H claude auth login`. Parowanie urządzenia: `t3code pair`
# (link https w tailnecie + QR, ważny 5 min); pozostałe polecenia `t3`
# na koncie usługi: `t3code <polecenie>`, np. `t3code auth session list`.
# Po usunięciu modułu konfiguracja Serve zostaje w stanie tailscaled:
# `sudo tailscale serve reset`.
#
# Sprawdzenie: `systemctl status t3code t3code-tailnet tailscaled`,
# `tailscale serve status`, `sudo iptables -S nixos-fw | head -3` (bez ts-input),
# `curl -sI http://127.0.0.1:3773` jako nixos (odrzucone), z urządzenia
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
      tailscale = lib.getExe config.services.tailscale.package;

      t3code = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code.override {
        # Te same CLI agentów co Hermes i tools.nix zamiast kopii z llm-agents.
        providerPackages = with pkgs; [
          claude-code
          codex
        ];
      };

      tailscaleSetFlags = [
        "--accept-dns=false"
        "--netfilter-mode=nodivert"
      ];

      # Firewall przy reloadzie czyści tylko własne łańcuchy, nie OUTPUT, więc
      # przed dodaniem reguła jest usuwana, żeby się nie mnożyła.
      outputRules = [
        {
          cmd = "iptables";
          rule = "OUTPUT -o lo -p tcp -d 127.0.0.1 --dport ${toString port} -m owner ! --uid-owner root -m owner ! --uid-owner ${user} -j REJECT";
        }
        # Własne adresy tailnetu (100.64.0.0/10, fd7a:115c:a1e0::/48) idą przez lo.
        {
          cmd = "iptables";
          rule = "OUTPUT -o lo -d 100.64.0.0/10 -j REJECT";
        }
        {
          cmd = "ip6tables";
          rule = "OUTPUT -o lo -d fd7a:115c:a1e0::/48 -j REJECT";
        }
      ];
      deleteRule = { cmd, rule }: "${cmd} -D ${rule} 2>/dev/null || true";
      appendRule = { cmd, rule }: "${cmd} -A ${rule}";

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
      services.tailscale.enable = true;

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

        # Po zalogowaniu (tailscale wait czeka na Running) wymusza ustawienia
        # z nagłówka i Serve: https://<RPi>.<tailnet>.ts.net -> T3. BindsTo
        # z After: przy lockdown (tailscaled pominięty) też się nie uruchamia.
        t3code-tailnet = {
          description = "Tailscale: ustawienia i Serve dla T3 Code";
          wantedBy = [ "tailscaled.service" ];
          bindsTo = [ "tailscaled.service" ];
          after = [ "tailscaled.service" ];
          script = ''
            ${tailscale} wait
            ${tailscale} set ${lib.escapeShellArgs tailscaleSetFlags}
            ${tailscale} serve --bg --yes --https=443 http://127.0.0.1:${toString port}
          '';
          # Serve czeka na HTTPS Certificates w panelu Tailscale albo kończy
          # się błędem; ponowienie zastosuje je po włączeniu.
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = "1min";
          };
        };
      };

      networking.firewall = {
        extraCommands = lib.concatMapStringsSep "\n" (rule: ''
          ${deleteRule rule}
          ${appendRule rule}
        '') outputRules;
        extraStopCommands = lib.concatMapStringsSep "\n" deleteRule outputRules;
      };

      # Obie łączą się z internetem same (koordynacja Tailscale, API modeli).
      customBot.lockdownServices = [
        "tailscaled"
        user
      ];
    };
}

# Agenci AI Brulionu dla telefonu (services.brulion-acp z flake'a Brulionu,
# `brulion-cli acp serve`, docs/NIXOS.md „AI agents for the phone”): telefon
# nie uruchamia programów, więc Claude Code działa tutaj, w kopii notatnika
# synchronizowanej z Nextcloudem tego RPi, a Brulion na telefonie rozmawia
# z nim wyłącznie przez tailnet: Tailscale Serve wystawia
# https://<RPi>.<tailnet>:8790 i przekazuje ruch do `brulion-cli acp serve`
# na 127.0.0.1:8790 (długie odpytywanie, odpowiedzi czekają na telefon).
#
# Agent to program z powłoką: działa jako osobne konto brulion-acp (bez sudo,
# grup i sekretów poza hasłem aplikacji Nextclouda, bez dostępu do /var/lib
# innych usług), a sparowany telefon nim steruje. Parowanie bez kodu
# (`--tailscale-serve`, docs/CLI.md „In a tailnet”): serwer pyta tailscaled
# (whois), czyje urządzenie Serve przekazało, i paruje tylko urządzenia
# użytkownika, na którego zalogowany jest RPi; reszta tailnetu potrzebuje kodu
# z `brulion-acp pair`. Nagłówek Tailscale-User-Login bierze tylko wtedy, gdy
# whois nikogo nie zna, a lokalnie do portu łączy się tylko root (proxy
# tailscaled, customBot.tailscaleServe.users), więc żadne konto RPi go nie
# podrobi. Agent pochodzi z nixpkgs (claude-agent-acp), nie z `npx`.
#
# Nextcloud: przez nginx na localhost (połączenia na własne adresy tailnetu są
# odrzucane, hosts/tailscale.nix), stąd zaufana domena `localhost`. Konto
# customTop.users.nextcloud, hasło aplikacji z brulion-acp-nextcloud.age
# (root 0400, usługa dostaje je przez LoadCredential). Nowe hasło: w Nextcloudzie
# Ustawienia → Bezpieczeństwo → Urządzenia i sesje, potem na laptopie
# `cd modules/_secrets && agenix -e brulion-acp-nextcloud.age` (samo hasło).
#
# Jednorazowo:
#   1. `sudo brulion-acp login claude`: w Claude Code /login (subskrypcja).
#   2. W Brulionie na telefonie (Tailscale włączony): Ustawienia →
#      Rozszerzenia → Agenci AI → Dodaj → Agent na innym komputerze, adres
#      https://<RPi>.<tailnet>:8790, kod pusty, „Sparuj”. Urządzenie spoza
#      konta RPi: kod lub QR z `sudo brulion-acp pair` (10 minut).
#   Później: `sudo brulion-acp clients`, `sudo brulion-acp revoke --all`.
#
# Notatnik: /var/lib/brulion-acp/notebook, jedno z urządzeń notatnika
# w folderze `Notatki` tego konta (jak w ustawieniach synchronizacji
# aplikacji). Brulion nie ma cache: pierwszy build brulion-cli na RPi
# kompiluje go lokalnie.
#
# Pamięć: brulion-cli kilkadziesiąt MB, agent (Node) kilkaset MB na rozmowę
# z telefonu — obok Nextclouda i T3 Code przy 4 GB RAM; przy presji pamięci
# `sudo systemctl stop brulion-acp`. lockdown zatrzymuje usługę.
#
# Sprawdzenie: `systemctl status brulion-acp`,
# `journalctl -u brulion-acp -b` (linie „devices of … pair without a code”
# i synchronizacji), `tailscale serve status`, z urządzenia w tailnecie
# `curl -s https://<RPi>.<tailnet>:8790/` (tekst „Brulion: AI agents …”).
{ inputs, ... }:
{
  flake.modules.nixos.rpi-brulion-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      host = "${config.networking.hostName}.${config.customTop.tailnet.domain}";
      port = 8790;
    in
    {
      imports = [ inputs.brulion.nixosModules.default ];

      age.secrets.brulion-acp-nextcloud = {
        file = config.customTop.secretsDir + "/brulion-acp-nextcloud.age";
        # Czyta go systemd (LoadCredential) jako root.
        owner = "root";
        mode = "0400";
      };

      services = {
        brulion-acp = {
          enable = true;
          inherit port;
          agents.claude = {
            name = "Claude Code";
            command = lib.getExe pkgs.claude-agent-acp;
          };
          # claude: do `sudo brulion-acp login claude`; reszta: polecenia agenta.
          path = with pkgs; [
            bashInteractive
            coreutils
            findutils
            gnugrep
            gnused
            git
            ripgrep
            claude-code
          ];
          publicUrl = "https://${host}:${toString port}";
          # Moduł nie ma opcji dla tego trybu (aplikacja na laptopie
          # uruchamia go tak samo przy własnym Serve).
          extraArgs = [ "--tailscale-serve" ];
          nextcloud = {
            url = "http://localhost";
            user = config.customTop.users.nextcloud;
            folder = "Notatki";
            passwordFile = config.age.secrets.brulion-acp-nextcloud.path;
            deviceName = config.networking.hostName;
          };
        };

        nextcloud.settings.trusted_domains = [ "localhost" ];
      };

      customBot = {
        tailscaleServe.${toString port} = {
          inherit port;
          users = [ ];
        };
        # Agent łączy się z internetem sam (API modelu).
        lockdownServices = [ "brulion-acp" ];
      };
    };
}

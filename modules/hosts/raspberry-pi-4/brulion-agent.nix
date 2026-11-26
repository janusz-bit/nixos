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
# odrzucane, hosts/tailscale.nix), stąd zaufana domena `localhost`. Hasło
# aplikacji tworzy raz jednostka brulion-acp-nextcloud-password
# (`occ user:auth-tokens:add`, w Nextcloudzie urządzenie „brulion-acp”),
# bo Nextcloud jest na tym samym hoście: plik root 0400 w katalogu root 0700,
# usługa dostaje go przez LoadCredential. Po usunięciu urządzenia
# w Nextcloudzie: `sudo rm /var/lib/brulion-acp-nextcloud/app-password`,
# `sudo systemctl restart brulion-acp` (tworzy nowe).
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
# w Nextcloudzie (konto customBot.defaultUser, folder `Brulion` jak
# w ustawieniach synchronizacji aplikacji). Brulion nie ma cache: pierwszy
# build brulion-cli na RPi kompiluje go lokalnie.
#
# Pamięć: brulion-cli kilkadziesiąt MB, agent (Node) kilkaset MB na rozmowę
# z telefonu — obok Nextclouda i T3 Code przy 4 GB RAM; przy presji pamięci
# `sudo systemctl stop brulion-acp`. lockdown zatrzymuje usługę.
#
# Sprawdzenie: `systemctl status brulion-acp brulion-acp-nextcloud-password`,
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
      nextcloudUser = config.customBot.defaultUser;
      passwordStateDirectory = "brulion-acp-nextcloud";
      passwordDir = "/var/lib/${passwordStateDirectory}";
      passwordFile = "${passwordDir}/app-password";

      # occ jako nextcloud (runuser ustawia USER, więc nextcloud-occ nie woła
      # sudo), wynik tylko w katalogu roota (mktemp: 0600); przy błędzie occ
      # wypisuje sam komunikat, bez hasła.
      createAppPassword = pkgs.writeShellApplication {
        name = "brulion-acp-nextcloud-password";
        runtimeInputs = [
          config.services.nextcloud.occ
          pkgs.coreutils
          pkgs.gnused
          pkgs.util-linux
        ];
        text = ''
          target=${lib.escapeShellArg passwordFile}
          if [[ -s $target ]]; then
            exit 0
          fi
          output="$(mktemp ${lib.escapeShellArg passwordDir}/.occ.XXXXXX)"
          trap 'rm -f "$output"' EXIT
          if ! runuser -u nextcloud -- nextcloud-occ --no-interaction --no-ansi \
            user:auth-tokens:add --name brulion-acp ${lib.escapeShellArg nextcloudUser} >"$output"; then
            cat "$output" >&2
            exit 1
          fi
          created="$(mktemp ${lib.escapeShellArg passwordDir}/.app-password.XXXXXX)"
          sed -n '/^app password:$/{n;p;q}' "$output" >"$created"
          if [[ ! -s $created ]]; then
            rm -f "$created"
            echo "occ user:auth-tokens:add nie wypisał hasła" >&2
            exit 1
          fi
          chmod 0400 "$created"
          mv "$created" "$target"
        '';
      };
    in
    {
      imports = [ inputs.brulion.nixosModules.default ];

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
            user = nextcloudUser;
            folder = "Brulion";
            inherit passwordFile;
            deviceName = config.networking.hostName;
          };
        };

        nextcloud.settings.trusted_domains = [ "localhost" ];
      };

      systemd.services.brulion-acp-nextcloud-password = {
        description = "Hasło aplikacji Nextclouda dla brulion-acp";
        requiredBy = [ "brulion-acp.service" ];
        before = [ "brulion-acp.service" ];
        after = [ "nextcloud-setup.service" ];
        # Root (plik czyta LoadCredential), ale /usr, /boot i /etc tylko do
        # odczytu; occ pisze do /var/lib/nextcloud, więc bez ProtectSystem=strict.
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe createAppPassword;
          StateDirectory = passwordStateDirectory;
          StateDirectoryMode = "0700";
          ProtectSystem = "full";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
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

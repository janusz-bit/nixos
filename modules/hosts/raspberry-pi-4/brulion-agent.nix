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
# innych usług), a sparowany telefon nim steruje — kod parowania traktuj jak
# hasło. Lokalnie do portu łączy się tylko root (proxy tailscaled,
# customBot.tailscaleServe.users), a serwer i tak wymaga tokenu urządzenia.
# Agent pochodzi z nixpkgs (claude-agent-acp), nie z `npx`.
#
# Nextcloud: przez nginx na localhost (połączenia na własne adresy tailnetu są
# odrzucane, hosts/tailscale.nix), stąd zaufana domena `localhost`.
#
# Jednorazowo:
#   1. W Nextcloudzie hasło aplikacji (Ustawienia → Bezpieczeństwo → Urządzenia
#      i sesje → „brulion-acp”), na laptopie:
#        cd modules/_secrets && agenix -e brulion-acp-nextcloud.age   # samo hasło
#      (git add, commit) — bez niego usługa się nie włącza (ostrzeżenie).
#   2. `sudo brulion-acp login claude`: w Claude Code /login (subskrypcja).
#   3. `sudo brulion-acp pair`: kod QR dla aparatu telefonu i kod (10 minut);
#      Brulion otwiera parowanie wypełnione, „Sparuj”. Ręcznie: Ustawienia →
#      Rozszerzenia → Agenci AI → Dodaj → Agent na innym komputerze, adres
#      https://<RPi>.<tailnet>:8790 i kod.
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
# Sprawdzenie: `systemctl status brulion-acp`, `journalctl -u brulion-acp -b`,
# `tailscale serve status`, z urządzenia w tailnecie
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
      inherit (config.customTop) secretsDir;
      host = "${config.networking.hostName}.${config.customTop.tailnet.domain}";
      port = 8790;
      secretFile = secretsDir + "/brulion-acp-nextcloud.age";
      hasSecret = builtins.pathExists secretFile;
    in
    {
      imports = [ inputs.brulion.nixosModules.default ];

      warnings =
        lib.optional (!hasSecret)
          "rpi-brulion-agent: brak modules/_secrets/brulion-acp-nextcloud.age w gicie — agenci Brulionu są wyłączeni (kroki w nagłówku brulion-agent.nix).";

      age.secrets.brulion-acp-nextcloud = lib.mkIf hasSecret {
        file = secretFile;
        # Czyta go systemd (LoadCredential) jako root.
        owner = "root";
        mode = "0400";
      };

      services = {
        brulion-acp = lib.mkIf hasSecret {
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
          nextcloud = {
            url = "http://localhost";
            user = config.customBot.defaultUser;
            folder = "Brulion";
            passwordFile = config.age.secrets.brulion-acp-nextcloud.path;
            deviceName = config.networking.hostName;
          };
        };

        nextcloud.settings.trusted_domains = lib.mkIf hasSecret [ "localhost" ];
      };

      customBot = lib.mkIf hasSecret {
        tailscaleServe.${toString port} = {
          inherit port;
          users = [ ];
        };
        # Agent łączy się z internetem sam (API modelu).
        lockdownServices = [ "brulion-acp" ];
      };
    };
}

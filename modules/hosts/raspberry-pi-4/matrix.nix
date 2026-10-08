{ customTop, ... }:
{
  flake.modules.nixos.matrix =
    { config, lib, ... }:
    let
      domain = customTop.site.full;
      # Adres serwera dla klientów (Element) — przez Cloudflare Tunnel
      # (cloudflared.nix). ID kont: @nazwa:${domain} (server_name).
      clientUrl = "https://matrix.${domain}";
      continuwuity = config.services.matrix-continuwuity.settings.global;

      # Jedyne konto, które może rozmawiać z Hermesem. Zakładasz je jako
      # pierwsze (dostaje admina serwera) — przy innej nazwie zmień tutaj.
      owner = "@janusz:${domain}";

      # Token dostępu konta bota @hermes:${domain}, plik env:
      #   MATRIX_ACCESS_TOKEN=…
      #   MATRIX_RECOVERY_KEY=…   (opcjonalnie, patrz niżej)
      # Dopóki pliku nie ma w gicie, serwer działa, a Hermes się nie łączy.
      secretFile = customTop.secretsDir + "/hermes-matrix.age";
      hasSecret = builtins.pathExists secretFile;

      hermesEnv = {
        # Bezpośrednio, z pominięciem tunelu.
        MATRIX_HOMESERVER = "http://127.0.0.1:${toString (builtins.head continuwuity.port)}";
        MATRIX_ALLOWED_USERS = owner;
        # Cel powiadomień (cron `deliver: "matrix"`, `hermes send matrix …`):
        # DM z ${owner}. Nie przez /sethome — w trybie zarządzanym (Nix)
        # Hermes nie zapisuje config.yaml, więc wybór zginąłby po restarcie.
        MATRIX_HOME_ROOM = "!dTrQicK0YGC8YxepExnDhhmVWD9O2u3QRiTwj4YaY20";
        # TLS klientów kończy się w Cloudflare, więc treść rozmów chroni
        # dopiero E2EE. `required`: bez działającego szyfrowania adapter nie
        # startuje, zamiast po cichu przejść na tekst jawny.
        MATRIX_E2EE_MODE = "required";
        # Przy pierwszym połączeniu Hermes zakłada cross-signing konta bota
        # i zapisuje klucz odzyskiwania jednorazowo (0600, nie nadpisuje).
        # Kopię wpisz do hermes-matrix.age jako MATRIX_RECOVERY_KEY — bez niej
        # nowe urządzenie bota (nowy token) zostanie niezweryfikowane.
        MATRIX_RECOVERY_KEY_OUTPUT_FILE = "${config.services.hermes-agent.stateDir}/.hermes/platforms/matrix/recovery-key";
        # Większe pliki serwer i tak odrzuci (413).
        MATRIX_MAX_MEDIA_BYTES = toString continuwuity.max_request_size;
      };
    in
    lib.mkMerge [
      {
        warnings = lib.optionals (!hasSecret) [
          "matrix: brak modules/_secrets/hermes-matrix.age w gicie — Hermes nie połączy się z Matrixem."
        ];

        services.matrix-continuwuity = {
          enable = true;
          settings.global = {
            server_name = domain;
            # Prywatny kanał do Hermesa, nie serwer publiczny: bez federacji
            # (pushe na telefon idą osobnym klientem do bramki push z
            # rejestracji klienta, więc działają) i bez otwartej rejestracji.
            # Pierwsze konto zakłada się jednorazowym tokenem, który serwer
            # wypisuje przy pierwszym starcie (journalctl -u continuwuity);
            # kolejne tworzy admin w pokoju #admins: !admin users create-user …
            allow_federation = false;
            trusted_servers = [ ];
            well_known.client = clientUrl;
          };
        };

        # server_name to domena główna, którą serwuje Nextcloud — delegacja
        # klientów (wpisujących samo ${domain}) na matrix.${domain}. Dokładne
        # `=` ma pierwszeństwo przed `^~ /.well-known` z modułu nextcloud.
        # Odpowiedź (z well_known.client) i nagłówek CORS daje continuwuity —
        # własny add_header w lokacji skasowałby nagłówki bezpieczeństwa
        # vhosta (gixy: add_header_redefinition).
        services.nginx.virtualHosts.${domain}.locations."= /.well-known/matrix/client".proxyPass =
          "http://127.0.0.1:${toString (builtins.head continuwuity.port)}";
      }

      (lib.mkIf hasSecret {
        # Aktywacja Hermesa dokleja plik do $HERMES_HOME/.env procesem z uid
        # usługi (jak hermes-env w hermes.nix).
        age.secrets.hermes-matrix = {
          file = secretFile;
          owner = "hermes";
          mode = "0400";
        };

        services.hermes-agent = {
          environment = hermesEnv;
          environmentFiles = [ config.age.secrets.hermes-matrix.path ];
        };

        # Brama czyta .env tylko przy starcie, a moduł nie restartuje jej po
        # zmianie konfiguracji (ścieżka /run/agenix/… jest stała). Hash, nie
        # ścieżka: ta leży w źródle flake'a i zmienia się z każdym commitem.
        systemd.services.hermes-agent.restartTriggers = [
          (builtins.hashFile "sha256" secretFile)
          (builtins.toJSON hermesEnv)
        ];
      })
    ];
}

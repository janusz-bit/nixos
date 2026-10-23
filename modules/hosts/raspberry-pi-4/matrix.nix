# Prywatny serwer Matrix continuwuity jako kanał rozmów i powiadomień
# Hermesa: server_name = domena główna, klienci przez matrix.<domena> w tunelu,
# bez federacji i otwartej rejestracji; Hermes łączy się lokalnie kontem bota.
#
# Hermes odpowiada tylko kontu właściciela (MATRIX_ALLOWED_USERS): w DM
# zawsze, w pokojach z innymi osobami tylko na @wzmiankę (domyślne
# MATRIX_REQUIRE_MENTION).
#
# Matrix jest domyślnym kanałem powiadomień: cron i `hermes send` przez
# MATRIX_HOME_ROOM, powiadomienia o restarcie bramy tylko tutaj (e-mail je
# wycisza, Hermes startuje po continuwuity i zatrzymuje się przed nim).
#
# Sprawdzenie: `systemctl status continuwuity`,
# `curl -s http://127.0.0.1:6167/_matrix/client/versions`,
# `journalctl -u hermes-agent -b | grep -i matrix`.
{ customTop, ... }:
{
  flake.modules.nixos.rpi-matrix =
    { config, lib, ... }:
    let
      inherit (customTop) domain;
      continuwuity = config.services.matrix-continuwuity.settings.global;
      # Adres lokalny z pominięciem tunelu: łączy się nim Hermes, a nginx
      # proxuje na niego .well-known.
      localUrl = "http://127.0.0.1:${toString (builtins.head continuwuity.port)}";

      # Jedyne konto, które może rozmawiać z Hermesem. Zakładasz je jako
      # pierwsze — dostaje admina serwera.
      ownerId = "@${customTop.users.matrix}:${domain}";

      # Token konta bota @hermes:${domain}, plik env: MATRIX_ACCESS_TOKEN=…
      # i opcjonalnie MATRIX_RECOVERY_KEY=… (niżej). Bez pliku w gicie serwer
      # działa, a Hermes się nie łączy (ostrzeżenie).
      secretFile = customTop.secretsDir + "/hermes-matrix.age";
      hasSecret = builtins.pathExists secretFile;

      hermesEnv = {
        MATRIX_HOMESERVER = localUrl;
        MATRIX_ALLOWED_USERS = ownerId;
        # Cel powiadomień (cron `deliver: "matrix"`, `hermes send matrix …`):
        # DM z ownerId. Nie przez /sethome — w trybie zarządzanym (Nix)
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
            # Prywatny kanał do Hermesa: bez federacji (pushe na telefon idą
            # bramką push klienta, więc działają) i bez otwartej rejestracji.
            # Pierwsze konto: jednorazowy token z `journalctl -u continuwuity`
            # (pierwszy start); kolejne: `!admin users create-user …` w #admins.
            allow_federation = false;
            trusted_servers = [ ];
            # Klienci (Element) przez tunel (cloudflared.nix).
            well_known.client = "https://matrix.${domain}";
          };
        };

        # server_name to domena główna, którą serwuje Nextcloud: delegacja
        # klientów na matrix.${domain}. Dokładne `=` ma pierwszeństwo przed
        # `^~ /.well-known` z modułu nextcloud. Odpowiedź i nagłówek CORS daje
        # continuwuity — własny add_header w lokacji skasowałby nagłówki
        # bezpieczeństwa vhosta (gixy: add_header_redefinition).
        services.nginx.virtualHosts.${domain}.locations."= /.well-known/matrix/client".proxyPass = localUrl;
      }

      (lib.mkIf hasSecret {
        # Aktywacja Hermesa dokleja plik do $HERMES_HOME/.env procesem z uid
        # usługi (jak hermes-env w hermes.nix).
        age.secrets.hermes-matrix = {
          file = secretFile;
          owner = config.services.hermes-agent.user;
          mode = "0400";
        };

        services.hermes-agent = {
          environment = hermesEnv;
          environmentFiles = [ config.age.secrets.hermes-matrix.path ];
          # Powiadomienia o zatrzymaniu/restarcie bramy idą do kanałów domowych
          # wszystkich platform; e-mail (EMAIL_HOME_ADDRESS z hermes-env.age)
          # zostaje do rozmów, a powiadomienia tylko na Matrixie. Bez klucza
          # `enabled` Hermes nadal włącza e-mail z danych w .env.
          settings.platforms.email.gateway_restart_notification = false;
        };

        systemd.services.hermes-agent = {
          # systemd zatrzymuje jednostki w kolejności odwrotnej do `after`:
          # bez tego continuwuity znika razem z Hermesem przy restarcie lub
          # aktywacji i powiadomienie o zatrzymaniu nie dochodzi na Matrix
          # (Cannot connect to host 127.0.0.1:6167).
          after = [ "continuwuity.service" ];
          wants = [ "continuwuity.service" ];
          # Brama czyta .env tylko przy starcie, a moduł nie restartuje jej po
          # zmianie konfiguracji (ścieżka /run/agenix/… jest stała).
          restartTriggers = [
            (builtins.hashFile "sha256" secretFile)
            (builtins.toJSON hermesEnv)
          ];
        };
      })
    ];
}

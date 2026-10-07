{ customTop, ... }:
{
  flake.modules.nixos.nextcloud =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # nextcloud-setup czyta plik przez LoadCredential (jako PID 1), więc
      # domyślne root:root 0400. Właściciel `nextcloud` dawał hasło admina
      # w czystej postaci każdemu workerowi PHP-FPM i każdej aplikacji
      # Nextcloud (AGENTS.md: sekrety LoadCredential = root 0400).
      age.secrets.nextcloud-adminpass.file = customTop.secretsDir + "/nextcloud-adminpass.age";
      services = {
        nextcloud = {
          enable = true;
          hostName = "${customTop.site.full}";
          # Upgrade o jedną wersję główną naraz (34 → 35); nextcloud-setup
          # uruchamia `occ upgrade` przy pierwszym starcie nowej wersji.
          package = pkgs.nextcloud35;

          database.createLocally = true;

          config = {
            dbtype = "pgsql";
            adminpassFile = config.age.secrets.nextcloud-adminpass.path;
            adminuser = "admin";
          };

          configureRedis = true;
          maxUploadSize = "2G";

          # PHP-FPM pool tuning for RPi4 (4 GB RAM).
          # Default max_children=120 is absurd for 4GB — each child is ~55 MB,
          # so 120 children = 6.6 GB potential allocation. Under memory
          # pressure (RPi4 typically runs with <200 MB free), PHP-FPM cannot
          # spawn new children for upload processing, causing uploads to fail
          # silently. 24 children × 55 MB = ~1.3 GB — fits comfortably.
          # ondemand: prywatna instancja przez większość czasu stoi bezczynnie,
          # więc nie trzymamy w RAM-ie zapasowych workerów.
          poolSettings = {
            pm = "ondemand";
            "pm.max_children" = 24;
            "pm.max_requests" = 500;
            "pm.process_idle_timeout" = "30s";
          };

          phpOptions = {
            "opcache.interned_strings_buffer" = "16";
            # Moduł ustawia memory_limit = maxUploadSize (2G na KAŻDEGO z 24
            # workerów na hoście z 3,7 GB). Upload jest strumieniowany do
            # plików tymczasowych i dzielony na kawałki przez klientów, więc
            # nie potrzebuje limitu równego rozmiarowi pliku; 512M to
            # zalecenie dokumentacji Nextcloud.
            memory_limit = lib.mkForce "512M";
          };
          # occ i nextcloud-cron (podglądy, aktualizacje aplikacji).
          cli.memoryLimit = "1G";

          # Nextcloud dostępny wyłącznie przez Cloudflare Tunnel (via localhost)
          # Odcięto całkowicie dostęp z sieci lokalnej (brak otwartych portów, brak mDNS)
          settings = {
            maintenance_window_start = 1;
            overwriteprotocol = "https";
            "overwrite.cli.url" = "https://${customTop.site.full}";
            trusted_proxies = [
              "127.0.0.1"
              "::1"
            ];
          };
        };

        nginx.virtualHosts."${customTop.site.full}" = {
          # Tylko pętla zwrotna (cloudflared łączy się z 127.0.0.1:80).
          # Domyślne listen to 0.0.0.0:80 i [::]:80 — wtedy LAN od czystego
          # HTTP dzieliła wyłącznie zapora.
          listen = [
            {
              addr = "127.0.0.1";
              port = 80;
            }
          ];
          # HSTS Header
          extraConfig = ''
            add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
          '';
        };

        # PostgreSQL performance tuning for RPi4
        postgresql.settings = {
          shared_buffers = "128MB";
          work_mem = "4MB";
          maintenance_work_mem = "32MB";
          effective_cache_size = "256MB";
          # Jedyny klient (Nextcloud) łączy się przez /run/postgresql
          # (peer auth); nasłuch TCP na lo byłby tylko powierzchnią ataku
          # haseł md5 dla każdego lokalnego procesu. Moduł ustawia
          # "localhost" na zwykłym priorytecie.
          listen_addresses = lib.mkForce "";
        };

        # Redis Nextcloud trzyma tylko cache i blokady plików (z TTL) — bez
        # zrzutów RDB co kilka minut na SSD. Bez zrzutów zbędne jest też
        # globalne vm.overcommit_memory = 1, które moduł ustawia dla fork().
        redis = {
          servers.nextcloud.save = [ ];
          vmOverCommit = false;
        };
      };

      # Bez Redisa (cache + blokady plików) każde żądanie Nextcloud kończy się
      # błędem, a moduł nie ustawia restartu.
      systemd.services.redis-nextcloud.serviceConfig = {
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
}

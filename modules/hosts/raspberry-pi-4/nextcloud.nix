{ customTop, ... }:
{
  flake.modules.nixos.nextcloud =
    { config, pkgs, ... }:
    {
      # nextcloud-setup czyta plik przez LoadCredential.
      age.secrets.nextcloud-adminpass = {
        file = customTop.secretsDir + "/nextcloud-adminpass.age";
        owner = "nextcloud";
        mode = "0400";
      };
      services = {
        nextcloud = {
          enable = true;
          hostName = customTop.site.full;
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
          };

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

        # HSTS Header
        nginx.virtualHosts."${customTop.site.full}".extraConfig = ''
          add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
        '';

        # PostgreSQL performance tuning for RPi4
        postgresql.settings = {
          shared_buffers = "128MB";
          work_mem = "4MB";
          maintenance_work_mem = "32MB";
          effective_cache_size = "256MB";
        };
      };
    };
}

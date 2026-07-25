{ self, customTop, ... }:
{
  flake.modules.nixos.nextcloud =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      age.secrets.nextcloud-adminpass = {
        file = customTop.secretsDir + "/nextcloud-adminpass.age";
        owner = "nextcloud";
        mode = "0440";
      };
      services = {
        nextcloud = {
          enable = true;
          hostName = "${customTop.site.full}";
          package = pkgs.nextcloud34;

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
          poolSettings = {
            pm = "dynamic";
            "pm.max_children" = 24;
            "pm.max_requests" = 500;
            "pm.max_spare_servers" = 6;
            "pm.min_spare_servers" = 2;
            "pm.start_servers" = 4;
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

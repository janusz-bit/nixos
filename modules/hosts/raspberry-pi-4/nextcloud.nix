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

      # Dostęp Nextcloud do plików Hermes workspace (External Storage)
      users.users.nextcloud.extraGroups = [ "hermes" ];

      services = {
        nextcloud = {
          enable = true;
          hostName = "${customTop.site.full}";
          package = pkgs.nextcloud33;

          database.createLocally = true;

          config = {
            dbtype = "pgsql";
            adminpassFile = config.age.secrets.nextcloud-adminpass.path;
            adminuser = "admin";
          };

          configureRedis = true;
          maxUploadSize = "2G";

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

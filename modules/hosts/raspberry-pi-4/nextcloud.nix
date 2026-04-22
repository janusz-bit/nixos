{ self, custom, ... }:
{
  flake.nixosModules."raspberry-pi-4/nextcloud" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      age.secrets.nextcloud-adminpass = {
        file = ../../_secrets/nextcloud-adminpass.age;
        owner = "nextcloud";
        mode = "0440";
      };
      services.nextcloud = {
        enable = true;
        hostName = "${custom.site.full}";
        package = pkgs.nextcloud33;

        database.createLocally = true;

        config = {
          dbtype = "pgsql";
          adminpassFile = config.age.secrets.nextcloud-adminpass.path;
          adminuser = "admin";
        };

        configureRedis = true;
        maxUploadSize = "2G";
      };

      # PostgreSQL performance tuning for RPi4
      services.postgresql.settings = {
        shared_buffers = "128MB";
        work_mem = "4MB";
        maintenance_work_mem = "32MB";
        effective_cache_size = "256MB";
      };

      # Nextcloud dostępny wyłącznie przez Cloudflare Tunnel (via localhost)
      # Odcięto całkowicie dostęp z sieci lokalnej (brak otwartych portów, brak mDNS)
      services.nextcloud.settings = {
        overwriteprotocol = "https";
        "overwrite.cli.url" = "https://${custom.site.full}";
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
}

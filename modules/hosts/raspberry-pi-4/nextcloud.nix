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

      # mDNS dla łatwego dostępu lokalnego
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        publish = {
          enable = true;
          addresses = true;
          domain = true;
        };
      };

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
      services.nextcloud.settings = {
        overwriteprotocol = "https";
        overwritecondaddr = "^127\\.0\\.0\\.1$";
        trusted_proxies = [ "127.0.0.1" ];
        trusted_domains = [
          "localhost"
          "192.168.100.212"
          "raspberry-pi-4.local"
          "raspberry-pi-4"
        ];
      };
    };
}

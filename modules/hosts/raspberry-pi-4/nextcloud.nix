{ self, ... }:
{
  flake.nixosModules."raspberry-pi-4/nextcloud" =
    { config, pkgs, ... }:
    {
      age.secrets.nextcloud-adminpass = {
        file = ../../_secrets/nextcloud-adminpass.age;
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
      };

      services.nextcloud = {
        enable = true;
        hostName = "raspberry-pi-4.local";
        package = pkgs.nextcloud33;

        database.createLocally = true;

        config = {
          dbtype = "pgsql";
          adminpassFile = config.age.secrets.nextcloud-adminpass.path;
          adminuser = "admin";
        };

        configureRedis = true;

        # Performance optimizations
        settings = {
          # Improve PHP performance
          opcache_optimization = true;
          # Enable memory caching
          memcache.local = "\\OC\\Memcache\\Redis";
          memcache.locking = "\\OC\\Memcache\\Redis";
          # Maintenance window to run heavy tasks at night
          maintenance_window_start = 1;
          # Default region for better localization performance
          default_phone_region = "PL";
        };
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
    };
}

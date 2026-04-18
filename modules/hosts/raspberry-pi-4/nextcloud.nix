{ self, ... }:
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
        maxUploadSize = "2G";

        # Performance optimizations
        settings = {
          # Enable memory caching
          memcache.local = "\\OC\\Memcache\\Redis";
          memcache.locking = "\\OC\\Memcache\\Redis";
          # Maintenance window to run heavy tasks at night
          maintenance_window_start = 1;
          # Default region for better localization performance
          default_phone_region = "PL";
          # Limit preview generation to save CPU and SD card wear
          preview_max_x = 1024;
          preview_max_y = 1024;
        };

        # PHP configuration tuning
        phpOptions = {
          "opcache.interned_strings_buffer" = "16";
          "opcache.max_accelerated_files" = "10000";
          "opcache.memory_consumption" = "128";
          "opcache.revalidate_freq" = "1";
          "memory_limit" = lib.mkForce "512M";
        };
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
    };
}

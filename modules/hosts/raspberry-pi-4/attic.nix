{ self, custom, ... }:
{
  flake.nixosModules."raspberry-pi-4/attic" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      age.secrets.attic-server-token = {
        file = custom.secretsDir + "/attic-server-token.age";
        owner = "atticd";
        mode = "0440";
      };

      services.atticd = {
        enable = true;
        environmentFile = config.age.secrets.attic-server-token.path;

        # Attic settings
        settings = {
          # Database configuration
          # SQLite is lightweight and sufficient for RPi4
          database.url = "sqlite:///var/lib/atticd/atticd.db?mode=rwc";

          listen = "[::]:8080";
          allowed-hosts = [ "cache.${custom.site.full}" ];
          api-endpoint = "https://cache.${custom.site.full}/";

          # Storage configuration
          storage = {
            type = "local";
            path = "/var/lib/atticd/storage";
          };

          # Chunking configuration (recommended for Attic)
          chunking = {
            min-size = 65536; # 64 KiB
            avg-size = 131072; # 128 KiB
            max-size = 262144; # 256 KiB
          };

          # Garbage collection
          garbage-collection = {
            interval = "12 hours";
            default-retention-period = "1 months";
          };
        };
      };

      # Create storage directory with correct permissions
      systemd.tmpfiles.rules = [
        "d /var/lib/atticd 0750 atticd atticd -"
        "d /var/lib/atticd/storage 0750 atticd atticd -"
      ];
    };
}

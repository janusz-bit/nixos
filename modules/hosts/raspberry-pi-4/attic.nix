{ self, custom, ... }:
{
  flake.nixosModules."raspberry-pi-4/attic" =
    { config, ... }:
    {
      age.secrets.attic-server-token = {
        file = custom.secretsDir + "/attic-server-token.age";
        mode = "0444";
      };

      services.atticd = {
        enable = true;
        environmentFile = config.age.secrets.attic-server-token.path;

        settings = {
          listen = "[::]:8080";
          allowed-hosts = [ "cache.${custom.site.full}" ];
          api-endpoint = "https://cache.${custom.site.full}/";

          # SQLite is lightweight and sufficient for RPi4
          database.url = "sqlite:///var/lib/atticd/atticd.db?mode=rwc";

          # Chunking configuration (recommended for Attic)
          chunking = {
            nar-size-threshold = 65536; # 64 KiB
            min-size = 16384; # 16 KiB
            avg-size = 65536; # 64 KiB
            max-size = 262144; # 256 KiB
          };

          garbage-collection = {
            interval = "12 hours";
            default-retention-period = "1 months";
          };
        };
      };
    };
}

{ self, ... }:
{
  flake.nixosModules.raspberry-pi-4-nextcloud =
    { config, pkgs, ... }:
    {
      age.secrets.nextcloud-adminpass = {
        file = ../_secrets/nextcloud-adminpass.age;
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
      };

      services.nextcloud = {
        enable = true;
        hostName = "raspberry-pi-4.local";
        package = pkgs.nextcloud32;

        database.createLocally = true;

        config = {
          dbtype = "sqlite";
          adminpassFile = config.age.secrets.nextcloud-adminpass.path;
          adminuser = "admin";
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

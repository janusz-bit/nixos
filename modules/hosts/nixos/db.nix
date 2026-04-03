{ inputs, ... }:
{
  flake.nixosModules.nixos-db =
    {
      config,
      pkgs,
      lib,
      ...
    }:

    {
      virtualisation = {
        containers.enable = true;
        podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true; # Required for containers under podman-compose to be able to talk to each other.
        };
      };

      users.users.${config.custom.defaultUser} = {
        # replace `<USERNAME>` with the actual username
        extraGroups = [
          "podman"
        ];
      };
      environment.systemPackages = [
        pkgs.oracle-instantclient
      ];
    };

}

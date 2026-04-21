{ self, custom, ... }:
{
  flake.nixosModules."raspberry-pi-4/cloudflared" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.cloudflared = {
        enable = true;
        tunnels = {
          "raspberry-pi-4" = {
            credentialsFile = config.age.secrets.cloudflared-tunnel.path;
            default = "http_status:404";
            ingress = {
              "${custom.site.full}" = "http://localhost:80";
            };
          };
        };
      };
    };
}

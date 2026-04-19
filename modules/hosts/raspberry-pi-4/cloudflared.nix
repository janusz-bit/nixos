{ self, ... }:
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
            # credentialsFile = config.age.secrets.cloudflared-tunnel.path;
            default = "http_status:404";
            ingress = {
              "cloud.example.com" = "http://localhost:80";
            };
          };
        };
      };
    };
}

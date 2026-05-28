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
      age.secrets.cloudflared-tunnel = {
        file = custom.secretsDir + "/cloudflared-tunnel.age";
        owner = "root";
        group = "root";
        mode = "0440";
      };
      services.cloudflared = {
        enable = true;
        tunnels = {
          "raspberry-pi-4" = {
            credentialsFile = config.age.secrets.cloudflared-tunnel.path;
            default = "http_status:404";
            ingress = {
              "chat.${custom.site.full}" = "http://localhost:8080";
              "hermes.${custom.site.full}" = "http://127.0.0.1:8642";
              "${custom.site.full}" = "http://localhost:80";
              "notes.${custom.site.full}" = "http://localhost:8081";
              "ssh.${custom.site.full}" = "ssh://localhost:22";
            };
          };
        };
      };
    };
}

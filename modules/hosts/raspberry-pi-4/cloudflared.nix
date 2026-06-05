{ self, ... }:
{
  flake.modules.nixos.cloudflared =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      age.secrets.cloudflared-tunnel = {
        file = config.customTop.secretsDir + "/cloudflared-tunnel.age";
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
              "chat.${config.customTop.site.full}" = "http://localhost:8080";
              "agent.${config.customTop.site.full}" = "http://localhost:8787";
              "${config.customTop.site.full}" = "http://localhost:80";
              "notes.${config.customTop.site.full}" = "http://localhost:8081";
              "ssh.${config.customTop.site.full}" = "ssh://localhost:22";
            };
          };
        };
      };
    };
}

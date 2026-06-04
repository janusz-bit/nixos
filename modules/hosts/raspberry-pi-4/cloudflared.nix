{ self, customTop, ... }:
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
        file = customTop.secretsDir + "/cloudflared-tunnel.age";
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
              "chat.${customTop.site.full}" = "http://localhost:8080";
              "agent.${customTop.site.full}" = "http://localhost:8787";
              "${customTop.site.full}" = "http://localhost:80";
              "notes.${customTop.site.full}" = "http://localhost:8081";
              "ssh.${customTop.site.full}" = "ssh://localhost:22";
            };
          };
        };
      };
    };
}

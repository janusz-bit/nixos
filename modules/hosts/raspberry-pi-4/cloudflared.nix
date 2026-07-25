{ self, customTop, ... }:
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
              # Nextcloud — longer timeouts for photo uploads through tunnel.
              # Default connectTimeout (30s) was too short: cloudflared canceled
              # upload streams mid-transfer ("stream canceled by remote with
              # error code 0"). 300s gives PHP-FPM enough time to process
              # large files even under memory pressure.
              "${customTop.site.full}" = {
                service = "http://localhost:80";
                originRequest = {
                  connectTimeout = "300s";
                  keepAliveConnections = 10;
                  keepAliveTimeout = "2m";
                };
              };
              "chat.${customTop.site.full}" = {
                service = "http://localhost:8080";
                originRequest = {
                  connectTimeout = "300s";
                  keepAliveConnections = 10;
                  keepAliveTimeout = "2m";
                };
              };
              "notes.${customTop.site.full}" = "http://localhost:8081";
              "ssh.${customTop.site.full}" = "ssh://localhost:22";
              "git.${customTop.site.full}" = "http://localhost:3000";
            };
          };
        };
      };
    };
}

# Gitea w tailnecie pod https://<RPi>.<tailnet>:3000: SQLite (lekka baza dla
# RPi), HTTP tylko na 127.0.0.1:3000 za Tailscale Serve, bez rejestracji.
# Git po SSH obsługuje systemowy sshd (wbudowany serwer SSH Gitei wyłączony)
# przez tailscale0: gitea@<RPi>.<tailnet>.
#
# Sprawdzenie: `systemctl status gitea`,
# `curl -s http://127.0.0.1:3000/api/v1/version`.
_: {
  flake.modules.nixos.rpi-gitea =
    { config, ... }:
    let
      host = "${config.networking.hostName}.${config.customTop.tailnet}";
      servePort = 3000;
    in
    {
      services.gitea = {
        enable = true;
        database.type = "sqlite3";

        settings = {
          server = {
            ROOT_URL = "https://${host}:${toString servePort}/";
            HTTP_ADDR = "127.0.0.1";
            START_SSH_SERVER = false;
            SSH_DOMAIN = host;
          };
          service.DISABLE_REGISTRATION = true;
          session.COOKIE_SECURE = true;
        };
      };

      customBot = {
        tailscaleServe.${toString servePort} =
          "http://127.0.0.1:${toString config.services.gitea.settings.server.HTTP_PORT}";
        lockdownServices = [ "gitea" ];
      };
    };
}

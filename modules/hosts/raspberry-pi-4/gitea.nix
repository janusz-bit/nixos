# Gitea pod git.<domena>: SQLite (lekka baza dla RPi), HTTP tylko na
# 127.0.0.1:3000 przez Cloudflare Tunnel, bez rejestracji. Git po SSH
# obsługuje systemowy sshd (wbudowany serwer SSH Gitei wyłączony).
#
# Sprawdzenie: `systemctl status gitea`,
# `curl -s http://127.0.0.1:3000/api/v1/version`.
{ customTop, ... }:
{
  flake.modules.nixos.rpi-gitea = _: {
    services.gitea = {
      enable = true;
      database.type = "sqlite3";

      settings = {
        server = {
          DOMAIN = "git.${customTop.site.full}";
          ROOT_URL = "https://git.${customTop.site.full}/";
          HTTP_ADDR = "127.0.0.1";
          HTTP_PORT = 3000;
          DISABLE_SSH = false;
          START_SSH_SERVER = false;
          SSH_DOMAIN = "git.${customTop.site.full}";
          SSH_PORT = 22;
        };
        service.DISABLE_REGISTRATION = true;
        session.COOKIE_SECURE = true;
      };
    };
  };
}

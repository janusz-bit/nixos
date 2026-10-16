# Gitea pod git.<domena>: SQLite (lekka baza dla RPi), HTTP tylko na
# 127.0.0.1:3000 przez Cloudflare Tunnel, bez rejestracji. Git po SSH
# obsługuje systemowy sshd (wbudowany serwer SSH Gitei wyłączony), pod
# adresem gitea@ssh.<domena>.
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
          ROOT_URL = "https://git.${customTop.site.full}/";
          HTTP_ADDR = "127.0.0.1";
          HTTP_PORT = 3000;
          DISABLE_SSH = false;
          START_SSH_SERVER = false;
          # Adres klonowania przez SSH: git.<domena> tunel podaje tylko jako
          # HTTP, sshd osiąga ssh.<domena> (`cloudflared access ssh` z bloku
          # `Host ssh.*` w base-ssh; jawny `gitea@` wygrywa z `User root`).
          SSH_DOMAIN = "ssh.${customTop.site.full}";
          SSH_PORT = 22;
        };
        service.DISABLE_REGISTRATION = true;
        session.COOKIE_SECURE = true;
      };
    };
  };
}

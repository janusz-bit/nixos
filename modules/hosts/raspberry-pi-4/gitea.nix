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
          ROOT_URL = "https://git.${customTop.domain}/";
          HTTP_ADDR = "127.0.0.1";
          HTTP_PORT = 3000;
          START_SSH_SERVER = false;
          # Klonowanie przez SSH idzie przez ssh.<domena> (git.<domena> tunel
          # podaje tylko jako HTTP); jawny `gitea@` wygrywa z `User root`
          # z bloku `Host ssh.*` w base-ssh.
          SSH_DOMAIN = "ssh.${customTop.domain}";
        };
        service.DISABLE_REGISTRATION = true;
        session.COOKIE_SECURE = true;
      };
    };
  };
}

{ customTop, ... }:
{
  flake.modules.nixos.ttyd =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ttydPort = 8082;
      # cloudflared ingress target (modules/hosts/raspberry-pi-4/cloudflared.nix)
      proxyPort = 8083;
      htpasswd = "/run/ttyd-auth/htpasswd";

      # Dedykowane hasło: modules/_secrets/ttyd-password.age (agenix -e).
      # Dopóki pliku nie ma, nginx używa hasła admina Nextcloud — ale już nie
      # przez linię poleceń ttyd. Po dodaniu pliku przełącza się sam.
      ownSecretFile = customTop.secretsDir + "/ttyd-password.age";
      hasOwnSecret = builtins.pathExists ownSecretFile;
      passwordFile =
        if hasOwnSecret then
          config.age.secrets.ttyd-password.path
        else
          config.age.secrets.nextcloud-adminpass.path;
    in
    {
      # Web terminal (ttyd) exposed ONLY through the Cloudflare Tunnel:
      # ttyd.janusz-bit.com -> nginx 127.0.0.1:8083 (Basic Auth) -> ttyd
      # 127.0.0.1:8082. Firewall leaves both ports closed.
      #
      # Basic Auth robi nginx, nie ttyd: moduł ttyd przekazuje hasło jako
      # `--credential user:hasło`, czyli w /proc/*/cmdline widocznym dla
      # każdego lokalnego procesu (w tym agenta hermes). nginx czyta tylko
      # hash SHA-512-crypt z pliku 0440 root:nginx.
      #
      # Entrypoint pattern taken from the OCF Berkeley production config
      # (ocf/nix, modules/ttyd.nix): spawn the system `login` program
      # instead of a bare shell. `login` is the SAME binary SSH uses —
      # it sets up the full PAM session, sources /etc/profile and the
      # NixOS environment, then starts the user's login shell (fish via
      # the base bash->fish exec chain). Lokalny proces, który połączy się
      # z 127.0.0.1:8082 z pominięciem nginx, dostaje tylko prompt `login`.
      age.secrets = lib.mkIf hasOwnSecret {
        ttyd-password.file = ownSecretFile;
      };

      services.ttyd = {
        enable = true;
        port = ttydPort;
        interface = "lo";
        writeable = true;
        # `login` must run as root to be able to set up user sessions.
        user = "root";
        entrypoint = [
          (lib.getExe' pkgs.shadow "login")
        ];
      };

      systemd.services.ttyd-htpasswd = {
        description = "Plik htpasswd nginx dla ttyd z sekretu agenix";
        wantedBy = [ "nginx.service" ];
        before = [ "nginx.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Group = config.services.nginx.group;
          RuntimeDirectory = "ttyd-auth";
          RuntimeDirectoryMode = "0750";
          LoadCredential = "password:${passwordFile}";
          UMask = "0027";
        };
        # Hasło idzie przez stdin (nie argv); do pliku trafia tylko hash.
        script = ''
          hash="$(${lib.getExe pkgs.openssl} passwd -6 -stdin < "$CREDENTIALS_DIRECTORY/password")"
          printf 'admin:%s\n' "$hash" > ${htpasswd}.tmp
          mv -f ${htpasswd}.tmp ${htpasswd}
        '';
      };

      services.nginx = {
        enable = true;
        virtualHosts."ttyd.${customTop.site.full}" = {
          listen = [
            {
              addr = "127.0.0.1";
              port = proxyPort;
            }
          ];
          basicAuthFile = htpasswd;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString ttydPort}";
            proxyWebsockets = true;
          };
        };
      };
    };
}

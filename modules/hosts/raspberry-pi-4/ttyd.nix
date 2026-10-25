# Terminal WWW (ttyd) wystawiony wyłącznie przez Cloudflare Tunnel:
# ttyd.<domena> -> nginx 127.0.0.1:8083 (Basic Auth, limit żądań) -> ttyd
# (root, `login`) na gnieździe UNIX /run/ttyd/ttyd.sock.
#
# Gniazdo zamiast portu TCP na lo: do TCP mógł połączyć się każdy lokalny
# proces (w tym agent hermes) z pominięciem Basic Auth. Gniazdo root:nginx
# 0660 w katalogu 0750 otwiera tylko nginx.
#
# Basic Auth robi nginx, nie ttyd: moduł ttyd przekazuje hasło jako
# `--credential user:hasło`, czyli w /proc/*/cmdline widocznym dla każdego
# lokalnego procesu. nginx czyta tylko hash SHA-512-crypt z pliku 0640
# root:nginx, a hasło jest osobnym sekretem (ttyd-password.age, asercja).
#
# Entrypoint jak w OCF Berkeley (ocf/nix, modules/ttyd.nix): systemowy
# `login` zamiast gołej powłoki, czyli pełna sesja PAM, /etc/profile
# i powłoka logowania jak przez SSH.
#
# Sprawdzenie: `systemctl status ttyd ttyd-htpasswd`,
# `sudo ls -l /run/ttyd/ttyd.sock` (srw-rw---- root nginx),
# `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8083/` (401).
_: {
  flake.modules.nixos.rpi-ttyd =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Cel ingress w cloudflared.nix.
      proxyPort = 8083;
      socketDir = "/run/ttyd";
      socket = "${socketDir}/ttyd.sock";
      authDir = "/run/ttyd-auth";
      htpasswd = "${authDir}/htpasswd";

      # Własne hasło Basic Auth, celowo bez wartości zastępczej (asercja).
      secretFile = config.age.secrets.ttyd-password.file;
    in
    {
      assertions = [
        {
          assertion = builtins.pathExists secretFile;
          message = ''
            ttyd: brak modules/_secrets/ttyd-password.age (git add po utworzeniu).
            Hasło Basic Auth powłoki z dostępem do roota nie może być hasłem innej
            usługi. Utwórz je na laptopie w devShellu:
              cd modules/_secrets && openssl rand -base64 32 | agenix -e ttyd-password.age
          '';
        }
      ];

      # Czyta je wyłącznie systemd (LoadCredential) — domyślne root:root 0400.
      age.secrets.ttyd-password.file = config.customTop.secretsDir + "/ttyd-password.age";

      services.ttyd = {
        enable = true;
        inherit socket;
        # Origin musi zgadzać się z Host (nginx: proxy_set_header Host $host).
        # Bez tego strona z innej domeny otwiera WebSocket z zapamiętanymi
        # w przeglądarce danymi Basic Auth (cross-site WebSocket hijacking).
        checkOrigin = true;
        writeable = true;
        # `login` zakłada sesje użytkowników, więc musi działać jako root.
        user = "root";
        entrypoint = [
          (lib.getExe' pkgs.shadow "login")
        ];
        # Obrazki (Sixel, iTerm2 IIP) w xterm.js; tmux przepuszcza Sixel
        # (terminal-features w base/shell.nix).
        clientOptions.enableSixel = "true";
      };

      systemd.services = {
        ttyd.serviceConfig = {
          # Grupa główna nginx + UMask 0007 => gniazdo root:nginx 0660
          # (libwebsockets nie nadaje bitów x; do connect() wystarcza w).
          Group = config.services.nginx.group;
          UMask = "0007";
          RuntimeDirectory = baseNameOf socketDir;
          RuntimeDirectoryMode = "0750";
          Restart = "on-failure";
          RestartSec = "5s";
        };

        ttyd-htpasswd = {
          description = "Plik htpasswd nginx dla ttyd z sekretu agenix";
          wantedBy = [ "nginx.service" ];
          before = [ "nginx.service" ];
          # Nowa treść sekretu nie zmienia ścieżki /run/agenix/ttyd-password —
          # restart przy zmianie pliku .age odświeża hash bez rebootu.
          restartTriggers = [ (builtins.hashFile "sha256" secretFile) ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Group = config.services.nginx.group;
            RuntimeDirectory = baseNameOf authDir;
            RuntimeDirectoryMode = "0750";
            # Zatrzymanie jednostki (switch) nie kasuje htpasswd — inaczej
            # nginx odrzucał logowania ttyd do jej ponownego startu.
            RuntimeDirectoryPreserve = "yes";
            LoadCredential = "password:${config.age.secrets.ttyd-password.path}";
            UMask = "0027";
          };
          # Hasło idzie przez stdin (nie argv); do pliku trafia tylko hash.
          script = ''
            hash="$(${lib.getExe pkgs.openssl} passwd -6 -stdin < "$CREDENTIALS_DIRECTORY/password")"
            printf 'admin:%s\n' "$hash" > ${htpasswd}.tmp
            mv -f ${htpasswd}.tmp ${htpasswd}
          '';
        };
      };

      services.nginx = {
        enable = true;
        # Ruch z tunelu przychodzi z 127.0.0.1; klucz z CF-Connecting-IP
        # rozdziela klientów, a lokalne żądania (bez nagłówka) dzielą jeden
        # kubełek z adresem pętli zwrotnej — limit obejmuje też je.
        appendHttpConfig = ''
          limit_req_zone $binary_remote_addr$http_cf_connecting_ip zone=ttyd:1m rate=10r/m;
        '';
        virtualHosts."ttyd.${config.customTop.domain}" = {
          listen = [
            {
              addr = "127.0.0.1";
              port = proxyPort;
            }
          ];
          basicAuthFile = htpasswd;
          locations."/" = {
            proxyPass = "http://unix:${socket}";
            proxyWebsockets = true;
            # Host $host — od niego zależy --check-origin w ttyd.
            recommendedProxySettings = true;
            extraConfig = ''
              limit_req zone=ttyd burst=10 nodelay;
              limit_req_status 429;
            '';
          };
        };
      };
    };
}

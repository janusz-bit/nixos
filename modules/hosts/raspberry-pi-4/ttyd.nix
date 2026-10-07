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
      # cloudflared ingress target (modules/hosts/raspberry-pi-4/cloudflared.nix)
      proxyPort = 8083;
      socketDir = "/run/ttyd";
      socket = "${socketDir}/ttyd.sock";
      htpasswd = "/run/ttyd-auth/htpasswd";

      # Dedykowane hasło Basic Auth: modules/_secrets/ttyd-password.age
      # (agenix -e, plik śledzony w gicie). Celowo bez wartości zastępczej —
      # wcześniej brak pliku oznaczał po cichu hasło admina Nextcloud.
      # Asercja i restartTriggers biorą ścieżkę z config, więc test VM
      # (modules/checks/rpi-services.nix) podstawia własny zaszyfrowany plik.
      secretFile = config.age.secrets.ttyd-password.file;
    in
    {
      # Web terminal (ttyd) exposed ONLY through the Cloudflare Tunnel:
      # ttyd.janusz-bit.com -> nginx 127.0.0.1:8083 (Basic Auth, limit
      # żądań) -> ttyd na gnieździe UNIX ${socket}.
      #
      # Gniazdo zamiast portu TCP na lo: do TCP mógł połączyć się każdy
      # lokalny proces (w tym agent hermes) z pominięciem Basic Auth. Gniazdo
      # root:nginx 0660 w katalogu 0750 otwiera tylko nginx.
      #
      # Basic Auth robi nginx, nie ttyd: moduł ttyd przekazuje hasło jako
      # `--credential user:hasło`, czyli w /proc/*/cmdline widocznym dla
      # każdego lokalnego procesu. nginx czyta tylko hash SHA-512-crypt
      # z pliku 0640 root:nginx.
      #
      # Entrypoint pattern taken from the OCF Berkeley production config
      # (ocf/nix, modules/ttyd.nix): spawn the system `login` program
      # instead of a bare shell. `login` is the SAME binary SSH uses —
      # it sets up the full PAM session, sources /etc/profile and the
      # NixOS environment, then starts the user's login shell (fish via
      # the base bash->fish exec chain).
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
      age.secrets.ttyd-password.file = customTop.secretsDir + "/ttyd-password.age";

      services.ttyd = {
        enable = true;
        inherit socket;
        # Origin musi zgadzać się z Host (nginx: proxy_set_header Host $host).
        # Bez tego strona z innej domeny otwiera WebSocket z zapamiętanymi
        # w przeglądarce danymi Basic Auth (cross-site WebSocket hijacking).
        checkOrigin = true;
        writeable = true;
        # `login` must run as root to be able to set up user sessions.
        user = "root";
        entrypoint = [
          (lib.getExe' pkgs.shadow "login")
        ];
        # Obrazki w terminalu: xterm.js ładuje image addon (Sixel + iTerm2
        # IIP). tmux przepuszcza Sixel dzięki terminal-features w
        # modules/hosts/base/shell.nix (ttyd zgłasza się jako xterm-256color).
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
          restartTriggers = [ secretFile ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Group = config.services.nginx.group;
            RuntimeDirectory = "ttyd-auth";
            RuntimeDirectoryMode = "0750";
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
        virtualHosts."ttyd.${customTop.site.full}" = {
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

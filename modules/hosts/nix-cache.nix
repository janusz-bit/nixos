# Cache Nix w tailnecie na raspberry-pi-4: zwykły binary cache (*.narinfo,
# nar/) w /var/lib/nix-cache/files, który nginx wystawia przez Tailscale Serve
# pod customTop.nixCache.url. GitHub Actions dołącza do tailnetu jako
# efemeryczny węzeł tag:ci i wysyła tam podpisane wyniki buildów
# (nix-cache-push), a laptop, RPi i CI pobierają z niego obok cache.nixos.org
# i Cachix.
#
# Granica zaufania:
# - Podpisuje CI: klucz prywatny jest tylko w sekrecie GitHub Actions
#   NIX_CACHE_SIGNING_KEY. RPi przechowuje pliki i niczego nie podpisuje, więc
#   przejęty RPi może cache zepsuć albo opróżnić (Nix weźmie ścieżkę z innego
#   cache'a albo ją zbuduje), ale nie podsunie hostom zmienionej ścieżki:
#   klient sprawdza podpis i NarHash. Attic odpadł, bo podpisuje na serwerze.
#   Klucz w GitHubie nie otwiera nowej drogi: kto przejmie repo, ten i tak
#   wdraża przez `update`.
# - Zapis tylko PUT-em z hasłem (nix-cache-htpasswd.age, konto `ci`), odczyt
#   bez hasła dla tailnetu. Inne metody WebDAV (DELETE, MOVE) są wyłączone, więc
#   z hasłem da się tylko dopisać albo nadpisać plik, którego bez podpisu
#   klienci nie przyjmą. nix-cache-info jest stałe w nginx.
# - Z backendem łączy się lokalnie tylko root (proxy tailscaled, nix-daemon
#   RPi): customBot.tailscaleServe.users = [ ].
# - Polityka tailnetu (panel Tailscale) wpuszcza tag:ci tylko na port cache'a
#   na RPi, więc węzeł CI nie widzi laptopa ani innych usług RPi.
#
# - nginx buforuje ciało PUT w client_body_temp_path. Domyślne /tmp to na RPi
#   tmpfs (rpi-resources), a NAR-y kernela czy CUDA mają gigabajty, więc bufor
#   (upload/) leży na SSD w tym samym montowaniu co pliki: rename między dwoma
#   ReadWritePaths daje EXDEV, a wtedy nginx kopiuje NAR blokująco w procesie
#   roboczym i stoi też Nextcloud.
# - nix-cache-push wysyła domknięcie wyniku bez ścieżek podpisanych przez
#   cache.nixos.org (pełne domknięcie laptopa to dziesiątki GB) i bez tych,
#   które cache już ma, po jednej naraz (nagłówek _nix-cache/push.sh: czemu
#   nie nix copy wprost do cache'a). nix-cache-info
#   nie ma Priority, więc cache ma domyślne 50 i ścieżki obecne w
#   cache.nixos.org (40) klienci biorą stamtąd.
# - nix-cache-gc (codziennie, jako nginx) usuwa narinfo starsze niż
#   RETENTION_DAYS, a NAR-y, do których nie prowadzi już żaden narinfo, przy
#   następnym przebiegu. Wiek liczy się od wysłania, bo Nix nie wysyła ponownie
#   ścieżki, którą cache już ma; CI wyśle ją znowu, gdy po usunięciu jej użyje.
#
# Jednorazowo:
# - Na laptopie klucz `nix key generate-secret --key-name <owner>-ci-1`:
#   prywatny do sekretu GitHuba NIX_CACHE_SIGNING_KEY, publiczny do
#   customTop.nixCache.publicKey. Losowe hasło do sekretu
#   NIX_CACHE_PUSH_PASSWORD, `ci:<openssl passwd -6>` do nix-cache-htpasswd.age.
# - Panel Tailscale: tag:ci w tagOwners; Trust credentials -> OpenID Connect
#   dla GitHub Actions (subject repo:<owner>/<repo>:*, scope auth_keys, tag
#   tag:ci) -> sekrety GitHuba TS_OAUTH_CLIENT_ID i TS_AUDIENCE. W polityce
#   ogólna reguła ze src autogroup:member zamiast "*" (tag:ci nie jest
#   członkiem) i grant tag:ci -> adres tailnetu RPi, ip tcp:<nixCache.port>.
#
# Sprawdzenie: na laptopie `curl -s <nixCache.url>/nix-cache-info` i
# `nix path-info --store <nixCache.url> <ścieżka z CI>`; na RPi
# `systemctl list-timers nix-cache-gc`, `journalctl -u nix-cache-gc`; test VM
# `nix build -L .#checks.<system>.nix-cache`.
{ config, ... }:
let
  inherit (config.customTop) nixCache;
  pushUser = "ci";
  backendPort = 8081;
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.nix-cache-push = pkgs.writeShellApplication {
        name = "nix-cache-push";
        # Własny nix, nie ten z runnera: format `path-info --json-format 1`.
        runtimeInputs = [
          pkgs.nix
          pkgs.jq
          pkgs.coreutils
          pkgs.curl
          pkgs.gnused
        ];
        runtimeEnv = {
          NIX_CACHE_DEFAULT_URL = nixCache.url;
          NIX_CACHE_USER = pushUser;
        };
        text = builtins.readFile ./_nix-cache/push.sh;
      };
    };

  flake.modules.nixos.nixos-nix-cache = {
    nix.settings = {
      extra-substituters = [ nixCache.url ];
      extra-trusted-public-keys = [ nixCache.publicKey ];
      # Gdy RPi nie odpowiada, curl bez limitu czeka na połączenie 300 s,
      # a Nix ponawia próby (download-attempts), więc rebuild stałby minutami.
      connect-timeout = 5;
    };
  };

  flake.modules.nixos.rpi-nix-cache =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.services.nginx) user group;
      stateDir = "/var/lib/nix-cache";
      filesDir = "${stateDir}/files";
      uploadDir = "${stateDir}/upload";
      gc = pkgs.writeShellApplication {
        name = "nix-cache-gc";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          gnused
        ];
        text = builtins.readFile ./_nix-cache/gc.sh;
      };
    in
    {
      age.secrets.nix-cache-htpasswd = {
        file = config.customTop.secretsDir + "/nix-cache-htpasswd.age";
        owner = user;
      };

      services.nginx = {
        enable = true;
        virtualHosts.nix-cache = {
          listen = [
            {
              addr = "127.0.0.1";
              port = backendPort;
            }
          ];
          root = filesDir;
          extraConfig = ''
            client_max_body_size 0;
            client_body_temp_path ${uploadDir};
          '';
          locations = {
            "= /nix-cache-info".extraConfig = ''
              default_type text/plain;
              return 200 "StoreDir: ${builtins.storeDir}\n";
            '';
            "/".extraConfig = ''
              dav_methods PUT;
              create_full_put_path on;
              dav_access user:rw group:r all:r;
              limit_except GET HEAD {
                auth_basic "nix-cache";
                auth_basic_user_file ${config.age.secrets.nix-cache-htpasswd.path};
              }
            '';
          };
        };
      };

      systemd = {
        # stateDir należy do roota: nginx tworzy przy starcie (jako root)
        # client_body_temp_path i zmienia mu właściciela, a w katalogu konta
        # nginx to konto mogłoby podmienić upload/ na dowiązanie.
        tmpfiles.settings.nix-cache = {
          ${stateDir}.d.mode = "0755";
          ${filesDir}.d = {
            inherit user group;
            mode = "0750";
          };
          # Przerwany PUT nginx sprząta sam, ale po awarii RPi niedokończone
          # bufory zostają; usuwa je systemd-tmpfiles-clean.
          ${uploadDir}.d = {
            inherit user group;
            mode = "0700";
            age = "1d";
          };
        };

        services = {
          # Cały stateDir jako jedno montowanie (nagłówek: EXDEV). Przy switch
          # tmpfiles tworzy katalogi przed restartem nginx
          # (sysinit-reactivation.target).
          nginx.serviceConfig.ReadWritePaths = [ stateDir ];

          nix-cache-gc = {
            description = "Remove old entries from the tailnet nix cache";
            startAt = "daily";
            environment = {
              NIX_CACHE_DIR = filesDir;
              RETENTION_DAYS = "90";
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe gc;
              User = user;
              Group = group;
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              PrivateNetwork = true;
              ReadWritePaths = [ filesDir ];
            };
          };
        };
      };

      # Bez Serve: połączenia RPi na własny adres tailnetu są odrzucane
      # (hosts/tailscale.nix).
      nix.settings = {
        extra-substituters = [ "http://127.0.0.1:${toString backendPort}" ];
        extra-trusted-public-keys = [ nixCache.publicKey ];
      };

      customBot = {
        tailscaleServe.${toString nixCache.port} = {
          port = backendPort;
          users = [ ];
        };
        lockdownServices = [ "nginx" ];
      };
    };
}

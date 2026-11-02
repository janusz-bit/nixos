# Nextcloud 35 pod nextcloud.<domena> (customTop.domain): PostgreSQL i Redis
# lokalnie, PHP-FPM i PostgreSQL dostrojone do 4 GB RAM RPi; dostępny
# wyłącznie z tailnetu (tailnet.nix: nginx na adresie tailnetu, HTTPS z
# Let's Encrypt przez DNS-01, nazwa tylko w MagicDNS headscale). Nie ma go
# w Cloudflare Tunnel, w LAN-ie ani w internecie, a publiczne linki do
# udostępniania plików nie działają. Aplikacje mobilne wymagają włączonego
# klienta tailnetu.
#
# Domena główna zostaje w tunelu tylko dla /.well-known/matrix/client
# (matrix.nix), na własnym vhoście bez Nextcloudu.
#
# nixpkgs instaluje bez admina (`occ maintenance:install --disable-admin-user`):
# po świeżej instalacji `sudo nextcloud-occ user:add <nazwa>` i
# `sudo nextcloud-occ group:adduser admin <nazwa>`. Hasło istniejącego `admin`
# jest tylko kopią w `nextcloud-adminpass.age` (żaden host go nie deklaruje).
#
# PHP pochodzi z inputu `nixpkgs-unstable-small` (PHP2Shell, temporary-fixes.md); asercja
# pilnuje, żeby żadna zmiana nie wróciła do PHP < 8.4.27.
#
# Sprawdzenie: `systemctl status phpfpm-nextcloud`, `sudo nextcloud-occ status`,
# `sudo nextcloud-occ config:system:get trusted_proxies`.
{ inputs, ... }:
{
  flake.modules.nixos.rpi-nextcloud =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # PHP2Shell (CVE-2026-109618, CVE-2026-109619): nieuwierzytelnione RCE
      # w PHP, poprawione w 8.4.27; tailnet ogranicza dostęp do urządzeń
      # z kluczem, ale nie zastępuje poprawki.
      assertions = [
        {
          assertion = lib.versionAtLeast config.services.nextcloud.phpPackage.version "8.4.27";
          message = "rpi-nextcloud: PHP ${config.services.nextcloud.phpPackage.version} jest podatne na PHP2Shell (CVE-2026-109618/109619); użyj php84 >= 8.4.27.";
        }
      ];

      services = {
        nextcloud = {
          enable = true;
          hostName = "nextcloud.${config.customTop.domain}";
          https = true;
          # Upgrade o jedną wersję główną naraz (34 → 35); nextcloud-setup
          # uruchamia `occ upgrade` przy pierwszym starcie nowej wersji.
          package = pkgs.nextcloud35;
          # PHP2Shell: przypięty nixpkgs ma php84 8.4.26, poprawka (8.4.27,
          # NixOS/nixpkgs#576853) jest na razie tylko w nixos-unstable-small.
          # Usunąć (i input `nixpkgs-unstable-small`, jeśli nic innego go nie
          # używa), gdy pkgs.php84 >= 8.4.27 (temporary-fixes.md).
          phpPackage = inputs.nixpkgs-unstable-small.legacyPackages.${pkgs.stdenv.hostPlatform.system}.php84;

          database.createLocally = true;

          config.dbtype = "pgsql";

          maxUploadSize = "2G";

          # Domyślne max_children=120 × ~55 MB = 6,6 GB przy 4 GB RAM: pod
          # presją pamięci (zwykle <200 MB wolnego) PHP-FPM nie startował
          # nowych workerów i uploady po cichu padały; 24 × 55 MB ≈ 1,3 GB.
          # ondemand: instancja zwykle stoi bezczynnie, bez zapasowych workerów.
          poolSettings = {
            pm = "ondemand";
            "pm.max_children" = 24;
            "pm.max_requests" = 500;
            "pm.process_idle_timeout" = "30s";
          };

          phpOptions."opcache.interned_strings_buffer" = "16";

          # occ, cron i maile nie znają adresu nginxa (inaczej linki na
          # localhost).
          settings = {
            maintenance_window_start = 1;
            "overwrite.cli.url" = "https://${config.services.nextcloud.hostName}";
          };
        };

        nginx.virtualHosts.${config.services.nextcloud.hostName} = {
          listenAddresses = [ config.customBot.tailnetAddress ];
          forceSSL = true;
          enableACME = true;
          # Certyfikat przez DNS-01 (tailnet.nix), nie przez webroot.
          acmeRoot = null;
        };

        postgresql.settings = {
          shared_buffers = "128MB";
          work_mem = "4MB";
          maintenance_work_mem = "32MB";
          effective_cache_size = "256MB";
        };
      };
    };
}

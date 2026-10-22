# Nextcloud 35 pod domeną główną (customTop.site.full): PostgreSQL i Redis
# lokalnie, PHP-FPM i PostgreSQL dostrojone do 4 GB RAM RPi; dostępny
# wyłącznie przez Cloudflare Tunnel (cloudflared → nginx :80).
#
# Dostęp z LAN-u celowo odcięty: nginx słucha na :80 tylko na localhost
# (defaultListenAddresses w network.nix) i nie ma mDNS (avahi). Ten vhost serwuje też
# /.well-known/matrix/client (matrix.nix).
#
# Konto `admin` powstało przy pierwszej instalacji; nixpkgs instaluje teraz bez
# admina (`occ maintenance:install --disable-admin-user`), więc po świeżej
# instalacji: `sudo nextcloud-occ user:add <nazwa>` i
# `sudo nextcloud-occ group:adduser admin <nazwa>`. Hasło obecnego `admin` zostaje
# tylko jako kopia w `nextcloud-adminpass.age` (żaden host go nie deklaruje).
#
# Sprawdzenie: `systemctl status phpfpm-nextcloud`, `sudo nextcloud-occ status`,
# `sudo nextcloud-occ config:system:get trusted_proxies`.
{ customTop, ... }:
{
  flake.modules.nixos.rpi-nextcloud =
    { pkgs, ... }:
    {
      services = {
        nextcloud = {
          enable = true;
          hostName = customTop.site.full;
          # Upgrade o jedną wersję główną naraz (34 → 35); nextcloud-setup
          # uruchamia `occ upgrade` przy pierwszym starcie nowej wersji.
          package = pkgs.nextcloud35;

          database.createLocally = true;

          config.dbtype = "pgsql";

          configureRedis = true;
          maxUploadSize = "2G";

          # PHP-FPM pool tuning for RPi4 (4 GB RAM).
          # Default max_children=120 is absurd for 4GB — each child is ~55 MB,
          # so 120 children = 6.6 GB potential allocation. Under memory
          # pressure (RPi4 typically runs with <200 MB free), PHP-FPM cannot
          # spawn new children for upload processing, causing uploads to fail
          # silently. 24 children × 55 MB = ~1.3 GB — fits comfortably.
          # ondemand: prywatna instancja przez większość czasu stoi bezczynnie,
          # więc nie trzymamy w RAM-ie zapasowych workerów.
          poolSettings = {
            pm = "ondemand";
            "pm.max_children" = 24;
            "pm.max_requests" = 500;
            "pm.process_idle_timeout" = "30s";
          };

          phpOptions = {
            "opcache.interned_strings_buffer" = "16";
          };

          # Za tunelem: Cloudflare kończy TLS, a cloudflared przekazuje HTTP
          # z localhost.
          # - overwriteprotocol: bez tego Nextcloud generuje linki http://
          #   (psuło logowanie z aplikacji mobilnej);
          # - overwrite.cli.url: occ, cron i maile nie mają żądania
          #   z publicznym adresem, więc bez niego linki wskazują localhost;
          # - trusted_proxies: cały ruch z tunelu przychodzi z pętli zwrotnej;
          #   zaufanie jej każe brać adres klienta z X-Forwarded-For, więc logi
          #   i ochrona przed brute force widzą prawdziwe IP, nie 127.0.0.1.
          settings = {
            maintenance_window_start = 1;
            overwriteprotocol = "https";
            "overwrite.cli.url" = "https://${customTop.site.full}";
            trusted_proxies = [
              "127.0.0.1"
              "::1"
            ];
          };
        };

        # HSTS Header
        nginx.virtualHosts."${customTop.site.full}".extraConfig = ''
          add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
        '';

        # PostgreSQL performance tuning for RPi4
        postgresql.settings = {
          shared_buffers = "128MB";
          work_mem = "4MB";
          maintenance_work_mem = "32MB";
          effective_cache_size = "256MB";
        };
      };
    };
}

# Nextcloud 35 pod domeną główną (customTop.domain): PostgreSQL i Redis
# lokalnie, PHP-FPM i PostgreSQL dostrojone do 4 GB RAM RPi; dostępny
# wyłącznie przez Cloudflare Tunnel (cloudflared → nginx :80).
#
# Dostęp z LAN-u celowo odcięty: nginx słucha na :80 tylko na localhost
# (defaultListenAddresses w network.nix) i nie ma mDNS (avahi). Ten vhost
# serwuje też /.well-known/matrix/client (matrix.nix).
#
# nixpkgs instaluje bez admina (`occ maintenance:install --disable-admin-user`):
# po świeżej instalacji `sudo nextcloud-occ user:add <nazwa>` i
# `sudo nextcloud-occ group:adduser admin <nazwa>`. Hasło istniejącego `admin`
# jest tylko kopią w `nextcloud-adminpass.age` (żaden host go nie deklaruje).
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
          hostName = customTop.domain;
          # Upgrade o jedną wersję główną naraz (34 → 35); nextcloud-setup
          # uruchamia `occ upgrade` przy pierwszym starcie nowej wersji.
          package = pkgs.nextcloud35;

          database.createLocally = true;

          config.dbtype = "pgsql";

          configureRedis = true;
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

          # Za tunelem (TLS w Cloudflare, HTTP z localhost):
          # - overwriteprotocol: inaczej linki http:// (psuło logowanie
          #   z aplikacji mobilnej);
          # - overwrite.cli.url: occ, cron i maile nie znają publicznego adresu
          #   (inaczej linki na localhost);
          # - trusted_proxies: ruch z tunelu przychodzi z pętli zwrotnej, a jej
          #   zaufanie każe brać adres klienta z X-Forwarded-For, więc logi
          #   i ochrona przed brute force widzą prawdziwe IP, nie 127.0.0.1.
          settings = {
            maintenance_window_start = 1;
            overwriteprotocol = "https";
            "overwrite.cli.url" = "https://${customTop.domain}";
            trusted_proxies = [
              "127.0.0.1"
              "::1"
            ];
          };
        };

        nginx.virtualHosts.${customTop.domain}.extraConfig = ''
          add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
        '';

        postgresql.settings = {
          shared_buffers = "128MB";
          work_mem = "4MB";
          maintenance_work_mem = "32MB";
          effective_cache_size = "256MB";
        };
      };
    };
}

# Cloudflare Tunnel `raspberry-pi-4`: jedyna droga z internetu do usług RPi
# (Nextcloud, ttyd, SSH, Gitea, Matrix); nieznane nazwy hostów dostają 404.
# Mapa (ingress niżej): <domena> → nginx :80 (Nextcloud),
# ttyd. → nginx :8083 (Basic Auth przed ttyd), ssh. → :22,
# git. → :3000 (Gitea), matrix. → :6167 (continuwuity).
#
# Usługi WWW nie mają portów otwartych w firewallu, a TLS kończy się
# w Cloudflare. Ruch z tunelu dochodzi do usług z 127.0.0.1/::1, więc adres
# klienta widać tylko w nagłówkach X-Forwarded-For/CF-Connecting-IP
# (Nextcloud trusted_proxies, limit żądań ttyd), a sshd widzi logowania przez
# ssh.<domena> jako lokalne (`cloudflared access ssh` po stronie klienta,
# base-ssh).
#
# Sprawdzenie: `systemctl status cloudflared-tunnel-raspberry-pi-4`,
# `journalctl -u cloudflared-tunnel-raspberry-pi-4 -b | grep -i registered`
# (połączenia z protocol=http2).
{ customTop, ... }:
{
  flake.modules.nixos.rpi-cloudflared =
    { config, ... }:
    let
      tunnelName = "raspberry-pi-4";
    in
    {
      # Moduł cloudflared czyta plik przez LoadCredential (DynamicUser),
      # więc wystarcza domyślne root:root 0400.
      age.secrets.cloudflared-tunnel.file = customTop.secretsDir + "/cloudflared-tunnel.age";

      # Bez sieci cloudflared kończy się zaraz po starcie (brak DNS dla
      # rekordów SRV argotunnel.com). Przy domyślnych 100 ms między
      # restartami 5 startów mieściło się w 2 s, czyli w StartLimitBurst
      # (5 w 10 s), i systemd porzucał usługę na stałe — tunel nie wracał
      # nawet po podłączeniu kabla. Co 5 s w 10 s mieszczą się najwyżej 3.
      systemd.services."cloudflared-tunnel-${tunnelName}".serviceConfig.RestartSec = 5;

      services.cloudflared = {
        enable = true;
        tunnels = {
          ${tunnelName} = {
            # Force HTTP/2 over TCP instead of the default QUIC (UDP).
            # QUIC connections died in clusters ("Failed to dial a quic
            # connection … timeout: no recent network activity"), sometimes
            # taking all 4 tunnel connections down at once → every site
            # behind the tunnel intermittently unreachable. Classic QUIC/UDP
            # path issue (e.g. MTU blackhole on the uplink). HTTP/2 is
            # TCP-based and unaffected; perf difference is negligible here.
            protocol = "http2";
            credentialsFile = config.age.secrets.cloudflared-tunnel.path;
            default = "http_status:404";
            ingress = {
              # Nextcloud — longer timeouts for photo uploads through tunnel.
              # Default connectTimeout (30s) was too short: cloudflared canceled
              # upload streams mid-transfer ("stream canceled by remote with
              # error code 0"). 300s gives PHP-FPM enough time to process
              # large files even under memory pressure.
              "${customTop.site.full}" = {
                service = "http://localhost:80";
                originRequest = {
                  connectTimeout = "300s";
                  keepAliveConnections = 10;
                  keepAliveTimeout = "2m";
                };
              };
              # nginx z Basic Auth przed ttyd (modules/hosts/raspberry-pi-4/ttyd.nix)
              "ttyd.${customTop.site.full}" = "http://localhost:8083";
              "ssh.${customTop.site.full}" = "ssh://localhost:22";
              "git.${customTop.site.full}" = "http://localhost:3000";
              # continuwuity (modules/hosts/raspberry-pi-4/matrix.nix)
              "matrix.${customTop.site.full}" = "http://localhost:6167";
            };
          };
        };
      };
    };
}

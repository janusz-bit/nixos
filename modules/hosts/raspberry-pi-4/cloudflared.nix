# Cloudflare Tunnel `raspberry-pi-4`: jedyna droga z internetu do usług RPi
# (Nextcloud, Trilium, ttyd, SSH, Gitea, Matrix); nieznane nazwy hostów
# dostają 404. Mapa (ingress niżej): <domena> → nginx :80 (Nextcloud),
# notes. → :8081 (Trilium), ttyd. → nginx :8083 (Basic Auth przed ttyd),
# ssh. → :22, git. → :3000 (Gitea), matrix. → :6167 (continuwuity).
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
      inherit (customTop) domain;
      tunnelName = "raspberry-pi-4";
      localHttp = port: "http://localhost:${toString port}";
    in
    {
      # Moduł czyta plik przez LoadCredential (DynamicUser), więc wystarcza
      # domyślne root:root 0400.
      age.secrets.cloudflared-tunnel.file = customTop.secretsDir + "/cloudflared-tunnel.age";

      # Bez sieci (brak DNS) cloudflared kończy się zaraz po starcie. Przy
      # domyślnych 100 ms 5 restartów mieściło się w StartLimitBurst (5 w 10 s)
      # i systemd porzucał tunel na stałe; co 5 s w 10 s mieszczą się najwyżej 3.
      systemd.services."cloudflared-tunnel-${tunnelName}".serviceConfig.RestartSec = 5;

      services.cloudflared = {
        enable = true;
        tunnels.${tunnelName} = {
          # HTTP/2 po TCP zamiast domyślnego QUIC: połączenia QUIC padały
          # grupami ("no recent network activity"), czasem wszystkie 4 naraz,
          # i strony za tunelem znikały (problem ścieżki UDP, np. MTU).
          protocol = "http2";
          credentialsFile = config.age.secrets.cloudflared-tunnel.path;
          default = "http_status:404";
          ingress = {
            # Domyślne connectTimeout 30 s zrywało uploady zdjęć ("stream
            # canceled by remote"); 300 s daje PHP-FPM czas przy presji pamięci.
            ${domain} = {
              service = localHttp 80;
              originRequest = {
                connectTimeout = "300s";
                keepAliveConnections = 10;
                keepAliveTimeout = "2m";
              };
            };
            "notes.${domain}" = localHttp config.services.trilium-server.port;
            # nginx z Basic Auth przed ttyd (ttyd.nix).
            "ttyd.${domain}" = localHttp 8083;
            "ssh.${domain}" = "ssh://localhost:22";
            "git.${domain}" = localHttp config.services.gitea.settings.server.HTTP_PORT;
            "matrix.${domain}" = localHttp (
              builtins.head config.services.matrix-continuwuity.settings.global.port
            );
          };
        };
      };
    };
}

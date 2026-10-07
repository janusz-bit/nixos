{ customTop, ... }:
{
  flake.modules.nixos.cloudflared =
    { config, lib, ... }:
    {
      # Moduł cloudflared czyta plik przez LoadCredential (DynamicUser),
      # więc wystarcza domyślne root:root 0400.
      age.secrets.cloudflared-tunnel.file = customTop.secretsDir + "/cloudflared-tunnel.age";
      services.cloudflared = {
        enable = true;
        tunnels = {
          "raspberry-pi-4" = {
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
            # Jawne 127.0.0.1 zamiast localhost: nginx (Nextcloud) i usługi
            # słuchają tylko na IPv4 pętli zwrotnej, a localhost rozwiązuje się
            # najpierw do ::1 (odrzucone połączenie i ponowna próba).
            # Duże uploady Nextcloud działają dzięki dzieleniu na kawałki przez
            # klientów — limit Cloudflare to 100 MB na żądanie i 100 s na
            # odpowiedź; connectTimeout dotyczy tylko nawiązania TCP do origin.
            ingress = {
              "${customTop.site.full}" = {
                service = "http://127.0.0.1:80";
                originRequest = {
                  keepAliveConnections = 10;
                  keepAliveTimeout = "2m";
                };
              };
              "chat.${customTop.site.full}" = {
                service = "http://127.0.0.1:8080";
                originRequest = {
                  keepAliveConnections = 10;
                  keepAliveTimeout = "2m";
                };
              };
              "notes.${customTop.site.full}" = "http://127.0.0.1:8081";
              # nginx z Basic Auth przed ttyd (modules/hosts/raspberry-pi-4/ttyd.nix)
              "ttyd.${customTop.site.full}" = "http://127.0.0.1:8083";
              "ssh.${customTop.site.full}" = "ssh://127.0.0.1:22";
              "git.${customTop.site.full}" = "http://127.0.0.1:3000";
            };
          };
        };
      };

      # Jedyne wejście z internetu i ścieżka administracyjna (ssh.*): moduł
      # daje Restart=on-failure z domyślnym limitem 5 startów / 10 s, po
      # którym systemd przestaje próbować na zawsze (np. błąd DNS przy
      # starcie) — wtedy wszystkie strony i SSH leżą do fizycznego dostępu.
      systemd.services."cloudflared-tunnel-raspberry-pi-4" = {
        startLimitIntervalSec = 0;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "5s";
          # Utwardzenie bez ograniczania wywołań systemowych i rodzin adresów
          # (te mogłyby odciąć tunel, a jego awaria = utrata zdalnego
          # dostępu); DynamicUser już daje ProtectSystem/ProtectHome/PrivateTmp.
          CapabilityBoundingSet = "";
          PrivateDevices = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          LockPersonality = true;
          UMask = "0077";
        };
      };
    };
}

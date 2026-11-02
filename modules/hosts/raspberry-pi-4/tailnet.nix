# Własny tailnet RPi: serwer koordynacyjny headscale (hs.<domena> przez
# Cloudflare Tunnel, cloudflared.nix), RPi jako jego węzeł (tailscaled)
# i HTTPS dla usług dostępnych tylko z tailnetu (Nextcloud, t3code).
#
# Usługa tailnetu to vhost nginx z `listenAddresses = [ tailnetAddress ]`
# (nextcloud.nix, t3code.nix). Ten moduł dla każdego takiego vhosta:
# - dopisuje rekord A do MagicDNS (`dns.extra_records`), więc nazwa
#   <usługa>.<domena> rozwiązuje się tylko u klientów tailnetu i publiczny
#   DNS nie zna jej wcale;
# - wystawia certyfikat Let's Encrypt przez wyzwanie DNS-01 w Cloudflare
#   (headscale nie ma `tailscale cert`); DNS-01 wymaga tylko rekordu TXT,
#   który lego sam dodaje i usuwa.
# Port 443 jest otwarty wyłącznie na tailscale0, a nginx wiąże się z adresem
# tailnetu RPi (tailnetAddress), więc z LAN-u i internetu usługi nie widać.
# `ip_nonlocal_bind` pozwala nginxowi wstać przed podniesieniem tailscale0
# (np. gdy headscale jest chwilowo nieosiągalny); bez niego padłby też lokalny
# vhost Matrixa.
#
# DERP: domyślna mapa Tailscale. Przekaźnik widzi tylko ruch zaszyfrowany
# WireGuardem; własny DERP wymagałby UDP 3478 otwartego w firewallu.
# tailscaled nie zarządza DNS RPi (`--accept-dns=false`), żeby nie walczyć
# z NetworkManagerem o /etc/resolv.conf.
#
# Adres tailnetAddress to pierwszy adres przydzielony przez headscale; jeśli
# RPi dostanie inny (`tailscale ip -4`), popraw go tutaj.
#
# Jednorazowo po pierwszym wdrożeniu (stan headscale jest w
# /var/lib/headscale, nie w gicie):
#   sudo headscale users create <nazwa>; sudo headscale users list   # ID
#   sudo headscale preauthkeys create --user <ID> --expiration 1h
#   cd modules/_secrets && agenix -e headscale-authkey.age           # klucz
#   (git add, update) tailscaled-autoconnect loguje RPi do tailnetu.
# Telefon i laptop: Tailscale z `--login-server=https://hs.<domena>`, potem
# `sudo headscale nodes register --user <ID> --key <klucz z klienta>`.
# Token Cloudflare do ACME: Zone / DNS / Edit dla strefy <domena>,
#   cd modules/_secrets && agenix -e acme-cloudflare.age   (sam token).
#
# Sprawdzenie: `systemctl status headscale tailscaled`, `tailscale status`,
# `sudo headscale nodes list`, `systemctl status acme-nextcloud.<domena>`,
# z klienta tailnetu `curl -I https://nextcloud.<domena>`.
_: {
  flake.modules.nixos.rpi-tailnet =
    { config, lib, ... }:
    let
      inherit (config.customTop) domain secretsDir;
      address = config.customBot.tailnetAddress;
      serverUrl = "https://hs.${domain}";

      authKeyFile = secretsDir + "/headscale-authkey.age";
      hasAuthKey = builtins.pathExists authKeyFile;
      acmeSecretFile = secretsDir + "/acme-cloudflare.age";
      hasAcmeSecret = builtins.pathExists acmeSecretFile;

      tailnetVhosts = lib.filterAttrs (
        _: vhost: vhost.listenAddresses == [ address ]
      ) config.services.nginx.virtualHosts;
    in
    lib.mkMerge [
      {
        warnings =
          lib.optionals (!hasAuthKey) [
            "rpi-tailnet: brak modules/_secrets/headscale-authkey.age w gicie — RPi nie dołączy do tailnetu (kroki w nagłówku tailnet.nix)."
          ]
          ++ lib.optionals (!hasAcmeSecret) [
            "rpi-tailnet: brak modules/_secrets/acme-cloudflare.age w gicie — usługi tailnetu zostają na certyfikacie samopodpisanym (kroki w nagłówku tailnet.nix)."
          ];

        customBot.tailnetAddress = "100.64.0.1";

        # headscale: sieć dochodzi do niego tunelem, tailscaled trzyma łączność
        # wychodzącą z tailnetem, t3code (t3code.nix) wystawia nginx.
        customBot.lockdownServices = [
          "headscale"
          "tailscaled"
        ];

        services.headscale = {
          enable = true;
          address = "127.0.0.1";
          port = 8085;
          settings = {
            server_url = serverUrl;
            dns = {
              base_domain = "ts.${domain}";
              nameservers.global = config.networking.nameservers;
              extra_records = lib.mapAttrsToList (name: _: {
                inherit name;
                type = "A";
                value = address;
              }) tailnetVhosts;
            };
          };
        };

        services.tailscale = {
          enable = true;
          extraUpFlags = [
            "--login-server=${serverUrl}"
            "--accept-dns=false"
          ];
        };

        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];
        boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

        security.acme = {
          acceptTerms = true;
          defaults = {
            inherit (config.customTop) email;
            dnsProvider = "cloudflare";
          };
        };
      }

      (lib.mkIf hasAcmeSecret {
        age.secrets.acme-cloudflare.file = acmeSecretFile;
        security.acme.defaults.credentialFiles.CLOUDFLARE_DNS_API_TOKEN_FILE =
          config.age.secrets.acme-cloudflare.path;
      })

      (lib.mkIf hasAuthKey {
        age.secrets.headscale-authkey.file = authKeyFile;
        services.tailscale.authKeyFile = config.age.secrets.headscale-authkey.path;
      })
    ];
}

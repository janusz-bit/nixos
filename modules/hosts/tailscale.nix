# Tailscale na laptopie i RPi: hostowany serwer koordynacji, wyłącznie
# połączenia wychodzące, więc działa za CGNAT (headscale za tunelem Cloudflare
# nie może, AGENTS.md). Tailnet służy przeglądarce laptopa i telefonu do T3 Code
# na RPi (rpi-t3code, Tailscale Serve).
#
# - --netfilter-mode=nodivert na obu hostach: domyślne `on` wstawia na początek
#   INPUT `-i tailscale0 -j ACCEPT`, z którym tailnet omijałby nixos-fw (także
#   SSH tylko z LAN-u). Tailnet dociera więc tylko do portów Serve, które
#   obsługuje netstack w procesie tailscaled; resztę blokuje nixos-fw.
# - DNS: laptop ma systemd-resolved, więc MagicDNS dostaje tylko domenę tailnetu
#   (split DNS na łączu tailscale0), a nazwy *.ts.net rozwiązują się tylko przez
#   niego. RPi: --accept-dns=false, bo bez resolved MagicDNS przejąłby DNS
#   całego hosta, a lockdown, który zatrzymuje tailscaled, odciąłby wtedy DNS
#   cloudflared.
# - Pierwsze `tailscale up` (bez ControlURL) nie sprawdza ustawień i nadpisuje je
#   domyślnymi, a extraSetFlags działa tylko przy starcie tailscaled, więc
#   tailscale-prefs wymusza je po każdym zalogowaniu (`tailscale wait`).
# - Żadne konto nie dostaje --operator: operator mógłby włączyć Funnel, czyli
#   wystawić usługi do internetu.
# - lockdown zatrzymuje tailscaled (własne połączenia wychodzące).
#
# Jednorazowo na każdym hoście `sudo tailscale up --netfilter-mode=nodivert`
# (RPi także --accept-dns=false), link logowania otworzyć w przeglądarce, na
# obu hostach to samo konto. W panelu Tailscale: wyłączyć wygasanie klucza RPi,
# włączyć MagicDNS i HTTPS Certificates.
#
# Sprawdzenie: `tailscale status`, `systemctl status tailscaled tailscale-prefs`,
# `sudo iptables -S INPUT` (bez skoku do ts-input).
_:
let
  tailscaleWith =
    setFlags:
    { config, lib, ... }:
    let
      tailscale = lib.getExe config.services.tailscale.package;
    in
    {
      services.tailscale.enable = true;

      # BindsTo z After: przy lockdown (tailscaled pominięty) też się nie
      # uruchamia. Typ simple, bo `tailscale wait` czeka do zalogowania, a
      # oneshot zatrzymałby na tym przełączanie konfiguracji.
      systemd.services.tailscale-prefs = {
        description = "Tailscale: ustawienia wymuszane po zalogowaniu";
        wantedBy = [ "tailscaled.service" ];
        bindsTo = [ "tailscaled.service" ];
        after = [ "tailscaled.service" ];
        script = ''
          ${tailscale} wait
          ${tailscale} set ${lib.escapeShellArgs setFlags}
        '';
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "1min";
        };
      };

      customBot.lockdownServices = [ "tailscaled" ];
    };
in
{
  flake.modules.nixos.nixos-tailscale = tailscaleWith [ "--netfilter-mode=nodivert" ];

  flake.modules.nixos.rpi-tailscale = tailscaleWith [
    "--accept-dns=false"
    "--netfilter-mode=nodivert"
  ];
}

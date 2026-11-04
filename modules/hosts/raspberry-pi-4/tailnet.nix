# RPi jako węzeł tailnetu Tailscale (serwer koordynacyjny Tailscale, nie
# własny headscale). Jedyną usługą RPi w tailnecie jest t3code (t3code.nix,
# `tailscale serve`); reszta idzie przez Cloudflare Tunnel (cloudflared.nix).
#
# Dlaczego nie headscale: protokół kontrolny Tailscale (POST /ts2021
# z `Upgrade: tailscale-control-protocol`) nie przechodzi przez Cloudflare
# Proxy ani Tunnel (dokumentacja headscale, juanfont/headscale#1468), a łącze
# za CGNAT nie pozwala wystawić go inaczej. Klucze węzłów rozdaje więc
# Tailscale; Tailnet Lock (`tailscale lock init` na laptopie) wymaga, żeby
# każdy nowy węzeł podpisało zaufane urządzenie.
#
# Firewall nie otwiera żadnego portu na tailscale0 i interfejs nie jest
# zaufany: `tailscale serve` obsługuje ruch w tailscaled, zanim trafi do
# jądra. tailscaled nie zarządza DNS RPi (`--accept-dns=false`), żeby nie
# walczyć z NetworkManagerem o /etc/resolv.conf.
#
# Jednorazowo (stan węzła jest w /var/lib/tailscale, nie w gicie):
# - panel Tailscale, DNS: MagicDNS i HTTPS Certificates włączone (certyfikat
#   *.ts.net dla `tailscale serve`);
# - na RPi `sudo tailscale up --reset --accept-dns=false`, otwórz wypisany
#   adres i zaloguj się (`--reset` zapomina wcześniejsze ustawienia `up`,
#   np. inny serwer logowania);
# - panel, Machines → raspberry-pi-4 → Disable key expiry (inaczej węzeł
#   wypada z tailnetu po 180 dniach).
#
# Sprawdzenie: `tailscale status`, `tailscale debug prefs | grep CorpDNS`
# (false), `systemctl status tailscaled tailscaled-set`.
_: {
  flake.modules.nixos.rpi-tailnet = {
    # Wychodząca łączność z tailnetem jest łącznością "z sieci": lockdown ją
    # ucina.
    customBot.lockdownServices = [ "tailscaled" ];

    services.tailscale = {
      enable = true;
      # extraUpFlags działają tylko z authKeyFile; extraSetFlags stosuje unit
      # tailscaled-set przy każdym starcie tailscaled.
      extraSetFlags = [ "--accept-dns=false" ];
    };
  };
}

# Laptop jako klient tailnetu Tailscale (rpi-tailnet): z laptopa działa
# t3code z RPi, dostępny tylko z tailnetu pod
# https://raspberry-pi-4.<tailnet>.ts.net (t3code.nix). Nazwy MagicDNS
# rozwiązuje systemd-resolved (włącza go mullvad-vpn, desktop/apps.nix),
# a tailscaled przyjmuje DNS tailnetu.
#
# Laptop niczego w tailnecie nie wystawia: firewall nie otwiera żadnego portu
# na tailscale0, a tailscale0 nie jest zaufanym interfejsem.
#
# Jednorazowo po wdrożeniu (stan węzła jest w /var/lib/tailscale):
#   sudo tailscale up --reset     # otwórz wypisany adres i zaloguj się
#
# Sprawdzenie: `tailscale status`, `resolvectl query raspberry-pi-4.<tailnet>.ts.net`.
_: {
  flake.modules.nixos.nixos-tailnet = {
    services.tailscale.enable = true;

    # Ruch wychodzący tailnetu jest łącznością "z sieci" — lockdown go ucina.
    customBot.lockdownServices = [ "tailscaled" ];
  };
}

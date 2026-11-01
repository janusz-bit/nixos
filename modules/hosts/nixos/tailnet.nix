# Laptop jako klient własnego tailnetu (headscale na RPi, rpi-tailnet): z
# laptopa działają usługi dostępne tylko z tailnetu (nextcloud.<domena>,
# t3.<domena>), bo MagicDNS rozwiązuje je przez systemd-resolved (włącza go
# mullvad-vpn, desktop/apps.nix), a tailscaled przyjmuje DNS tailnetu.
#
# Laptop niczego w tailnecie nie wystawia: firewall nie otwiera żadnego portu
# na tailscale0, a tailscale0 nie jest zaufanym interfejsem.
#
# Jednorazowo po wdrożeniu (stan węzła jest w /var/lib/tailscale):
#   sudo tailscale up --login-server=https://hs.<domena>
#   # na RPi, z kluczem wypisanym przez klienta:
#   sudo headscale nodes register --user <ID> --key <klucz>
#
# Sprawdzenie: `tailscale status`, `resolvectl query nextcloud.<domena>`,
# `curl -I https://nextcloud.<domena>`.
_: {
  flake.modules.nixos.nixos-tailnet = {
    services.tailscale.enable = true;

    # Ruch wychodzący tailnetu jest łącznością "z sieci" — lockdown go ucina.
    customBot.lockdownServices = [ "tailscaled" ];
  };
}

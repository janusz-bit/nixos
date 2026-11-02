# Laptop jako klient własnego tailnetu (headscale na RPi, rpi-tailnet): z
# laptopa działają usługi dostępne tylko z tailnetu (nextcloud.<domena>), bo
# MagicDNS rozwiązuje je przez systemd-resolved (włącza go mullvad-vpn,
# desktop/apps.nix), a tailscaled przyjmuje DNS tailnetu.
#
# Jedyny port otwarty na tailscale0 to SSH (porty sshd), żeby z innych
# urządzeń tailnetu dało się zalogować na laptopa poza domowym LAN-em
# (base-ssh-lan przepuszcza tam tylko LAN). Wymagania sshd bez zmian: tylko
# klucze, root bez logowania; fail2ban obejmuje też logowania z tailnetu.
# tailscale0 nie jest zaufanym interfejsem. Reguła jest przypięta do
# interfejsu, więc `lockdown on` jej nie zamyka, ale zatrzymuje tailscaled
# i tailnet znika razem z nią.
#
# Jednorazowo po wdrożeniu (stan węzła jest w /var/lib/tailscale):
#   sudo tailscale up --login-server=https://hs.<domena>
#   # na RPi, z kluczem wypisanym przez klienta:
#   sudo headscale nodes register --user <ID> --key <klucz>
#
# Sprawdzenie: `tailscale status`, `resolvectl query nextcloud.<domena>`,
# `curl -I https://nextcloud.<domena>`; z innego węzła tailnetu
# `ssh <użytkownik>@nixos.ts.<domena>` (lub adres z `tailscale ip -4`),
# na laptopie `sudo iptables -S nixos-fw | grep tailscale0`.
_: {
  flake.modules.nixos.nixos-tailnet =
    { config, ... }:
    {
      services.tailscale.enable = true;

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = config.services.openssh.ports;

      # Ruch wychodzący tailnetu jest łącznością "z sieci" — lockdown go ucina.
      customBot.lockdownServices = [ "tailscaled" ];
    };
}

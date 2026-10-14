# SSH tylko z domowego LAN-u (customTop.lan.subnet): reguła iptables
# zamiast openFirewall. Laptop nie przyjmuje SSH w obcych sieciach, do
# których się podłącza; RPi nie wystawia portu 22 przez IPv6, gdzie router
# może nie filtrować ruchu przychodzącego. Tunel Cloudflare łączy się
# z sshd przez localhost, więc go to nie dotyczy. Opcjonalny: importują
# go hosty z SSH z sieci (nixos, raspberry-pi-4), nie WSL. Przed zgadywaniem
# kluczy chroni base-fail2ban.
#
# Sprawdzenie: `sudo iptables -S nixos-fw | grep 'dport 22'` (tylko z LAN-u)
# i `sudo ip6tables -S nixos-fw | grep -c 'dport 22'` (0).
{ customTop, ... }:
{
  flake.modules.nixos.base-ssh-lan = _: {
    services.openssh.openFirewall = false;
    networking.firewall.extraCommands = ''
      iptables -A nixos-fw -p tcp -s ${customTop.lan.subnet} --dport 22 -j nixos-fw-accept
    '';
  };
}

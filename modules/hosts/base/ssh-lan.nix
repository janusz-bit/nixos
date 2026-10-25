# SSH tylko z domowego LAN-u (customTop.lan.subnet): reguła iptables zamiast
# openFirewall. Laptop nie przyjmuje SSH w obcych sieciach, a port 22 nie jest
# otwarty przez IPv6, gdzie router może nie filtrować ruchu przychodzącego.
# Tunelu Cloudflare (sshd przez localhost) to nie dotyczy.
#
# Sprawdzenie: `sudo iptables -S nixos-fw | grep 'dport 22'` (tylko z LAN-u)
# i `sudo ip6tables -S nixos-fw | grep -c 'dport 22'` (0).
_: {
  flake.modules.nixos.base-ssh-lan =
    { config, ... }:
    {
      services.openssh.openFirewall = false;
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${config.customTop.lan.subnet} --dport 22 -j nixos-fw-accept
      '';
    };
}

# SSH laptopa tylko z domowego LAN-u (customTop.lan.subnet), nie z każdej
# sieci, do której się podłączy. Reguła iptables, bo networking.nftables jest
# wyłączone; przed zgadywaniem haseł chroni base-fail2ban.
# Sprawdzenie: `sudo iptables -S nixos-fw | grep 'dport 22'`.
{ customTop, ... }:
{
  flake.modules.nixos.nixos-ssh = _: {
    services.openssh.openFirewall = false;
    networking.firewall.extraCommands = ''
      iptables -A nixos-fw -p tcp -s ${customTop.lan.subnet} --dport 22 -j nixos-fw-accept
    '';
  };
}

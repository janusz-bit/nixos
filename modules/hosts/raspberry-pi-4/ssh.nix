# Dostęp SSH do RPi z domowego LAN-u (base-ssh-lan) i z tailnetu: port sshd
# otwarty na tailscale0, do którego dochodzą tylko urządzenia tailnetu
# (netfilter nodivert, hosts/tailscale.nix). Bazowe ustawienia (tylko klucze)
# daje base-ssh. Logowanie roota kluczem zostaje — to ścieżka
# administracyjna (`ssh root@raspberry-pi-4`, MagicDNS).
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.raspberry-pi-4.config.users.users.nixos.openssh.authorizedKeys.keys`
# (i `…users.users.root…`) — tylko klucze wymienione niżej;
# `sudo iptables -S nixos-fw | grep tailscale0`.
_: {
  flake.modules.nixos.rpi-ssh =
    { config, ... }:
    let
      inherit (config.customTop) keys lan;
    in
    {
      services.openssh.settings.PermitRootLogin = "prohibit-password";
      # Port na interfejsie, nie globalny: lockdown go nie zamyka (SSH zostaje),
      # a obce sieci go nie widzą.
      networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts =
        config.services.openssh.ports;
      # Headless: bez x11-ssh-askpass (zależności X11).
      programs.ssh.enableAskPassword = false;

      # Stała sieć domowa — nie banuj hostów z LAN.
      services.fail2ban.ignoreIP = [ lan.subnet ];

      users.users = {
        # Klucze roota laptopa i RPi oraz telefonu. Lista jawna, nie
        # attrValues keys.hosts: nowy odbiorca agenix nie dostaje przez to
        # logowania na RPi.
        ${config.customBot.defaultUser}.openssh.authorizedKeys.keys = [
          keys.hosts.nixos
          keys.hosts.raspberry-pi-4
          keys.users.phone
        ];
        # Klucz głównego użytkownika laptopa: `ssh root@raspberry-pi-4`.
        root.openssh.authorizedKeys.keys = [ keys.users.janusz-bit ];
      };
    };
}

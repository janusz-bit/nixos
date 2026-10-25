# Dostęp SSH do RPi. Bazowe ustawienia (tylko klucze) daje base-ssh.
# Logowanie roota kluczem zostaje — to ścieżka administracyjna przez tunel
# Cloudflare (`ssh ssh.<domena>`, `Host ssh.*` → `User root` w base-ssh).
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.raspberry-pi-4.config.users.users.nixos.openssh.authorizedKeys.keys`
# (i `…users.users.root…`) — tylko klucze wymienione niżej.
_: {
  flake.modules.nixos.rpi-ssh =
    { config, ... }:
    let
      inherit (config.customTop) keys lan;
    in
    {
      services.openssh.settings.PermitRootLogin = "prohibit-password";
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
        # Klucz głównego użytkownika laptopa: `ssh ssh.<domena>` loguje jako
        # root (tunel).
        root.openssh.authorizedKeys.keys = [ keys.users.janusz-bit ];
      };
    };
}

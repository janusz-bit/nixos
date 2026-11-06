# SSH na każdym hoście: sshd tylko z kluczami, root domyślnie bez logowania,
# agent GnuPG i ssh-askpass.
#
# Wartości z mkDefault nadpisuje raspberry-pi-4: dopuszcza roota kluczem
# ("prohibit-password", to jego ścieżka administracyjna) i wyłącza
# ssh-askpass (headless, x11-ssh-askpass ciągnie zależności X11).
# Laptop i RPi zawężają dodatkowo port 22 do domowego LAN-u (base-ssh-lan),
# RPi otwiera go też w tailnecie (rpi-ssh).
#
# Sprawdzenie: `sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication)'`.
_: {
  flake.modules.nixos.base-ssh =
    { lib, ... }:
    {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = lib.mkDefault "no";
        };
      };

      programs = {
        ssh.enableAskPassword = lib.mkDefault true;
        gnupg.agent.enable = true;
      };
    };
}

# SSH na każdym hoście: sshd tylko z kluczami, root domyślnie bez logowania,
# agent GnuPG, ssh-askpass oraz wpis `Host ssh.*` w ssh_config, przez który
# `ssh ssh.<domena>` loguje się jako root na RPi przez Cloudflare Access.
#
# Wartości z mkDefault nadpisuje raspberry-pi-4: dopuszcza roota kluczem
# ("prohibit-password", to jego ścieżka administracyjna przez tunel) i
# wyłącza ssh-askpass (headless, x11-ssh-askpass ciągnie zależności X11).
# Laptop i RPi zawężają dodatkowo port 22 do domowego LAN-u (base-ssh-lan).
#
# Sprawdzenie: `sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication)'`;
# `ssh -G ssh.<domena> | grep -E '^(user|proxycommand) '`.
_: {
  flake.modules.nixos.base-ssh =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cloudflared ];

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = lib.mkDefault "no";
        };
      };

      programs = {
        ssh = {
          enableAskPassword = lib.mkDefault true;
          extraConfig = ''
            Host ssh.*
              User root
              ProxyCommand cloudflared access ssh --hostname %h
          '';
        };
        gnupg.agent.enable = true;
      };
    };
}

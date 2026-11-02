# SSH na każdym hoście: sshd tylko z kluczami, root domyślnie bez logowania,
# agent GnuPG, ssh-askpass oraz wpisy w ssh_config: `Host ssh.*`, przez który
# `ssh ssh.<domena>` loguje się jako root na RPi przez Cloudflare Access,
# i `Host laptop-remote`, który przez ten sam tunel i RPi jako jump host
# (ProxyJump) dochodzi do sshd laptopa w domowym LAN-ie. Laptop widzi wtedy
# połączenie z adresu RPi, czyli z LAN-u, który base-ssh-lan przepuszcza;
# klucz użytkownika musi być na liście laptopa (hosts/nixos/default.nix).
#
# Wartości z mkDefault nadpisuje raspberry-pi-4: dopuszcza roota kluczem
# ("prohibit-password", to jego ścieżka administracyjna przez tunel) i
# wyłącza ssh-askpass (headless, x11-ssh-askpass ciągnie zależności X11).
# Laptop i RPi zawężają dodatkowo port 22 do domowego LAN-u (base-ssh-lan).
#
# Sprawdzenie: `sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication)'`;
# `ssh -G ssh.<domena> | grep -E '^(user|proxycommand) '`;
# `ssh -G laptop-remote | grep -E '^(user|hostname|proxyjump) '`; poza domem
# `ssh laptop-remote`.
_: {
  flake.modules.nixos.base-ssh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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

            Host laptop-remote
              HostName ${config.customTop.lan.laptop}
              User ${config.customTop.users.laptop}
              ProxyJump root@ssh.${config.customTop.domain}
          '';
        };
        gnupg.agent.enable = true;
      };
    };
}

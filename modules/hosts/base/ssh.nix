_: {
  flake.modules.nixos.base-ssh =
    { lib, ... }:
    {
      services.openssh = {
        enable = true;
        settings = {
          # require public key authentication for better security
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          # raspberry-pi-4 nadpisuje na "prohibit-password" (logowanie roota
          # kluczem przez tunel Cloudflare to tam ścieżka administracyjna).
          PermitRootLogin = lib.mkDefault "no";
        };
      };

      programs = {
        ssh = {
          startAgent = false;
          # Headless RPi wyłącza (x11-ssh-askpass ciągnie zależności X11).
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

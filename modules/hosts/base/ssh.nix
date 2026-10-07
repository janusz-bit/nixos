{ customTop, ... }:
{
  flake.modules.nixos.base-ssh =
    { lib, ... }:
    {
      services.openssh = {
        # WSL wyłącza (brak kluczy i działającej zapory).
        enable = lib.mkDefault true;
        settings = {
          # require public key authentication for better security
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          # raspberry-pi-4 nadpisuje na "prohibit-password" (logowanie roota
          # kluczem przez tunel Cloudflare to tam ścieżka administracyjna).
          PermitRootLogin = lib.mkDefault "no";
          # Każdy klient tunelu Cloudflare (ssh.*) łączy się z pętli zwrotnej:
          # kary PerSourcePenalties (domyślne w OpenSSH ≥ 9.8) za kilka
          # nieudanych prób odcinałyby wszystkich naraz, łącznie ze ścieżką
          # administracyjną. Uwierzytelnianie i tak jest wyłącznie kluczem.
          PerSourcePenaltyExemptList = "127.0.0.1/32,::1/128";
          # Krótsze okno nieuwierzytelnionych połączeń (wspólne MaxStartups).
          LoginGraceTime = 30;
        };
      };

      programs = {
        ssh = {
          startAgent = false;
          # Headless RPi wyłącza (x11-ssh-askpass ciągnie zależności X11).
          enableAskPassword = lib.mkDefault true;
          # Dokładna nazwa zamiast `Host ssh.*`, który przejmował też obce
          # hosty (ssh.github.com na porcie 443, ssh.dev.azure.com).
          extraConfig = ''
            Host ssh.${customTop.site.full}
              User root
              ProxyCommand cloudflared access ssh --hostname %h
          '';
        };
        gnupg.agent.enable = true;
      };
    };
}

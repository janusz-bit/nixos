{ customTop, ... }:
{
  flake.modules.nixos.ttyd-web-terminal =
    {
      config,
      pkgs,
      ...
    }:
    {
      # Web terminal (ttyd) — dostęp przez https://terminal.janusz-bit.com
      # (cloudflared tunnel, patrz cloudflared.nix). Uwierzytelnianie:
      # HTTP basic auth z hasłem w agenix (ttyd-pass.age). ttyd słucha
      # wyłącznie na loopback (interface "lo"), więc firewall nie musi
      # otwierać żadnego portu — jedyna droga to tunel Cloudflare.
      age.secrets.ttyd-pass = {
        file = customTop.secretsDir + "/ttyd-pass.age";
        owner = "root";
        group = "root";
        mode = "0440";
      };

      services.ttyd = {
        enable = true;
        port = 7681;
        interface = "lo"; # tylko localhost — dostęp wyłącznie przez tunel
        writeable = true;
        username = "janusz";
        passwordFile = config.age.secrets.ttyd-pass.path;
        # Login shell domyślnego użytkownika (wheel → sudo działa).
        # base exec-uje fish dla interaktywnego basha, więc po połączeniu
        # dostajesz fish jak w zwykłym terminalu.
        user = config.customBot.defaultUser;
        entrypoint = [
          "${pkgs.bash}/bin/bash"
          "-l"
        ];
        clientOptions = {
          fontSize = "16";
        };
      };
    };
}

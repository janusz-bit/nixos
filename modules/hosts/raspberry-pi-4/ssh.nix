# Dostęp SSH do RPi. Bazowe ustawienia (tylko klucze) daje base-ssh.
# Logowanie roota kluczem zostaje — to ścieżka administracyjna przez tunel
# Cloudflare (`ssh ssh.<domena>`, `Host ssh.*` → `User root` w base-ssh).
# Użytkownik wpuszcza klucze roota hostów (laptop, RPi) i telefonu.
{ customTop, ... }:
{
  flake.modules.nixos.rpi-ssh =
    { config, ... }:
    let
      inherit (customTop) keys;
    in
    {
      services.openssh.settings.PermitRootLogin = "prohibit-password";
      # Headless: bez x11-ssh-askpass (zależności X11).
      programs.ssh.enableAskPassword = false;

      # Stała sieć domowa — nie banuj hostów z LAN.
      services.fail2ban.ignoreIP = [ customTop.lan.subnet ];

      users.users = {
        # Klucze roota laptopa i RPi oraz telefonu (SSH z komórki).
        ${config.customBot.defaultUser}.openssh.authorizedKeys.keys = builtins.attrValues keys.hosts ++ [
          keys.users.phone
        ];
        # Twój klucz z laptopa (`ssh ssh.<domena>` loguje się jako root).
        root.openssh.authorizedKeys.keys = [ keys.users.janusz-bit ];
      };
    };
}

# Aplikacje startujące przy logowaniu do Plasmy każdego użytkownika hosta,
# deklaratywnie (Ustawienia → Autostart piszą do ~/.config/autostart, poza
# flake'iem): makeAutostartItem kopiuje plik .desktop pakietu do etc/xdg/autostart
# profilu systemu (/run/current-system/sw); `name` to nazwa pliku
# z share/applications bez .desktop, nie nazwa pakietu.
# Sprawdzenie po zalogowaniu: systemctl --user list-units 'app-*@autostart.service'
_: {
  flake.modules.nixos.desktop-autostart =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.makeAutostartItem {
          name = "element-desktop";
          package = pkgs.element-desktop;
          appendExtraArgs = [ "--hidden" ];
        })
      ];
    };
}

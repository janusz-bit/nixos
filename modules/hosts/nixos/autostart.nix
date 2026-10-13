# Aplikacje uruchamiane przy logowaniu do Plasmy. makeAutostartItem kopiuje
# plik .desktop pakietu do etc/xdg/autostart (-> /run/current-system/sw/etc/
# xdg/autostart), który Plasma 6 odpala przez systemd-xdg-autostart-generator;
# `name` to nazwa pliku z share/applications bez .desktop, nie nazwa pakietu.
# Deklaratywnie zamiast Ustawień systemowych -> Autostart (te piszą do
# ~/.config/autostart, poza flake'iem); wpis obowiązuje każdego użytkownika
# z sesją graficzną na tym hoście.
# Sprawdzenie po zalogowaniu: systemctl --user list-units 'app-*@autostart.service'
_: {
  flake.modules.nixos.nixos-autostart =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.makeAutostartItem {
          name = "element-desktop";
          package = pkgs.element-desktop;
          # Start zminimalizowany do zasobnika zamiast okna na pulpicie.
          appendExtraArgs = [ "--hidden" ];
        })
      ];
    };
}

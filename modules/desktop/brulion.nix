# Brulion (github:janusz-bit/brulion) — notatki w Markdownie offline-first
# (dziennik i outliner, kalendarz, przypomnienia z alarmami) przez moduł
# programs.brulion z flake'a aplikacji. Przypomnienia odpala tylko działający
# program, więc autostart uruchamia go przy logowaniu schowanego w zasobniku
# (`brulion --hidden`, wpis /etc/xdg/autostart/io.github.januszbit.brulion.desktop
# z modułu, a nie desktop/autostart.nix). Brulion nie ma cache: pierwszy build
# kompiluje go lokalnie (kilka minut, z testami ctest).
# Sprawdzenie po zalogowaniu:
# systemctl --user status app-io.github.januszbit.brulion@autostart.service
{ inputs, ... }:
{
  flake.modules.nixos.desktop-brulion = {
    imports = [ inputs.brulion.nixosModules.default ];

    programs.brulion = {
      enable = true;
      autostart = true;
    };
  };
}

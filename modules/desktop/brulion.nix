# Brulion: notatki w Markdownie offline-first z przypomnieniami, przez moduł
# programs.brulion z flake'a aplikacji. Przypomnienia odpala tylko działający
# program, więc autostart modułu uruchamia go przy logowaniu w zasobniku.
# Brulion nie ma cache: pierwszy build kompiluje go lokalnie (kilka minut).
#
# Sprawdzenie: systemctl --user status app-io.github.januszbit.brulion@autostart.service
{ inputs, ... }:
{
  flake.modules.nixos.desktop-brulion = _: {
    imports = [ inputs.brulion.nixosModules.default ];

    programs.brulion = {
      enable = true;
      autostart = true;
    };
  };
}

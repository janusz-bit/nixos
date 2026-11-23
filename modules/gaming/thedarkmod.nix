# The Dark Mod: gra (pakiet lokalny thedarkmod, FHS) i wpis w menu, który
# uruchamia ją przez gamemoderun, więc na hybrydzie PRIME idzie na dGPU
# z profilem performance (gaming/gamemode.nix). Pierwszy start otwiera
# oficjalny instalator, który pobiera grę do ~/Games/darkmod; `tdm-installer`
# uruchamia go ponownie (aktualizacja gry, inne wydania).
#
# Sprawdzenie: w konsoli gry (~) `com_showFPS 1` i `r_glVendor`/`gfxInfo` —
# renderer NVIDIA; w trakcie gry `gamemoded -s` -> "gamemode is active".
_: {
  flake.modules.nixos.gaming-thedarkmod =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.thedarkmod
        (pkgs.makeDesktopItem {
          name = "thedarkmod";
          desktopName = "The Dark Mod";
          comment = "Stealth game in the style of Thief";
          exec = "${lib.getExe' pkgs.gamemode "gamemoderun"} ${lib.getExe pkgs.thedarkmod}";
          icon = "thedarkmod";
          categories = [ "Game" ];
        })
      ];
    };
}

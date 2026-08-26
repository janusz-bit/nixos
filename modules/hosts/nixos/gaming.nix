_: {
  flake.modules.nixos.nixos-gaming =
    { pkgs, ... }:
    {
      programs = {
        # Gamescope: mikro-kompozytor Valve — lepszy frame pacing, skalowanie FSR,
        # izolacja gry od compositora. capSysNice = wyższy priorytet procesu gamescope.
        gamescope = {
          enable = false;
          capSysNice = true;
        };

        steam = {
          # Osobna sesja "Steam (Gamescope)" w SDDM
          gamescopeSession.enable = false;
          # Naprawa prefixów Wine/Proton (biblioteki, workaroundi per-gra)
          protontricks.enable = true;
        };

        # GameMode: tymczasowe przełączenie systemu w tryb wydajnościowy na czas gry
        # (uruchamiane przez `gamemoderun %command%` lub automatycznie przez Proton).
        gamemode = {
          enableRenice = true; # nadaje gamemoded CAP_SYS_NICE (wymagane dla ujemnego nice)
        };
      };

      environment.systemPackages = with pkgs; [
        mangohud # overlay FPS/frametime: `mangohud %command%` w opcjach startowych Steam
      ];
    };
}

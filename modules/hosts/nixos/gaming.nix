_: {
  flake.modules.nixos.nixos-gaming =
    { pkgs, ... }:
    {
      programs = {
        # Gamescope: mikro-kompozytor Valve — niski frame latency, VRR, skalowanie FSR/integer
        gamescope = {
          enable = true;
          package = pkgs.gamescope_git; # Najświeższy build z optymalizacjami Wayland / explicit sync
          capSysNice = true;
          args = [
            "--adaptive-sync"
            "--expose-wayland"
          ];
        };

        steam = {
          enable = true;
          # Osobna sesja "Steam (Gamescope)" w SDDM
          gamescopeSession.enable = true;
          # Naprawa prefixów Wine/Proton (biblioteki, workaroundi per-gra)
          protontricks.enable = true;
          remotePlay.openFirewall = true;
          dedicatedServer.openFirewall = true;
          extraCompatPackages = [
            pkgs.proton-cachyos_x86_64_v3 # Proton-CachyOS zoptymalizowany pod x86-64-v3 + ThinLTO + NTSYNC
            pkgs.proton-ge-custom # Najświeższy build Proton-GE zoptymalizowany pod Linuksa
            pkgs.luxtorpeda # Natywne silniki gier dla klasyków ze Steam zamiast powolnego Wine
          ];
        };

        # GameMode: dynamiczne zarządzanie priorytetami CPU/GPU i profili energetycznych
        gamemode = {
          enable = true;
          enableRenice = true; # nadaje gamemoded CAP_SYS_NICE (wymagane dla ujemnego nice)
          settings = {
            general = {
              renice = 10;
              softrealtime = "auto";
              inhibit_screensaver = 1;
            };
            gpu = {
              apply_gpu_optimisations = "accept-responsibility";
              gpu_device = 1; # Karta dedykowana NVIDIA w konfiguracji hybrydowej
              nv_perf_level_3 = 1;
            };
            custom = {
              start = "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Tryb wydajności aktywowany' -i input-gaming";
              end = "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Powrót do trybu standardowego' -i input-gaming";
            };
          };
        };
      };

      environment.systemPackages = with pkgs; [
        mangohud_git # Najświeższy overlay FPS/frametime z minimalnym narzutem na klatki
        goverlay # Graficzny konfigurator nakładki MangoHud
        pkgs.proton-cachyos_x86_64_v3 # Proton-CachyOS zoptymalizowany pod x86-64-v3
        low-latency-layer # Warstwa Vulkan redukująca opóźnienia wejścia (hardware-agnostic input latency reduction)
      ];
    };
}

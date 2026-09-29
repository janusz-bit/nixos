_: {
  flake.modules.nixos.nixos-gaming =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # GameMode → power-profiles-daemon: na czas gry profil "performance"
      # (platform_profile firmware Lenovo jak Fn+Q: wyższe limity mocy,
      # głośniejsze wentylatory + EPP "performance"), po grze przywraca
      # profil sprzed startu (np. power-saver na baterii).
      # gamemoded (usługa użytkownika) ma PATH zawężony do pkexec, więc
      # skrypt niesie własny PATH (runtimeInputs).
      gamemodePowerProfile = pkgs.writeShellApplication {
        name = "gamemode-power-profile";
        runtimeInputs = [
          pkgs.coreutils
          config.services.power-profiles-daemon.package
        ];
        text = ''
          state="$XDG_RUNTIME_DIR/gamemode-power-profile"
          case "$1" in
            start)
              powerprofilesctl get > "$state"
              powerprofilesctl set performance
              ;;
            end)
              prev=$(cat "$state" 2>/dev/null || true)
              rm -f "$state"
              powerprofilesctl set "''${prev:-balanced}"
              ;;
          esac
        '';
      };
    in
    {
      programs = {
        # Gamescope: mikro-kompozytor Valve — niski frame latency, VRR, skalowanie FSR/integer
        gamescope = {
          enable = false;
        };

        steam = {
          enable = true;
          # Osobna sesja "Steam (Gamescope)" w SDDM
          gamescopeSession.enable = false;
          # Naprawa prefixów Wine/Proton (biblioteki, workaroundi per-gra)
          protontricks.enable = true;
          remotePlay.openFirewall = true;
          extraCompatPackages = [
            pkgs.proton-cachyos_x86_64_v3 # Proton-CachyOS zoptymalizowany pod x86-64-v3 + ThinLTO + NTSYNC
          ];
        };

        # GameMode: dynamiczne zarządzanie priorytetami CPU/GPU i profili energetycznych.
        # Domyślnie (1.8.2) już: governor "performance", pinning gry na
        # P-rdzenie (hybryda P+E), wyłączona mitygacja split-lock, ioprio BE/0.
        gamemode = {
          enable = true;
          settings = {
            # nice -10 dla procesów gry (gamemoded ma CAP_SYS_NICE z wrappera NixOS).
            general.renice = 10;
            custom = lib.mkIf config.services.power-profiles-daemon.enable {
              start = "${lib.getExe gamemodePowerProfile} start";
              end = "${lib.getExe gamemodePowerProfile} end";
            };
          };
        };
      };

      boot = {
        # NTSYNC: synchronizacja NT w kernelu (/dev/ntsync, 0666). Wine 11 /
        # Proton-CachyOS 11 używa jej automatycznie, gdy urządzenie istnieje —
        # ale kernel CachyOS ma CONFIG_NTSYNC=m i nic nie ładuje modułu
        # (CachyOS robi to przez modules-load.d/ntsync.conf).
        kernelModules = [ "ntsync" ];

        # Wartości z CachyOS-Settings (70-cachyos-settings.conf).
        kernel.sysctl = {
          # Domyślnie 20%/10% RAM (~6/3 GB przy 32 GB): duże zrzuty zapisu
          # (pobieranie/aktualizacja w Steamie, cache shaderów) blokują I/O
          # i dają przycięcia w grze. Mniejsze, częstsze porcje writeback.
          "vm.dirty_bytes" = 268435456; # 256 MiB
          "vm.dirty_background_bytes" = 67108864; # 64 MiB
          # Watchdog NMI (HARDLOCKUP_DETECTOR_PERF): okresowe NMI na każdym
          # rdzeniu i zajęty licznik PMU — zbędne na desktopie.
          "kernel.nmi_watchdog" = 0;
        };
      };

      environment.systemPackages = [
        pkgs.low-latency-layer # Warstwa Vulkan redukująca opóźnienia wejścia (hardware-agnostic input latency reduction)
      ];
    };
}

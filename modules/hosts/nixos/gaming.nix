_: {
  flake.modules.nixos.nixos-gaming =
    { pkgs, ... }:
    {
      programs = {
        # Gamescope: mikro-kompozytor Valve — lepszy frame pacing, skalowanie FSR,
        # izolacja gry od compositora. capSysNice = wyższy priorytet procesu gamescope.
        gamescope = {
          enable = true;
          capSysNice = true;
        };

        steam = {
          # PRIME render offload (Optimus bez MUX-a): wewnętrzny ekran jest podpięty
          # przez iGPU Intela. Bez tych zmiennych Steam i WSZYSTKIE gry renderują na
          # słabym iGPU — gry działają wielokrotnie gorzej niż na Windowsie, który
          # przypisuje dGPU automatycznie. Moduł steam.nix merguje prev.extraEnv,
          # więc STEAM_EXTRA_COMPAT_TOOLS_PATHS itp. zostają zachowane.
          package = pkgs.steam.override {
            extraEnv = {
              __NV_PRIME_RENDER_OFFLOAD = "1";
              __VK_LAYER_NV_optimus = "NVIDIA_only";
              __GLX_VENDOR_LIBRARY_NAME = "nvidia";
              # NVAPI w Protonie — DLSS/Frame Generation na kartach RTX
              PROTON_ENABLE_NVAPI = "1";
            };
          };
          # Osobna sesja "Steam (Gamescope)" w SDDM
          gamescopeSession = {
            enable = true;
            # Sesja Gamescope też renderuje na dGPU (spójne z package.extraEnv)
            env = {
              __NV_PRIME_RENDER_OFFLOAD = "1";
              __VK_LAYER_NV_optimus = "NVIDIA_only";
              __GLX_VENDOR_LIBRARY_NAME = "nvidia";
            };
          };
          # Naprawa prefixów Wine/Proton (biblioteki, workaroundy per-gra)
          protontricks.enable = true;
        };

        # GameMode: tymczasowe przełączenie systemu w tryb wydajnościowy na czas gry
        # (uruchamiane przez `gamemoderun %command%` lub automatycznie przez Proton).
        gamemode = {
          enableRenice = true; # nadaje gamemoded CAP_SYS_NICE (wymagane dla ujemnego nice)
          settings = {
            general = {
              renice = 10; # gra dostaje nice -10 (użytkownik jest już w grupie gamemode)
              softrealtime = "auto";
              inhibit_screensaver = 1;
              desiredgov = "performance"; # governor performance na czas gry
            };
          };
        };
      };

      boot.kernel.sysctl = {
        # Duże mapowania pamięci — wymagane przez część gier (Star Citizen,
        # gry live-service, niektóre tytuły UE), inaczej crash przy ładowaniu.
        "vm.max_map_count" = 2147483642;
        # Bez kar wydajnościowych za split-lock (starsze gry/emulatory) — zamiast
        # dławienia rdzenia jądro tylko loguje zdarzenie.
        "kernel.split_lock_mitigate" = 0;
      };

      environment.systemPackages = with pkgs; [
        mangohud # overlay FPS/frametime: `mangohud %command%` w opcjach startowych Steam
      ];
    };
}

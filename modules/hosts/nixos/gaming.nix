_: {
  flake.modules.nixos.nixos-gaming =
    { pkgs, ... }:
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
          dedicatedServer.openFirewall = true;
          extraCompatPackages = [
            pkgs.proton-cachyos_x86_64_v3 # Proton-CachyOS zoptymalizowany pod x86-64-v3 + ThinLTO + NTSYNC
          ];
        };

        # GameMode: dynamiczne zarządzanie priorytetami CPU/GPU i profili energetycznych
        gamemode = {
          enable = true;
        };
      };

      environment.systemPackages = with pkgs; [
        pkgs.proton-cachyos_x86_64_v3 # Proton-CachyOS zoptymalizowany pod x86-64-v3
        low-latency-layer # Warstwa Vulkan redukująca opóźnienia wejścia (hardware-agnostic input latency reduction)
      ];
    };
}

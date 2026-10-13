# Steam z Protonem: Proton-CachyOS (x86-64-v3, z Chaotic-Nyx) jako narzędzie
# zgodności, protontricks, Remote Play, NTSYNC w kernelu i warstwa Vulkan
# low-latency-layer. GameMode i zmienne uruchamiania gier: gaming/gamemode.nix.
# Sprawdzenie: Steam → Ustawienia → Zgodność widzi „Proton-CachyOS x86-64-v3”;
# `ls -l /dev/ntsync`.
{ inputs, ... }:
{
  flake.modules.nixos.gaming-steam =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Chaotic-Nyx: overlay z bleeding-edge pakietami (proton-cachyos_x86_64_v3,
      # proton-ge-custom, mangohud_git...). Bez binary cache nyx: pakiety
      # z niego budują się lokalnie albo przychodzą z własnego cachix.
      imports = [ inputs.chaotic.nixosModules.default ];
      chaotic.nyx.cache.enable = false;

      programs.steam = {
        enable = true;
        # Hybryda iGPU + NVIDIA (PRIME offload): dGPU jako urządzenie Vulkan 0
        # w Steamie. Warstwa Mesy device-select stawia na początku GPU od
        # wyświetlacza (iGPU), a Steam prekompiluje shadery gier
        # (fossilize_replay --device-index 0) i wybiera bucket cache dla
        # urządzenia 0 — zmierzone 2026-10-12 na RTX 5060: ~190 tys.
        # pipeline'ów Deadlocka trafiło do mesa_shader_cache_sf, nvidiav1
        # pusty, a gra renderuje na NVIDII. Bez warstwy kolejność ustala
        # loader (dyskretne GPU pierwsze). EGL/GL (UI Steama) zostaje na iGPU;
        # __NV_PRIME_RENDER_OFFLOAD przeniósłby EGL na dGPU, a kolejności
        # urządzeń Vulkan nie zmienia (vulkaninfo). To samo FHS dostaje steam-run.
        package = lib.mkIf config.hardware.nvidia.prime.offload.enable (
          pkgs.steam.override { extraEnv.NODEVICE_SELECT = "1"; }
        );
        # Naprawa prefixów Wine/Proton (biblioteki, workaroundi per-gra)
        protontricks.enable = true;
        remotePlay.openFirewall = true;
        extraCompatPackages = [
          pkgs.proton-cachyos_x86_64_v3 # Proton-CachyOS zoptymalizowany pod x86-64-v3 + ThinLTO + NTSYNC
        ];
      };

      boot = {
        # NTSYNC: synchronizacja NT w kernelu (/dev/ntsync, 0666). Wine 11 /
        # Proton-CachyOS 11 używa jej automatycznie, gdy urządzenie istnieje —
        # ale kernel CachyOS ma CONFIG_NTSYNC=m i nic nie ładuje modułu
        # (CachyOS robi to przez modules-load.d/ntsync.conf).
        kernelModules = [ "ntsync" ];
        # dirty_bytes i nmi_watchdog (70-cachyos-settings.conf): desktop/tuning.nix.
      };

      environment.systemPackages = [
        pkgs.low-latency-layer # Warstwa Vulkan redukująca opóźnienia wejścia (hardware-agnostic input latency reduction)
      ];
    };
}

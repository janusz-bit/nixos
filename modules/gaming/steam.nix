# Steam z Protonem: Proton-CachyOS (x86-64-v3, z Chaotic-Nyx) jako narzędzie
# zgodności, protontricks, Remote Play, NTSYNC w kernelu i warstwa Vulkan
# low-latency-layer. GameMode i zmienne uruchamiania gier: gaming/gamemode.nix.
#
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
      # Chaotic-Nyx (proton-cachyos_x86_64_v3) bez cache nyx: jego pakiety budują
      # się lokalnie albo przychodzą z własnego cachix.
      imports = [ inputs.chaotic.nixosModules.default ];
      chaotic.nyx.cache.enable = false;

      programs.steam = {
        enable = true;
        # PRIME offload: Steam prekompiluje shadery (fossilize_replay --device-index 0)
        # dla urządzenia Vulkan 0, a warstwa Mesy device-select stawia tam iGPU od
        # wyświetlacza — zmierzone 2026-10-12: ~190 tys. pipeline'ów Deadlocka
        # w cache Mesy, nvidiav1 pusty, choć gra renderuje na NVIDII. Bez warstwy
        # dGPU jest pierwsze, a UI Steama (EGL/GL) zostaje na iGPU;
        # __NV_PRIME_RENDER_OFFLOAD przeniósłby EGL na dGPU, a kolejności urządzeń
        # Vulkan nie zmienia. To samo FHS dostaje steam-run.
        package = lib.mkIf config.hardware.nvidia.prime.offload.enable (
          pkgs.steam.override { extraEnv.NODEVICE_SELECT = "1"; }
        );
        protontricks.enable = true;
        remotePlay.openFirewall = true;
        extraCompatPackages = [ pkgs.proton-cachyos_x86_64_v3 ];
      };

      # NTSYNC: Wine/Proton 11 używa /dev/ntsync, gdy istnieje, a kernel CachyOS ma
      # CONFIG_NTSYNC=m bez ładowania (CachyOS: modules-load.d/ntsync.conf).
      boot.kernelModules = [ "ntsync" ];

      environment.systemPackages = [ pkgs.low-latency-layer ];
    };
}

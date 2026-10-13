# Dead by Daylight (appid 381210): wrapper w stylu gamemoderun, który
# uruchamia grę w DX11. W Launch Options Steama wpisz:  dbdrun %command%
# bez -dx12 (UE5 kończy się błędem, gdy dostanie dwa wymuszone RHI).
# Od patcha 7.7.0 (UE5, kwiecień 2024) DBD domyślnie renderuje w DX12, czyli
# pod Protonem przez vkd3d-proton — na NVIDII najwolniejszą ścieżkę
# (https://forums.developer.nvidia.com/t/directx12-performance-is-terrible-on-linux/303207 ,
# nadal otwarte; ścieżka descriptor heap z vkd3d-proton 3.0.1 jest tylko za
# VKD3D_CONFIG z powodu błędów NVIDII). -dx11 (wg PCGamingWiki nadal
# wspierane) przełącza grę na DXVK, przez które dobrze działa tu Deadlock.
# dGPU wybiera już GAMEMODERUNEXEC (configuration.nix,
# __VK_LAYER_NV_optimus=NVIDIA_only); wrapper, a nie zmienne sesji, bo Steam
# odpala go przy każdym starcie gry.
# Sprawdzenie: Launch Options `PROTON_LOG=1 dbdrun %command%`, w
# ~/steam-381210.log są "D3D11InternalCreateDevice: Using feature level"
# i "dxvk.enableNvRawAccessChains = False"; po meczu
# `journalctl -k | grep Xid` jest puste. A/B z DX12: `gamemoderun %command%`.
{
  flake.modules.nixos.gaming-dbd =
    { lib, pkgs, ... }:
    let
      # See temporary-fixes.md: w DX11 grę renderuje DXVK, więc grozi jej ten
      # sam zawias GPU co Deadlockowi (Xid 109 przez VK_NV_raw_access_chains na
      # NVIDIA 610/615, poprawki DXVK nie ma jeszcze w żadnym Protonie), a
      # zawieszony mecz to rozłączenie i kara w matchmakingu.
      # __GL_SHADER_DISK_CACHE_SKIP_CLEANUP: sterownik NVIDII nie przycina
      # cache shaderów (także Vulkan) po przekroczeniu limitu rozmiaru, więc
      # skompilowane pipeline'y zostają między sesjami.
      dbdrun = pkgs.writeShellApplication {
        name = "dbdrun";
        text = ''
          export DXVK_CONFIG="dxvk.enableNvRawAccessChains=False"
          export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
          exec ${lib.getExe' pkgs.gamemode "gamemoderun"} "$@" -dx11
        '';
      };
    in
    {
      environment.systemPackages = [ dbdrun ];
    };
}

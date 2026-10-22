# Dead by Daylight (appid 381210): wrapper na gamemoderun uruchamiający grę
# w DX11; Launch Options: `dbdrun %command%`, bez -dx12 (dwa wymuszone RHI to
# błąd UE5).
#
# Domyślne DX12 idzie pod Protonem przez vkd3d-proton, na NVIDII najwolniejszą
# ścieżką (https://forums.developer.nvidia.com/t/directx12-performance-is-terrible-on-linux/303207 ,
# nadal otwarte); -dx11 przełącza grę na DXVK, przez które dobrze działa tu
# Deadlock. dGPU wybiera GAMEMODERUNEXEC (gaming/gamemode.nix). Wrapper, a nie
# zmienne sesji, bo Steam odpala go przy każdym starcie tej jednej gry.
# Sprawdzenie: Launch Options `PROTON_LOG=1 dbdrun %command%`, w ~/steam-381210.log
# "D3D11InternalCreateDevice: Using feature level" i
# "dxvk.enableNvRawAccessChains = False"; po meczu `journalctl -k | grep Xid`
# puste. A/B z DX12: `gamemoderun %command%`.
_: {
  flake.modules.nixos.gaming-dbd =
    { lib, pkgs, ... }:
    let
      # DXVK_CONFIG tymczasowo (temporary-fixes.md nr 6): w DX11 renderuje DXVK,
      # więc grozi ten sam zawias GPU co w Deadlocku (Xid 109), a zawieszony mecz
      # to rozłączenie i kara w matchmakingu.
      # __GL_SHADER_DISK_CACHE_SKIP_CLEANUP: sterownik NVIDII nie przycina cache
      # shaderów (także Vulkan) po przekroczeniu limitu rozmiaru, więc
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

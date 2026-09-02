# Dead by Daylight (appid 381210): wrapper w stylu gamemoderun.
# W Launch Options Steama wpisz:  dbdrun %command%
# Zmienne trafiają do procesu gry, bo wrapper jest odpalany PRZEZ Steam
# (działa też, gdy Steam stoi od dawna - w przeciwieństwie do env z shella).
{
  flake.modules.nixos.nixos-dbd =
    { pkgs, ... }:
    let
      # Zmienne zweryfikowane z DXVK 2.7.1 w proton-cachyos (gaming.nix):
      #  DXVK_HIDE_INTEGRATED_GRAPHICS - hybryda Iris Xe + RTX 5060: DXVK ma używać dGPU
      #  DXVK_LOW_LATENCY=2            - NVIDIA Reflex (VK_NV_low_latency2), tryb + boost
      #  __GL_THREADED_OPTIMIZATIONS   - threaded optimization drivera NVIDIA
      #  __GL_SHADER_DISK_CACHE_SKIP_CLEANUP - nie usuwa cache shaderów (mniej stutterów)
      #  __GL_MaxFramesAllowed=1       - max 1 klatka w kolejce drivera (niższa latencja)
      # Na końcu przekazuje sterowanie do gamemoderun (governor "performance", renice,
      # screensaver inhibit) - jw. gaming.nix.
      dbdrun = pkgs.writeShellScriptBin "dbdrun" ''
        export DXVK_HIDE_INTEGRATED_GRAPHICS=1
        export DXVK_LOW_LATENCY=2
        export __GL_THREADED_OPTIMIZATIONS=1
        export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
        export __GL_MaxFramesAllowed=1
        # PowerMizer: preferuj maksymalną wydajność (na Waylandzie może być niedostępny)
        nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=1" >/dev/null 2>&1 || true
        exec ${pkgs.gamemode}/bin/gamemoderun "$@"
      '';
    in
    {
      environment.systemPackages = [
        dbdrun
      ];
    };
}

# OBS Studio z wtyczkami (przechwytywanie Wayland/PipeWire/Vulkan, usuwanie
# tła). Z NVIDIĄ wariant CUDA (koder NVENC, akceleracja usuwania tła); bez niej
# zwykły pakiet, bo pakietów CUDA nie ma w cache.nixos.org i budują się lokalnie
# (cudaCapabilities ustawia moduł sprzętu).
_: {
  flake.modules.nixos.desktop-obs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.obs-studio = {
        enable = true;
        package = lib.mkIf config.hardware.nvidia.enabled (
          pkgs.obs-studio.override { cudaSupport = true; }
        );
        plugins = with pkgs.obs-studio-plugins; [
          wlrobs
          obs-backgroundremoval
          obs-pipewire-audio-capture
          obs-gstreamer
          obs-vkcapture
        ];
      };
    };
}
